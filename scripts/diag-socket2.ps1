Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class Ws2c {
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
    public static extern int WSAGetLastError();
    [DllImport("ws2_32.dll", SetLastError = true, CallingConvention = CallingConvention.StdCall)]
    public static extern int closesocket(IntPtr s);
}
'@
$ws = New-Object Ws2c+WSAData
$r = [Ws2c]::WSAStartup(0x0202, [ref]$ws)
Write-Host ("WSAStartup ret={0}" -f $r)
$s = [Ws2c]::socket(2,2,17)
$raw = $s.ToInt64()
Write-Host ("socket raw={0} invalid={1} err={2}" -f $raw, ($raw -eq -1), [Ws2c]::WSAGetLastError())
