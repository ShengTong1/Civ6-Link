# probe-reply-shape.ps1 -- characterise how a Civ6 LAN host answers ONE discovery request
#
# Records, for every reply datagram: arrival time, source endpoint, arrival
# interface, length, and SHA256 of the whole payload. Two questions it settles:
#   1. does one request produce exactly one reply, or a fixed burst?
#   2. are all replies byte-identical, or do they carry different content?
#
# USAGE (game hosting a LAN room on this PC, no admin needed):
#   powershell -NoProfile -ExecutionPolicy Bypass -File probe-reply-shape.ps1
#   powershell -NoProfile -ExecutionPolicy Bypass -File probe-reply-shape.ps1 -Repeat 3 -Seconds 6
param(
    [int]$Seconds = 6,
    [int]$Repeat = 1,
    [int]$TargetPort = 62900
)

$ErrorActionPreference = 'Stop'
$magic = [byte[]](0x8d, 0xe8, 0xfc, 0x70)

function New-ProbeSocket {
    $s = New-Object System.Net.Sockets.Socket(
        [System.Net.Sockets.AddressFamily]::InterNetwork,
        [System.Net.Sockets.SocketType]::Dgram,
        [System.Net.Sockets.ProtocolType]::Udp)
    $s.EnableBroadcast = $true
    [void]$s.SetSocketOption([System.Net.Sockets.SocketOptionLevel]::Socket,
                             [System.Net.Sockets.SocketOptionName]::ReuseAddress, $true)
    [void]$s.SetSocketOption([System.Net.Sockets.SocketOptionLevel]::IP,
                             [System.Net.Sockets.SocketOptionName]::PacketInformation, $true)
    $s.Bind((New-Object System.Net.IPEndPoint([System.Net.IPAddress]::Any, 0)))
    return $s
}

$sha = [System.Security.Cryptography.SHA256]::Create()

Write-Host ""
Write-Host "=== Civ6 LAN reply shape probe ===" -ForegroundColor Cyan
Write-Host ("host={0}  target port={1}  repeats={2}  window={3}s" -f $env:COMPUTERNAME, $TargetPort, $Repeat, $Seconds)

for ($round = 1; $round -le $Repeat; $round++) {
    $sock = New-ProbeSocket
    $ep = $sock.LocalEndPoint
    Write-Host ""
    Write-Host ("--- round {0}   local={1}:{2} ---" -f $round, $ep.Address, $ep.Port) -ForegroundColor Yellow

    $bcast = New-Object System.Net.IPEndPoint([System.Net.IPAddress]::Broadcast, $TargetPort)
    $tSend = Get-Date
    try { [void]$sock.SendTo($magic, $bcast) } catch { Write-Host ("  send failed: {0}" -f $_.Exception.Message) -ForegroundColor Red }
    Write-Host ("  sent 1 datagram of 4 bytes at {0}" -f $tSend.ToString('HH:mm:ss.fff'))

    $deadline = (Get-Date).AddSeconds($Seconds)
    $buf = New-Object byte[] 2048
    $n = 0
    while ((Get-Date) -lt $deadline) {
        if (-not $sock.Poll(150000, [System.Net.Sockets.SelectMode]::SelectRead)) { continue }
        $remote = New-Object System.Net.IPEndPoint([System.Net.IPAddress]::Any, 0)
        $flags = [System.Net.Sockets.SocketFlags]::None
        $pinfo = New-Object System.Net.Sockets.IPPacketInformation
        try { $got = $sock.ReceiveMessageFrom($buf, 0, $buf.Length, [ref]$flags, [ref]$remote, [ref]$pinfo) }
        catch { continue }
        if ($got -le 0) { continue }
        $n++
        $payload = New-Object byte[] $got
        [Array]::Copy($buf, 0, $payload, 0, $got)
        $h = -join ($sha.ComputeHash($payload) | ForEach-Object { $_.ToString('x2') })
        $dt = ((Get-Date) - $tSend).TotalMilliseconds
        Write-Host ("  #{0,2}  +{1,7:N1} ms  from {2}:{3}  len={4,4}  if={5}  sha256={6}" -f `
            $n, $dt, $remote.Address, $remote.Port, $got, $pinfo.Interface, $h.Substring(0, 16))
    }
    $sock.Close()
    Write-Host ("  => {0} reply packet(s) in {1}s" -f $n, $Seconds) -ForegroundColor Green
}
Write-Host ""
Read-Host "Press Enter to close"
