# probe-discovery-reply.ps1 -- send a Civ6 LAN discovery request and capture the FULL reply
#
# WHY: the E2-A pcapng was captured with pktmon --pkt-size 128, so the 1146-byte
# host reply frame was truncated to 128 bytes = only 86 of 1104 UDP payload bytes.
# That is enough to read the AppID and the room name but NOT enough to decide
# whether the host address lives in the payload or only in the IP source address
# (hypothesis H4), because the remaining 1018 bytes were never captured.
#
# HOW: this needs ONE machine only. If Civilization VI is hosting a LAN room on
# the same PC, it answers discovery requests on port 62900. This script sends the
# exact 4-byte discovery magic (8d e8 fc 70) to 255.255.255.255 ports
# 62900..62999 from an ephemeral port, then receives the unicast reply on that
# same socket. A normal UDP receive is not truncated, so the whole 1104-byte
# payload arrives. No pktmon, no administrator, no second machine.
#
# USAGE (game must already be hosting a LAN room):
#   powershell -NoProfile -ExecutionPolicy Bypass -File probe-discovery-reply.ps1
#   powershell -NoProfile -ExecutionPolicy Bypass -File probe-discovery-reply.ps1 -Seconds 10
param(
    [int]$Seconds = 8
)

$ErrorActionPreference = 'Stop'

$magic = [byte[]](0x8d, 0xe8, 0xfc, 0x70)

$sock = New-Object System.Net.Sockets.Socket(
    [System.Net.Sockets.AddressFamily]::InterNetwork,
    [System.Net.Sockets.SocketType]::Dgram,
    [System.Net.Sockets.ProtocolType]::Udp)

# UdpClient-free path so we can ask for PacketInformation (arrival interface).
$sock.EnableBroadcast = $true
[void]$sock.SetSocketOption([System.Net.Sockets.SocketOptionLevel]::Socket,
                            [System.Net.Sockets.SocketOptionName]::ReuseAddress, $true)
[void]$sock.SetSocketOption([System.Net.Sockets.SocketOptionLevel]::IP,
                            [System.Net.Sockets.SocketOptionName]::PacketInformation, $true)

$sock.Bind((New-Object System.Net.IPEndPoint([System.Net.IPAddress]::Any, 0)))
$localEp = $sock.LocalEndPoint
Write-Host ""
Write-Host "=== Civ6 LAN discovery reply probe ===" -ForegroundColor Cyan
Write-Host ("host        : {0}" -f $env:COMPUTERNAME)
Write-Host ("local endp  : {0}:{1}   (ephemeral, unbound to a fixed port)" -f $localEp.Address, $localEp.Port)
Write-Host ("payload     : 4 bytes 8d e8 fc 70")
Write-Host ("target      : 255.255.255.255 ports 62900..62999  (100 sends)")
Write-Host ""

$sent = 0
$fail = 0
$bcast = New-Object System.Net.IPEndPoint([System.Net.IPAddress]::Broadcast, 0)
for ($port = 62900; $port -le 62999; $port++) {
    $bcast.Port = $port
    try { [void]$sock.SendTo($magic, $bcast); $sent++ }
    catch { $fail++ }
}
Write-Host ("sent={0}  fail={1}" -f $sent, $fail) -ForegroundColor Green
Write-Host ("waiting {0}s for replies ..." -f $Seconds) -ForegroundColor Yellow

$deadline = (Get-Date).AddSeconds($Seconds)
$buf = New-Object byte[] 2048
$replies = New-Object System.Collections.ArrayList

while ((Get-Date) -lt $deadline) {
    if (-not $sock.Poll(200000, [System.Net.Sockets.SelectMode]::SelectRead)) { continue }
    $ep = New-Object System.Net.IPEndPoint([System.Net.IPAddress]::Any, 0)
    $flags = [System.Net.Sockets.SocketFlags]::None
    $pinfo = New-Object System.Net.Sockets.IPPacketInformation
    try {
        $n = $sock.ReceiveMessageFrom($buf, 0, $buf.Length, [ref]$flags, [ref]$ep, [ref]$pinfo)
    }
    catch { continue }
    if ($n -le 0) { continue }
    $data = New-Object byte[] $n
    [Array]::Copy($buf, 0, $data, 0, $n)
    $hex = -join ($data | ForEach-Object { $_.ToString('x2') })
    [void]$replies.Add([pscustomobject]@{
        Time    = (Get-Date).ToString('HH:mm:ss.fff')
        From    = ('{0}:{1}' -f $ep.Address, $ep.Port)
        IfIndex = $pinfo.Interface
        Len     = $n
        Hex     = $hex
    })
    Write-Host ("  <- {0}  from {1}  len={2}  if={3}" -f (Get-Date).ToString('HH:mm:ss.fff'), ('{0}:{1}' -f $ep.Address, $ep.Port), $n, $pinfo.Interface) -ForegroundColor Gray
}

$sock.Close()

Write-Host ""
if ($replies.Count -eq 0) {
    Write-Host "NO REPLY RECEIVED" -ForegroundColor Red
    Write-Host ""
    Write-Host "Checklist:" -ForegroundColor Yellow
    Write-Host "  - is Civilization VI actually HOSTING a LAN room on this PC?"
    Write-Host "    (Multiplayer -> LAN -> Create/Host game; sitting in the lobby is not enough"
    Write-Host "     if the room was never created)"
    Write-Host "  - is a firewall blocking inbound UDP on the ephemeral port?"
    Write-Host "  - try -Seconds 15"
    exit 2
}

Write-Host ("=== {0} reply packet(s) ===" -f $replies.Count) -ForegroundColor Cyan
$byTuple = $replies | Group-Object From
foreach ($g in $byTuple) {
    $one = $g.Group[0]
    Write-Host ("from {0}  count={1}  len={2}  ifIndex={3}" -f $g.Name, $g.Count, $one.Len, $one.IfIndex)
}

$first = $replies[0]
Write-Host ""
Write-Host ("--- payload of first reply: {0} bytes ---" -f $first.Len)
$bytes = New-Object byte[] $first.Len
for ($i = 0; $i -lt $first.Len; $i++) { $bytes[$i] = [Convert]::ToByte($first.Hex.Substring($i * 2, 2), 16) }

# print hex in 16-byte rows with an ASCII gutter
for ($r = 0; $r -lt $bytes.Length; $r += 16) {
    $end = [Math]::Min($r + 15, $bytes.Length - 1)
    $hx = ($r..$end | ForEach-Object { $bytes[$_].ToString('x2') }) -join ' '
    $asc = -join ($r..$end | ForEach-Object {
        $c = $bytes[$_]
        if ($c -ge 32 -and $c -lt 127) { [char]$c } else { '.' }
    })
    Write-Host ("  {0,4}  {1,-47}  {2}" -f $r, $hx, $asc)
}

Write-Host ""
Write-Host "--- field scan ---"
Write-Host ("  total payload bytes : {0}" -f $bytes.Length)
for ($o = 0; $o -le [Math]::Min(28, $bytes.Length - 4); $o += 4) {
    $u32 = [BitConverter]::ToUInt32($bytes, $o)
    $note = ''
    if ($u32 -eq 289070) { $note = '  <== Civilization VI Steam AppID' }
    Write-Host ("  off={0,4}  u32LE={1,-12}{2}" -f $o, $u32, $note)
}

# UTF-8 string right after the header block (offset 24 as observed in E2-A)
if ($bytes.Length -gt 24) {
    $tail = New-Object byte[] ($bytes.Length - 24)
    [Array]::Copy($bytes, 24, $tail, 0, $tail.Length)
    $nz = 0
    while ($nz -lt $tail.Length -and $tail[$nz] -ne 0) { $nz++ }
    if ($nz -gt 0) {
        $s = [System.Text.Encoding]::UTF8.GetString($tail, 0, $nz)
        Write-Host ""
        Write-Host ("  utf8 @ off24 ({0} bytes): {1}" -f $nz, $s)
    }
    $zerosAfter = 0
    for ($i = 24 + $nz; $i -lt $bytes.Length; $i++) { if ($bytes[$i] -eq 0) { $zerosAfter++ } else { break } }
    Write-Host ("  zero padding after string: {0} bytes of {1} remaining" -f $zerosAfter, ($bytes.Length - 24 - $nz))
}

# does any IPv4-looking dotted quad appear in the payload?
Write-Host ""
Write-Host "--- IPv4 address scan inside payload ---"
$found = $false
for ($i = 0; $i -le $bytes.Length - 4; $i++) {
    $a = $bytes[$i]; $b = $bytes[$i + 1]; $c = $bytes[$i + 2]; $d = $bytes[$i + 3]
    $isPrivate = ($a -eq 192 -and $b -eq 168) -or ($a -eq 10) -or ($a -eq 172 -and $b -ge 16 -and $b -le 31) -or ($a -eq 26) -or ($a -eq 127)
    if ($isPrivate -and $c -ne 0 -and $d -ne 0) {
        Write-Host ("  off={0,4}  possible IPv4 = {1}.{2}.{3}.{4}" -f $i, $a, $b, $c, $d) -ForegroundColor Yellow
        $found = $true
    }
}
if (-not $found) { Write-Host "  none found (no 192.168/10/172.16-31/26/127 dotted quad in the payload)" }

Write-Host ""
Write-Host "--- H4 verdict input ---"
Write-Host "  If the scan above found NO address, the host address the client uses can only"
Write-Host "  come from the IP/UDP source address of this reply. If it DID find one at a"
Write-Host "  stable offset, a Fake-IP design must rewrite the payload too."
Write-Host ""
Read-Host "Press Enter to close"
