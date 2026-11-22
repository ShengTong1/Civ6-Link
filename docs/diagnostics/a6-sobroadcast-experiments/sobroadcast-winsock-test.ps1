# A-6 复核实验：原生 winsock setsockopt(SO_BROADCAST) 三段对照
# 动机：E1 日志显示 Civ6 调 setsockopt(SO_BROADCAST, val=0) 后 sendto(255.255.255.255) 成功(10013 未出现)。
#       原 sobroadcast-test.ps1 用 .NET Socket.SetSocketOption，非原生 winsock —— 本次用 P/Invoke 直接调 ws2_32。
# 用途：区分「Civ6 真实行为如此」 vs 「追踪器读 optval 有误」 vs 「.NET 封装差异」。
# 运行：powershell -NoProfile -ExecutionPolicy Bypass -File sobroadcast-winsock-test.ps1
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public static class Ws2 {
    [StructLayout(LayoutKind.Sequential)]
    public struct WSAData {
        public ushort wVersion; public ushort wHighVersion;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 256)] public string szDescription;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string szSystemStatus;
        public ushort iMaxSockets; public ushort iMaxUdpDg;
        public IntPtr lpVendorInfo;
    }
    [DllImport("ws2_32.dll", SetLastError = true, CallingConvention = CallingConvention.StdCall)]
    public static extern int WSAStartup(ushort version, out WSAData data);
    [DllImport("ws2_32.dll", SetLastError = true, CallingConvention = CallingConvention.StdCall)]
    public static extern IntPtr socket(int af, int type, int proto);
    [DllImport("ws2_32.dll", SetLastError = true, CallingConvention = CallingConvention.StdCall)]
    public static extern int setsockopt(IntPtr s, int level, int optname, ref int optval, int optlen);
    [DllImport("ws2_32.dll", SetLastError = true, CallingConvention = CallingConvention.StdCall)]
    public static extern int sendto(IntPtr s, byte[] buf, int len, int flags, ref SockAddrIn to, int tolen);
    [DllImport("ws2_32.dll", SetLastError = true, CallingConvention = CallingConvention.StdCall)]
    public static extern int closesocket(IntPtr s);

    [StructLayout(LayoutKind.Sequential)]
    public struct SockAddrIn {
        public short family;
        public ushort port;
        public uint addr;
        public long zero;
    }
}

public static class BcNative {
    public static string Run(int broadcastFlag, int dstPort) {
        const int AF_INET = 2, SOCK_DGRAM = 2, IPPROTO_UDP = 17;
        const int SOL_SOCKET = 0xFFFF, SO_BROADCAST = 0x20;
        Ws2.WSAData wd;
        int wsr = Ws2.WSAStartup(0x0202, out wd);
        if (wsr != 0) return "WSAStartup FAIL " + wsr;
        IntPtr s = Ws2.socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
        if (s.ToInt64() == -1) return "socket FAIL";
        string setResult = "not-set";
        if (broadcastFlag >= 0) {
            int v = broadcastFlag;
            int r = Ws2.setsockopt(s, SOL_SOCKET, SO_BROADCAST, ref v, 4);
            setResult = "set=" + broadcastFlag + " ret=" + r;
        }
        Ws2.SockAddrIn to = new Ws2.SockAddrIn();
        to.family = AF_INET;
        to.port = (ushort)((dstPort << 8) | (dstPort >> 8)); // htons
        to.addr = 0xFFFFFFFF; // 255.255.255.255
        to.zero = 0;
        byte[] payload = new byte[4] { 0x8d, 0xe8, 0xfc, 0x70 };
        int n = Ws2.sendto(s, payload, 4, 0, ref to, 16);
        string sendResult;
        if (n == -1) {
            int err = Marshal.GetLastWin32Error();
            sendResult = string.Format("sendto FAIL code={0} (WSAEACCES={1})", err, err == 10013);
        } else {
            sendResult = "sendto OK n=" + n;
        }
        Ws2.closesocket(s);
        return string.Format("{0} -> {1}", setResult, sendResult);
    }
}
'@
Write-Host "=== SO_BROADCAST 原生 winsock 微实验（P/Invoke，非 .NET 封装）==="
Write-Host ("不设置: " + [BcNative]::Run(-1, 62904))
Write-Host ("set=0:  " + [BcNative]::Run(0, 62905))
Write-Host ("set=1:  " + [BcNative]::Run(1, 62906))
