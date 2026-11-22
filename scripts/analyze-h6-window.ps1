# analyze-h6-window.ps1 -- compute H6 discovery socket lifetime from a civtrace log
#
# Purpose (E2-B, README section 4):
#   For every discovery round (one burst of sendto 255.255.255.255:62900..62999),
#   derive per-round:
#     T_first_bcast  t of first sendto of the round
#     T_last_bcast   t of last  sendto of the round
#     T_first_resp   t of first  recvfrom on the same socket (if any)
#     T_last_resp    t of last   recvfrom on the same socket (if any)
#     T_close        t of closesocket on the same socket (if any)
#     T_window       T_close - T_first_bcast     <- H6 key number
#     T_response     T_first_resp - T_first_bcast
#     T_resp_close   T_close - T_last_resp
#   Then print the distribution (min/p50/p90/max + full table) and, when a
#   relay RTT target is supplied, how many rounds had room for it.
#
# Why this exists:
#   H6 = "does the discovery socket stay open long enough for a +20~50 ms relay
#   round trip?"  Previously this had to be eyeballed from a 60 MB log. This
#   script makes the number reproducible and lets E2-B run the 10-refresh
#   distribution without manual log reading.
#
# Times are taken from the log's own QPC column (100 ns ticks, same clock for
# every line of one process), NOT from the wall-clock prefix, so the numbers are
# immune to log flush ordering.
#
# ASCII-only on purpose: PowerShell 5.1 decodes BOM-less .ps1 as the ANSI
# codepage, so non-ASCII comments break parsing. Keep this file ASCII.
#
# Usage:
#   powershell -NoProfile -ExecutionPolicy Bypass -File analyze-h6-window.ps1 `
#       -Log C:\Users\dd\AppData\Local\CivLink\M0A\logs\civtrace_..._pidN_client.log `
#       -RelayRttMs 50 [-Csv out.csv] [-RoundGapMs 500]
#
# Exit codes: 0 = rounds found, 2 = no discovery round found, 3 = bad input.

param(
    [Parameter(Mandatory = $true)][string]$Log,
    [double]$RelayRttMs = 50,
    [string]$Csv = '',
    [int]$RoundGapMs = 500,
    [double]$BurstGapMs = 20
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path $Log)) { Write-Host "ERROR log not found: $Log"; exit 3 }
$Log = [IO.Path]::GetFullPath($Log)

# --- one pass over the log, keep only lines we need -------------------------
# Line shapes (from trace_dll.cpp emit formats):
#   15:14:11.624 qpc=1072649945387 #011251 tid=49976 sendto s=0x868 af=2 type=2 dst=255.255.255.255:62900 len=4 ret=4 data=8d e8 fc 70 caller=...
#   15:14:13.645 qpc=1072670157907 #011545 tid=49976 closesocket s=0x868 af=2 type=2 ret=0 caller=...
#   ... recvfrom s=0x868 ret=1104 src=... len=1104 ...
$reSend = '^(\d+):(\d+):(\d+)\.(\d+)\s+qpc=(\d+)\s+#(\d+)\s+tid=(\d+)\s+sendto\s+s=(0x[0-9a-fA-F]+).*dst=255\.255\.255\.255:(\d+)'
$reRecv = '^(\d+):(\d+):(\d+)\.(\d+)\s+qpc=(\d+)\s+#(\d+)\s+tid=(\d+)\s+recvfrom\s+(.*)$'
$reClose = '^(\d+):(\d+):(\d+)\.(\d+)\s+qpc=(\d+)\s+#(\d+)\s+tid=(\d+)\s+closesocket\s+s=(0x[0-9a-fA-F]+)'

$sends = New-Object System.Collections.Generic.List[object]
$recvs = New-Object System.Collections.Generic.List[object]
$closes = New-Object System.Collections.Generic.List[object]

$sr = New-Object IO.StreamReader($Log)
try {
    while ($null -ne ($line = $sr.ReadLine())) {
        # cheap pre-filter first, regex second
        if ($line.IndexOf('dst=255.255.255.255:') -ge 0) {
            $m = [regex]::Match($line, $reSend)
            if ($m.Success) {
                $sends.Add([pscustomobject]@{
                    qpc = [int64]$m.Groups[5].Value
                    sock = $m.Groups[8].Value
                    port = [int]$m.Groups[9].Value
                })
            }
            continue
        }
        if ($line.IndexOf(' recvfrom ') -ge 0) {
            $m = [regex]::Match($line, $reRecv)
            if ($m.Success) {
                $rest = $m.Groups[8].Value
                $sock = ''
                $sm = [regex]::Match($rest, 's=(0x[0-9a-fA-F]+)')
                if ($sm.Success) { $sock = $sm.Groups[1].Value }
                $lenv = -1
                $lm = [regex]::Match($rest, 'len=(\d+)')
                if ($lm.Success) { $lenv = [int]$lm.Groups[1].Value }
                $recvs.Add([pscustomobject]@{
                    qpc = [int64]$m.Groups[5].Value
                    sock = $sock
                    len = $lenv
                })
            }
            continue
        }
        if ($line.IndexOf(' closesocket ') -ge 0) {
            $m = [regex]::Match($line, $reClose)
            if ($m.Success) {
                $closes.Add([pscustomobject]@{
                    qpc = [int64]$m.Groups[5].Value
                    sock = $m.Groups[8].Value
                })
            }
        }
    }
}
finally { $sr.Close() }

Write-Host ("log        : {0}" -f $Log)
Write-Host ("size       : {0:N0} bytes" -f (Get-Item $Log).Length)
Write-Host ("sendto 255 : {0}" -f $sends.Count)
Write-Host ("recvfrom   : {0}" -f $recvs.Count)
Write-Host ("closesocket: {0}" -f $closes.Count)

if ($sends.Count -eq 0) {
    Write-Host ''
    Write-Host 'NO DISCOVERY ROUND: no sendto to 255.255.255.255 was logged.' -ForegroundColor Yellow
    Write-Host 'Possibilities (do not guess, check which one applies):'
    Write-Host '  - this process never entered the LAN lobby / never pressed refresh'
    Write-Host '  - the log belongs to the host role, whose broadcast happens at create-room time only'
    Write-Host '  - the injection happened after the discovery phase had already run'
    exit 2
}

# --- split into rounds ------------------------------------------------------
# A round = consecutive sends (same socket) whose qpc gaps are <= BurstGapMs,
# and a new round starts if the socket changes or the idle gap is > RoundGapMs.
$sendsSorted = $sends | Sort-Object qpc
$rounds = New-Object System.Collections.Generic.List[object]
$cur = $null
$prev = $null
foreach ($s in $sendsSorted) {
    $newRound = $false
    if ($null -eq $prev) { $newRound = $true }
    elseif ($s.sock -ne $prev.sock) { $newRound = $true }
    else {
        $gapMs = ($s.qpc - $prev.qpc) / 10000.0
        if ($gapMs -gt $RoundGapMs) { $newRound = $true }
    }
    if ($newRound) {
        if ($null -ne $cur) { $rounds.Add($cur) }
        $cur = [pscustomobject]@{
            sock = $s.sock
            first = $s.qpc
            last = $s.qpc
            count = 0
            ports = New-Object System.Collections.Generic.HashSet[int]
        }
    }
    $cur.last = $s.qpc
    $cur.count = $cur.count + 1
    [void]$cur.ports.Add($s.port)
    $prev = $s
}
if ($null -ne $cur) { $rounds.Add($cur) }

Write-Host ("rounds     : {0}" -f $rounds.Count)

# --- attach responses and closes per round ---------------------------------
$rows = New-Object System.Collections.Generic.List[object]
$i = 0
foreach ($r in $rounds) {
    $i++
    # responses on the same socket, inside [first, close-or-first+10s]
    $closeQpc = $null
    $c = $closes | Where-Object { $_.sock -eq $r.sock -and $_.qpc -ge $r.first } | Sort-Object qpc | Select-Object -First 1
    if ($null -ne $c) { $closeQpc = $c.qpc }
    $horizon = if ($null -ne $closeQpc) { $closeQpc } else { $r.first + (10000 * 10000) }

    $resp = $recvs | Where-Object { $_.sock -eq $r.sock -and $_.qpc -ge $r.first -and $_.qpc -le $horizon } | Sort-Object qpc
    $firstResp = $null; $lastResp = $null; $respCount = 0; $respLen = 0
    if ($null -ne $resp -and $resp.Count -gt 0) {
        $firstResp = $resp[0].qpc
        $lastResp = $resp[$resp.Count - 1].qpc
        $respCount = $resp.Count
        $respLen = $resp[0].len
    }

    $burstMs = ($r.last - $r.first) / 10000.0
    $tWindowMs = if ($null -ne $closeQpc) { ($closeQpc - $r.first) / 10000.0 } else { $null }
    $tRespMs = if ($null -ne $firstResp) { ($firstResp - $r.first) / 10000.0 } else { $null }
    $tRespCloseMs = if ($null -ne $closeQpc -and $null -ne $lastResp) { ($closeQpc - $lastResp) / 10000.0 } else { $null }

    $rows.Add([pscustomobject]@{
        round = $i
        socket = $r.sock
        sends = $r.count
        ports = $r.ports.Count
        burst_ms = [math]::Round($burstMs, 3)
        window_ms = if ($null -ne $tWindowMs) { [math]::Round($tWindowMs, 3) } else { $null }
        response_ms = if ($null -ne $tRespMs) { [math]::Round($tRespMs, 3) } else { $null }
        responses = $respCount
        response_len = $respLen
        resp_to_close_ms = if ($null -ne $tRespCloseMs) { [math]::Round($tRespCloseMs, 3) } else { $null }
        closed = ($null -ne $closeQpc)
    })
}

# --- report ----------------------------------------------------------------
Write-Host ''
$fmt = '{0,5}  {1,-8}  {2,5}  {3,5}  {4,9}  {5,10}  {6,10}  {7,6}  {8,6}  {9,11}  {10,6}'
Write-Host ($fmt -f 'round', 'socket', 'sends', 'ports', 'burst_ms', 'window_ms', 'resp_ms', 'respN', 'len', 'resp2close', 'closed')
Write-Host ('-' * 110)
foreach ($r in $rows) {
    Write-Host ($fmt -f $r.round, $r.socket, $r.sends, $r.ports, $r.burst_ms,
        ($(if ($null -eq $r.window_ms) { 'n/a' } else { $r.window_ms })),
        ($(if ($null -eq $r.response_ms) { 'n/a' } else { $r.response_ms })),
        $r.responses, $r.response_len,
        ($(if ($null -eq $r.resp_to_close_ms) { 'n/a' } else { $r.resp_to_close_ms })),
        $r.closed)
}

function Get-Stats($values) {
    $v = @($values | Where-Object { $null -ne $_ } | Sort-Object)
    if ($v.Count -eq 0) { return $null }
    $p50 = $v[[math]::Floor(($v.Count - 1) * 0.50)]
    $p90 = $v[[math]::Floor(($v.Count - 1) * 0.90)]
    return [pscustomobject]@{
        n = $v.Count
        min = $v[0]
        p50 = $p50
        p90 = $p90
        max = $v[$v.Count - 1]
    }
}

$w = Get-Stats ($rows | ForEach-Object { $_.window_ms })
$resp = Get-Stats ($rows | ForEach-Object { $_.response_ms })

Write-Host ''
Write-Host '=== H6: discovery socket lifetime ===' -ForegroundColor Cyan
if ($null -eq $w) {
    Write-Host 'window_ms: no round was closed inside the log (still open at end of capture).' -ForegroundColor Yellow
    Write-Host 'A still-open window is an upper bound only: the process was probably injected and'
    Write-Host 'logged while the lobby socket was still polling. Re-run with a log that covers'
    Write-Host 'the closesocket, or note "window >= observed span" in the report.'
}
else {
    Write-Host ("window_ms: n={0} min={1} p50={2} p90={3} max={4}" -f $w.n, $w.min, $w.p50, $w.p90, $w.max)
    $fits = @($rows | Where-Object { $null -ne $_.window_ms -and $_.window_ms -ge $RelayRttMs }).Count
    $closedRows = @($rows | Where-Object { $null -ne $_.window_ms }).Count
    Write-Host ("relay target {0} ms : {1}/{2} closed rounds have window >= target" -f $RelayRttMs, $fits, $closedRows)
    if ($fits -eq $closedRows -and $closedRows -gt 0) {
        Write-Host 'verdict: the authorised +20~50 ms relay RTT fits inside every observed window.' -ForegroundColor Green
    }
    elseif ($fits -eq 0) {
        Write-Host 'verdict: NO closed round fits the relay target - the relay design would lose the response.' -ForegroundColor Red
    }
    else {
        Write-Host 'verdict: MIXED - some windows are shorter than the relay target.' -ForegroundColor Yellow
    }
}

if ($null -ne $resp) {
    Write-Host ("response_ms: n={0} min={1} p50={2} p90={3} max={4}" -f $resp.n, $resp.min, $resp.p50, $resp.p90, $resp.max)
    Write-Host ("responses total: {0} (expect 22 per served round x rounds)" -f ($rows | Measure-Object -Property responses -Sum).Sum)
}
else {
    Write-Host 'response_ms: no round received any recvfrom on its discovery socket.' -ForegroundColor Yellow
    Write-Host 'Expected when the round produced no host reply (e.g. client role with no host up).'
}

Write-Host ''
Write-Host '=== notes for the report ==='
Write-Host '1. Times use the log QPC column (100 ns ticks, one clock per process).'
Write-Host '2. window_ms is measured from the FIRST sendto, per README section 4.'
Write-Host '3. A round with sends=100 ports=100 is a full 62900..62999 sweep.'
Write-Host '4. Rounds that never received recvfrom still count for H6 window stats.'
Write-Host '5. This script never modifies the log and never touches the network.'

if ($Csv -ne '') {
    $Csv = [IO.Path]::GetFullPath($Csv)
    $dir = Split-Path -Parent $Csv
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $rows | Export-Csv -Path $Csv -NoTypeInformation -Encoding UTF8
    Write-Host ("csv written: {0}" -f $Csv)
}

exit 0
