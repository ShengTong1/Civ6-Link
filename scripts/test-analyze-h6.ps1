# test-analyze-h6.ps1 -- regression test for analyze-h6-window.ps1
#
# Purpose: prove the H6 analyzer classifies the three cases that matter before it
# is used on a real E2-B log:
#   A. full round with responses  -> window/response computed, relay target judged per-round
#   B. round shorter than the relay target -> must be reported as not fitting (MIXED, not PASS)
#   C. log with no broadcast at all -> exit 2 with the "no discovery round" message
#
# The test builds its own synthetic logs, so it needs no game and no network.
#
# QPC unit used by civtrace is 100 ns, so 1 ms = 10000 ticks. Getting this wrong is
# the single easiest way to produce a nonsense window number, which is why the test
# asserts exact milliseconds instead of "roughly right".
#
# ASCII-only on purpose: PowerShell 5.1 decodes BOM-less .ps1 as the ANSI codepage.
#
# Usage:
#   powershell -NoProfile -ExecutionPolicy Bypass -File test-analyze-h6.ps1
# Exit codes: 0 = all assertions passed, 1 = at least one failed.

$ErrorActionPreference = 'Stop'

$here = $PSScriptRoot
$analyzer = Join-Path $here 'analyze-h6-window.ps1'
if (-not (Test-Path $analyzer)) { Write-Host "ERROR analyzer not found: $analyzer"; exit 1 }

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$work = Join-Path (Split-Path -Parent (Split-Path -Parent $here)) "M0A\captures\h6-selftest-$stamp"
New-Item -ItemType Directory -Force -Path $work | Out-Null
Write-Host "work dir : $work"
Write-Host "analyzer : $analyzer"
Write-Host ''

$MS = 10000          # QPC ticks per millisecond (100 ns ticks)
$results = New-Object System.Collections.Generic.List[object]

function Add-Result([string]$name, [bool]$ok, [string]$detail) {
    $script:results.Add([pscustomobject]@{ name = $name; ok = $ok; detail = $detail })
    $tag = if ($ok) { 'PASS' } else { 'FAIL' }
    $color = if ($ok) { 'Green' } else { 'Red' }
    Write-Host ("[{0}] {1}  {2}" -f $tag, $name, $detail) -ForegroundColor $color
}

function New-BurstLog {
    param(
        [string]$Path,
        [string]$Socket,
        [int]$PortCount,
        [int64]$StartQpc,
        [int]$WindowMs,
        [int]$ResponseCount,
        [int]$ResponseAfterMs,
        [int]$BurstSpanMs
    )
    $L = New-Object System.Collections.Generic.List[string]
    $L.Add('15:00:00.000 qpc=' + $StartQpc + ' #000001 tid=999 ===== civtrace 0.4.4 session start =====')
    $seq = 2
    $step = if ($PortCount -gt 1) { [int](($BurstSpanMs * $MS) / $PortCount) } else { 0 }
    $q = $StartQpc - $step      # first send lands exactly on StartQpc
    for ($i = 0; $i -lt $PortCount; $i++) {
        $q = $q + $step
        $port = 62900 + $i
        $L.Add('15:00:00.100 qpc=' + $q + ' #' + $seq.ToString('D6') + ' tid=999 sendto s=' + $Socket +
            ' af=2 type=2 dst=255.255.255.255:' + $port + ' len=4 ret=4 data=8d e8 fc 70 caller=X.exe+0x1')
        $seq++
    }
    if ($ResponseCount -gt 0) {
        $rq = $StartQpc + ([int64]$ResponseAfterMs * $MS)
        for ($i = 1; $i -le $ResponseCount; $i++) {
            $L.Add('15:00:00.112 qpc=' + ($rq + $i * 100) + ' #' + $seq.ToString('D6') + ' tid=999 recvfrom s=' +
                $Socket + ' ret=1104 src=192.168.31.214:62900 len=1104 caller=X.exe+0x2')
            $seq++
        }
    }
    if ($WindowMs -gt 0) {
        $L.Add('15:00:02.100 qpc=' + ($StartQpc + ([int64]$WindowMs * $MS)) + ' #' + $seq.ToString('D6') +
            ' tid=999 closesocket s=' + $Socket + ' af=2 type=2 ret=0 caller=X.exe+0x3')
        $seq++
    }
    [IO.File]::WriteAllLines($Path, $L, (New-Object System.Text.UTF8Encoding($false)))
    return $L.Count
}

function Invoke-Analyzer([string]$log, [double]$rtt, [string]$csv) {
    # NOTE: never name this array $args -- PowerShell treats $args as an automatic
    # variable, the assignment is ignored and the analyzer silently runs without
    # -Csv (this bit us once: "csv written" appeared in no test output at all).
    $argv = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $analyzer, '-Log', $log, '-RelayRttMs', $rtt)
    if ($csv -ne '') { $argv += @('-Csv', $csv) }
    $out = & powershell.exe @argv 2>&1 | Out-String
    return [pscustomobject]@{ text = $out; code = $LASTEXITCODE }
}

# ---------------------------------------------------------------------------
# Case A: healthy round, 100 ports, 2000 ms window, 22 responses at +12 ms
# ---------------------------------------------------------------------------
Write-Host '--- case A: healthy round (window 2000 ms, 22 responses) ---'
$logA = Join-Path $work 'caseA.log'
$nA = New-BurstLog -Path $logA -Socket '0x868' -PortCount 100 -StartQpc 1000000000000 `
    -WindowMs 2000 -ResponseCount 22 -ResponseAfterMs 12 -BurstSpanMs 100
Write-Host ("built {0} with {1} lines" -f $logA, $nA)
$csvA = Join-Path $work 'caseA.csv'
$rA = Invoke-Analyzer $logA 50 $csvA

Add-Result 'A.exit0' ($rA.code -eq 0) ("exit=" + $rA.code)
Add-Result 'A.rounds1' ($rA.text -match 'rounds\s+:\s+1\b') 'expect exactly 1 round'
Add-Result 'A.sends100' ($rA.text -match 'sendto 255\s*:\s*100') 'expect 100 broadcast sends'
Add-Result 'A.ports100' ($rA.text -match '\b100\s+100\b') 'expect sends=100 ports=100 row'
Add-Result 'A.responses22' ($rA.text -match 'responses total:\s*22') 'expect 22 responses attributed'
Add-Result 'A.window2000' ($rA.text -match '2000([.,]\d+)?') 'expect a ~2000 ms window'
Add-Result 'A.fits' ($rA.text -match 'verdict: the authorised .* relay RTT fits inside every observed window') 'verdict must be PASS-class'
# NOTE: @() is required. In PS 5.1 a single CSV row comes back as one PSCustomObject
# that has no .Count property, so (Import-Csv x).Count is $null and the assertion
# fails even though the file is correct.
Add-Result 'A.csv' ((Test-Path $csvA) -and (@(Import-Csv $csvA).Count -eq 1)) 'csv written with 1 row'
Add-Result 'A.csvColumns' ($(if (Test-Path $csvA) { ((Import-Csv $csvA)[0].PSObject.Properties.Name -contains 'window_ms') } else { $false })) 'csv must carry a window_ms column'
Add-Result 'A.resp2close' ($rA.text -match '1987[.,]\d+') 'response-to-close must be ~1987 ms (2000 - 12 - 0.22)'

# ---------------------------------------------------------------------------
# Case B: window shorter than the relay target -> must be flagged, never PASS
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '--- case B: 30 ms window vs 50 ms relay target ---'
$logB = Join-Path $work 'caseB.log'
$nB = New-BurstLog -Path $logB -Socket '0x15c8' -PortCount 100 -StartQpc 2000000000000 `
    -WindowMs 30 -ResponseCount 0 -ResponseAfterMs 0 -BurstSpanMs 5
Write-Host ("built {0} with {1} lines" -f $logB, $nB)
$rB = Invoke-Analyzer $logB 50 ''

Add-Result 'B.exit0' ($rB.code -eq 0) ("exit=" + $rB.code)
Add-Result 'B.window30' ($rB.text -match '29[.,]\d+|30([.,]0+)?') 'expect ~30 ms window'
Add-Result 'B.noFit' ($rB.text -match 'verdict: NO closed round fits the relay target') 'verdict must be FAIL-class'
Add-Result 'B.notPass' (-not ($rB.text -match 'fits inside every observed window')) 'must NOT claim the relay fits'
Add-Result 'B.counter' ($rB.text -match '0/1 closed rounds have window >= target') 'expect 0 of 1 rounds fitting'

# ---------------------------------------------------------------------------
# Case C: no broadcast at all -> exit 2 and an explicit, non-guessing message
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '--- case C: log without any broadcast ---'
$logC = Join-Path $work 'caseC.log'
$Lc = New-Object System.Collections.Generic.List[string]
$Lc.Add('15:00:00.000 qpc=3000000000000 #000001 tid=999 ===== civtrace 0.4.4 session start =====')
$Lc.Add('15:00:01.000 qpc=3000001000000 #000002 tid=999 select rfd=- wfd=n=1[0xcf8] efd=- timeout=set ret=0 caller=X.exe+0x9')
$Lc.Add('15:00:02.000 qpc=3000002000000 #000003 tid=999 closesocket s=0x868 af=2 type=2 ret=0 caller=X.exe+0x3')
[IO.File]::WriteAllLines($logC, $Lc, (New-Object System.Text.UTF8Encoding($false)))
$rC = Invoke-Analyzer $logC 50 ''

Add-Result 'C.exit2' ($rC.code -eq 2) ("exit=" + $rC.code)
Add-Result 'C.message' ($rC.text -match 'NO DISCOVERY ROUND') 'must state that no round was found'
Add-Result 'C.noVerdict' (-not ($rC.text -match 'verdict:')) 'must not print a verdict when there is no data'

# ---------------------------------------------------------------------------
# Case D: missing log -> exit 3, never a fake result
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '--- case D: missing log file ---'
$rD = Invoke-Analyzer (Join-Path $work 'does-not-exist.log') 50 ''
Add-Result 'D.exit3' ($rD.code -eq 3) ("exit=" + $rD.code)
Add-Result 'D.message' ($rD.text -match 'log not found') 'must say the log is missing'

# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '=== summary ==='
$pass = @($results | Where-Object { $_.ok }).Count
$fail = @($results | Where-Object { -not $_.ok }).Count
Write-Host ("PASS {0}  FAIL {1}  total {2}" -f $pass, $fail, $results.Count)
if ($fail -gt 0) {
    Write-Host ''
    Write-Host 'failed assertions:'
    $results | Where-Object { -not $_.ok } | ForEach-Object { Write-Host ("  - {0}: {1}" -f $_.name, $_.detail) }
}

$report = Join-Path $work 'test-report.txt'
$lines = New-Object System.Collections.Generic.List[string]
$lines.Add('analyze-h6-window.ps1 regression test')
$lines.Add(('run at     : ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')))
$lines.Add(('analyzer   : ' + $analyzer))
$lines.Add(('analyzer sha256: ' + (Get-FileHash $analyzer -Algorithm SHA256).Hash))
$lines.Add(('analyzer bytes : ' + (Get-Item $analyzer).Length))
$lines.Add('')
foreach ($r in $results) { $lines.Add((('[{0}] {1} - {2}' -f $(if ($r.ok) { 'PASS' } else { 'FAIL' }), $r.name, $r.detail))) }
$lines.Add('')
$lines.Add(('PASS {0}  FAIL {1}  total {2}' -f $pass, $fail, $results.Count))
[IO.File]::WriteAllLines($report, $lines, (New-Object System.Text.UTF8Encoding($false)))
Write-Host ''
Write-Host ("report   : {0}" -f $report)

if ($fail -gt 0) { exit 1 }
exit 0
