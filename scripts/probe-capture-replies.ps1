# probe-capture-replies.ps1 -- capture every reply datagram of ONE discovery request to disk
#
# Saves each reply payload as a separate .bin file so the datagrams can be diffed
# offline. Needed because a Civ6 LAN host answers one 4-byte request with a burst
# of 1104-byte datagrams whose contents differ, and the shape of that burst decides
# whether a Fake-IP layer can rewrite a single datagram or must handle a set.
#
# USAGE (game hosting a LAN room on this PC, no admin needed):
#   powershell -NoProfile -ExecutionPolicy Bypass -File probe-capture-replies.ps1 -OutDir ..\captures\x
param(
    [string]$OutDir = '',
    [int]$Seconds = 6,
    [int]$TargetPort = 62900
)

$ErrorActionPreference = 'Stop'
$magic = [byte[]](0x8d, 0xe8, 0xfc, 0x70)

if ([string]::IsNullOrWhiteSpace($OutDir)) {
    $OutDir = Join-Path $PSScriptRoot 'reply-capture'
}
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$sock = New-Object System.Net.Sockets.Socket(
    [System.Net.Sockets.AddressFamily]::InterNetwork,
    [System.Net.Sockets.SocketType]::Dgram,
    [System.Net.Sockets.ProtocolType]::Udp)
$sock.EnableBroadcast = $true
[void]$sock.SetSocketOption([System.Net.Sockets.SocketOptionLevel]::Socket,
                            [System.Net.Sockets.SocketOptionName]::ReuseAddress, $true)
[void]$sock.SetSocketOption([System.Net.Sockets.SocketOptionLevel]::IP,
                            [System.Net.Sockets.SocketOptionName]::PacketInformation, $true)
$sock.Bind((New-Object System.Net.IPEndPoint([System.Net.IPAddress]::Any, 0)))
$ep = $sock.LocalEndPoint

Write-Host ("local={0}:{1}  ->  255.255.255.255:{2}" -f $ep.Address, $ep.Port, $TargetPort)

$bcast = New-Object System.Net.IPEndPoint([System.Net.IPAddress]::Broadcast, $TargetPort)
$tSend = Get-Date
[void]$sock.SendTo($magic, $bcast)
Write-Host ("sent at {0}" -f $tSend.ToString('HH:mm:ss.fff'))

$deadline = (Get-Date).AddSeconds($Seconds)
$buf = New-Object byte[] 4096
$sha = [System.Security.Cryptography.SHA256]::Create()
$rows = New-Object System.Collections.ArrayList
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
    $file = Join-Path $OutDir ("reply-{0:d2}.bin" -f $n)
    [IO.File]::WriteAllBytes($file, $payload)
    $h = -join ($sha.ComputeHash($payload) | ForEach-Object { $_.ToString('x2') })
    $ms = ((Get-Date) - $tSend).TotalMilliseconds
    [void]$rows.Add([pscustomobject]@{
        Index = $n
        Ms    = [Math]::Round($ms, 1)
        From  = ('{0}:{1}' -f $remote.Address, $remote.Port)
        Len   = $got
        IfIdx = $pinfo.Interface
        Sha   = $h
        File  = (Split-Path $file -Leaf)
    })
}
$sock.Close()

Write-Host ("`ncaptured {0} datagram(s) into {1}" -f $n, $OutDir) -ForegroundColor Green
$rows | Format-Table -AutoSize Index, Ms, Len, IfIdx, File, @{n='Sha16'; e = { $_.Sha.Substring(0, 16) } } | Out-String -Width 200 | Write-Host

$rows | Export-Csv -Path (Join-Path $OutDir 'replies.csv') -NoTypeInformation -Encoding UTF8

# quick structural comparison: where do the payloads first differ?
if ($n -ge 2) {
    $a = [IO.File]::ReadAllBytes((Join-Path $OutDir 'reply-01.bin'))
    $b = [IO.File]::ReadAllBytes((Join-Path $OutDir 'reply-02.bin'))
    $len = [Math]::Min($a.Length, $b.Length)
    $firstDiff = -1
    for ($i = 0; $i -lt $len; $i++) { if ($a[$i] -ne $b[$i]) { $firstDiff = $i; break } }
    Write-Host ("`nfirst byte where reply-01 and reply-02 differ: {0}" -f $firstDiff)
    if ($firstDiff -ge 0) {
        $s = [Math]::Max(0, $firstDiff - 12)
        $e = [Math]::Min($len - 1, $firstDiff + 20)
        Write-Host ("  reply-01[{0}..{1}] = {2}" -f $s, $e, (($a[$s..$e] | ForEach-Object { $_.ToString('x2') }) -join ' '))
        Write-Host ("  reply-02[{0}..{1}] = {2}" -f $s, $e, (($b[$s..$e] | ForEach-Object { $_.ToString('x2') }) -join ' '))
        Write-Host ("  reply-01 as text : {0}" -f (([Text.Encoding]::UTF8.GetString($a, $s, ($e - $s + 1))) -replace '[^\x20-\x7e]', '.'))
        Write-Host ("  reply-02 as text : {0}" -f (([Text.Encoding]::UTF8.GetString($b, $s, ($e - $s + 1))) -replace '[^\x20-\x7e]', '.'))
    }

    # common prefix length across ALL payloads
    $minLen = ($rows | Measure-Object Len -Minimum).Minimum
    $all = @()
    for ($k = 1; $k -le $n; $k++) { $all += , ([IO.File]::ReadAllBytes((Join-Path $OutDir ("reply-{0:d2}.bin" -f $k)))) }
    $prefix = 0
    for ($i = 0; $i -lt $minLen; $i++) {
        $v = $all[0][$i]
        $same = $true
        for ($k = 1; $k -lt $all.Count; $k++) { if ($all[$k][$i] -ne $v) { $same = $false; break } }
        if (-not $same) { break }
        $prefix++
    }
    Write-Host ("common prefix across all {0} payloads: {1} bytes" -f $n, $prefix)
}
