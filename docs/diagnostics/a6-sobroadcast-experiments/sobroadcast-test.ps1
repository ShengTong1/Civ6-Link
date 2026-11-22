# Micro-experiment: does sendto(255.255.255.255) succeed when SO_BROADCAST = 0 on this host?
# Motivation: E1 log shows Civ6 calls setsockopt(SO_BROADCAST, val=0) and then sendto(255.255.255.255)
#             returning ret=4 (success). That contradicts the classic WSAEACCES behaviour, so verify directly.

$ErrorActionPreference = 'Stop'

Add-Type -TypeDefinition @'
using System;
using System.Net;
using System.Net.Sockets;

public static class BcTest {
    public static string Run(int broadcastFlag, int dstPort) {
        // broadcastFlag: -1 = do not touch SO_BROADCAST, 0 = disable, 1 = enable
        using (var s = new Socket(AddressFamily.InterNetwork, SocketType.Dgram, ProtocolType.Udp)) {
            string setResult = "untouched";
            if (broadcastFlag >= 0) {
                try {
                    s.SetSocketOption(SocketOptionLevel.Socket, SocketOptionName.Broadcast, broadcastFlag != 0);
                    setResult = "set=" + broadcastFlag;
                } catch (Exception ex) {
                    setResult = "setthrew=" + ex.GetType().Name;
                }
            }
            var payload = new byte[] { 0x8d, 0xe8, 0xfc, 0x70 };
            var ep = new IPEndPoint(IPAddress.Broadcast, dstPort);
            try {
                int n = s.SendTo(payload, ep);
                return string.Format("{0} -> sendto OK n={1}", setResult, n);
            } catch (SocketException ex) {
                return string.Format("{0} -> sendto FAIL code={1} ({2})", setResult, ex.SocketErrorCode, (int)ex.SocketErrorCode);
            }
        }
    }
}
'@

Write-Host "=== SO_BROADCAST micro-experiment ==="
Write-Host ("untouched     : " + [BcTest]::Run(-1, 62901))
Write-Host ("SO_BROADCAST=0: " + [BcTest]::Run(0, 62902))
Write-Host ("SO_BROADCAST=1: " + [BcTest]::Run(1, 62903))

Write-Host ""
Write-Host "=== local IPv4 addresses (relevant to interface selection) ==="
Get-NetIPAddress -AddressFamily IPv4 |
    Where-Object { $_.IPAddress -ne '127.0.0.1' } |
    Select-Object IPAddress, InterfaceAlias, PrefixLength |
    Format-Table -AutoSize
