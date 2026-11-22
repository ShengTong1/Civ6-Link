Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class Ws2b {
    [DllImport("ws2_32.dll", SetLastError = true)]
    public static extern IntPtr socket(int af, int type, int proto);
    [DllImport("ws2_32.dll", SetLastError = true)]
    public static extern int WSAGetLastError();
}
'@
$s = [Ws2b]::socket(2,2,17)
Write-Host ("raw socket handle: {0}" -f $s)
Write-Host ("IsInvalid={0}" -f ($s -eq [IntPtr](-1)))
Write-Host ("lastError={0}" -f [Ws2b]::WSAGetLastError())
