# test-responder-errorpath.ps1
# Regression test for the v2.2 receive-error and v2.3 select-error accounting amendments
# (E2B-SYNTHETIC-CLIENT-REVIEW.md section 3; REV-014-REVIEW.md section 4).
#
# Covers three paths:
#   A. RECV FAULT-INJECTED : -InjectReceiveFault N forces N unexpected receive errors.
#                            Requires receive-errors.log to contain N records and summary.txt
#                            to report "N unexpected", and the script must survive to finalize.
#   B. RECV CLEAN          : -InjectReceiveFault 0 on a quiet port range.
#                            Requires receive-errors.log to exist but be empty (0 bytes) and
#                            summary.txt to report "0 unexpected" - i.e. absence is provable,
#                            not merely unobserved.
#   C. SELECT FAULT-INJECTED: -InjectSelectFault N forces N unexpected Select errors.
#                            Requires N kind=SelectException records, summary "select errors:
#                            N unexpected", the script to survive to finalize, AND (crucially)
#                            the loop not to busy-spin: a 10 s listen window must not produce
#                            thousands of log lines for 2 injected faults.
#
# The script sends synthetic magic datagrams in each run so that the receive path is
# actually entered (the A/B faults are injected on the receive call itself).
#
# Usage:
#   powershell -NoProfile -ExecutionPolicy Bypass -File test-responder-errorpath.ps1

[CmdletBinding()]
param(
    [string]$OutRoot = '',
    [int]$FirstPort = 62950,
    [int]$LastPort = 62959,
    # Defaults to the shipped responder. Overridden only by mutation testing, to prove the
    # assertions below actually fail against a responder with the defects re-introduced.
    [string]$ResponderPath = ''
)

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$responder = if ($ResponderPath -ne '') { (Resolve-Path $ResponderPath).Path } else { Join-Path $here 'synthetic-host-responder.ps1' }
$fixture = Join-Path $here '..\..\M0A\captures\E2A-H4-reply-20261113\reply-set'
if ($OutRoot -eq '') { $OutRoot = Join-Path $here ('..\..\M0A\captures\responder-errorpath-' + (Get-Date -Format 'yyyyMMdd-HHmmss')) }
New-Item -ItemType Directory -Force -Path $OutRoot | Out-Null

$results = New-Object System.Collections.Generic.List[string]
$failures = 0
function Check([string]$name, [bool]$ok, [string]$detail) {
    if ($ok) { $results.Add("PASS  $name  $detail") }
    else { $results.Add("FAIL  $name  $detail"); $script:failures++ }
}

function Send-Magic([int]$port) {
    $u = New-Object System.Net.Sockets.UdpClient
    try {
        $b = [byte[]](0x8d, 0xe8, 0xfc, 0x70)
        [void]$u.Send($b, 4, '127.0.0.1', $port)
    } finally { $u.Dispose() }
}

function Invoke-Run([string]$tag, [int]$inject, [int]$listenSec, [int]$injectSelect = 0) {
    $out = Join-Path $OutRoot $tag
    New-Item -ItemType Directory -Force -Path $out | Out-Null
    $argv = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $responder,
              '-FixtureDir', $fixture, '-OutDir', $out,
              '-FirstPort', "$FirstPort", '-LastPort', "$LastPort",
              '-ListenSeconds', "$listenSec", '-PostResponseSec', '1',
              '-MaxResponses', '3', '-InjectReceiveFault', "$inject",
              '-InjectSelectFault', "$injectSelect")
    $p = Start-Process powershell.exe -ArgumentList $argv -WindowStyle Hidden -PassThru
    # wait until the first port of the range is bound by this pid
    $deadline = (Get-Date).AddSeconds(60)
    do {
        Start-Sleep -Milliseconds 300
        $bound = @(Get-NetUDPEndpoint -LocalPort $FirstPort -EA SilentlyContinue | Where-Object { $_.OwningProcess -eq $p.Id })
    } while ($bound.Count -lt 1 -and (Get-Date) -lt $deadline)
    if ($bound.Count -lt 1) { $p | Stop-Process -Force -EA SilentlyContinue; return $null }
    Start-Sleep -Milliseconds 500
    Send-Magic $FirstPort
    Start-Sleep -Milliseconds 300
    Send-Magic ($FirstPort + 1)
    # let the window expire so finalize writes summary + receive-errors
    $waitDeadline = (Get-Date).AddSeconds($listenSec + 60)
    while ((Get-Process -Id $p.Id -EA SilentlyContinue) -and (Get-Date) -lt $waitDeadline) { Start-Sleep -Milliseconds 500 }
    if (Get-Process -Id $p.Id -EA SilentlyContinue) { $p | Stop-Process -Force -EA SilentlyContinue }
    return $out
}

# ---------------------------------------------------------------- A. fault-injected
$aOut = Invoke-Run -tag 'A-injected' -inject 2 -listenSec 10
if (-not $aOut -or -not (Test-Path (Join-Path $aOut 'summary.txt'))) {
    Check 'A.summary-written' $false 'responder did not finalize (no summary.txt)'
} else {
    $aSum = Get-Content (Join-Path $aOut 'summary.txt') -Raw
    $aErrPath = Join-Path $aOut 'receive-errors.log'
    $aErrExists = Test-Path $aErrPath
    $aErrLines = if ($aErrExists) { @(Get-Content $aErrPath | Where-Object { $_.Trim() -ne '' }).Count } else { -1 }
    Check 'A.errors-file-exists' $aErrExists "receive-errors.log present=$aErrExists"
    Check 'A.errors-recorded-2' ($aErrLines -eq 2) "lines=$aErrLines (expected 2)"
    Check 'A.injected-recorded' ($aSum -match '2 unexpected') ("summary says: " + (($aSum -split "`n" | Where-Object { $_ -match 'receive errors' }) -join ' '))
    Check 'A.survived-to-finalize' $true 'script reached finalize (summary + logs written)'
    if ($aErrExists) {
        $firstLine = (Get-Content $aErrPath | Select-Object -First 1)
        Check 'A.error-line-has-detail' ($firstLine -match 'port=' -and $firstLine -match 'kind=' -and $firstLine -match 'msg=') $firstLine
    }
}

# ---------------------------------------------------------------- B. clean run
$bOut = Invoke-Run -tag 'B-clean' -inject 0 -listenSec 10
if (-not $bOut -or -not (Test-Path (Join-Path $bOut 'summary.txt'))) {
    Check 'B.summary-written' $false 'responder did not finalize (no summary.txt)'
} else {
    $bSum = Get-Content (Join-Path $bOut 'summary.txt') -Raw
    $bErrPath = Join-Path $bOut 'receive-errors.log'
    $bErrExists = Test-Path $bErrPath
    $bErrSize = if ($bErrExists) { (Get-Item $bErrPath).Length } else { -1 }
    Check 'B.errors-file-exists' $bErrExists "receive-errors.log present=$bErrExists"
    Check 'B.errors-file-empty' ($bErrSize -eq 0) "size=$bErrSize bytes (expected 0)"
    Check 'B.zero-unexpected' ($bSum -match '0 unexpected') ("summary says: " + (($bSum -split "`n" | Where-Object { $_ -match 'receive errors' }) -join ' '))
    Check 'B.zero-select-unexpected' ($bSum -match 'select errors\s*:\s*0 unexpected') ("summary says: " + (($bSum -split "`n" | Where-Object { $_ -match 'select errors' }) -join ' '))
    $bReq = Join-Path $bOut 'requests.log'
    $bMatched = if (Test-Path $bReq) { @(Select-String -Path $bReq -Pattern 'magic=True localSrc=True').Count } else { 0 }
    Check 'B.receive-path-entered' ($bMatched -ge 1) "matched request lines=$bMatched"
}

# ---------------------------------------------------------------- C. select fault-injected
$cOut = Invoke-Run -tag 'C-select-injected' -inject 0 -listenSec 10 -injectSelect 2
if (-not $cOut -or -not (Test-Path (Join-Path $cOut 'summary.txt'))) {
    Check 'C.summary-written' $false 'responder did not finalize (no summary.txt)'
} else {
    $cSum = Get-Content (Join-Path $cOut 'summary.txt') -Raw
    $cErrPath = Join-Path $cOut 'receive-errors.log'
    $cErrExists = Test-Path $cErrPath
    $cSelLines = if ($cErrExists) { @(Select-String -Path $cErrPath -Pattern 'kind=SelectException').Count } else { -1 }
    Check 'C.errors-file-exists' $cErrExists "receive-errors.log present=$cErrExists"
    Check 'C.select-recorded-2' ($cSelLines -eq 2) "kind=SelectException lines=$cSelLines (expected 2)"
    Check 'C.select-summary' ($cSum -match 'select errors\s*:\s*2 unexpected') ("summary says: " + (($cSum -split "`n" | Where-Object { $_ -match 'select errors' }) -join ' '))
    Check 'C.recv-untouched' ($cSum -match 'receive errors\s*:\s*0 unexpected') ("summary says: " + (($cSum -split "`n" | Where-Object { $_ -match 'receive errors' }) -join ' '))
    Check 'C.survived-to-finalize' $true 'script reached finalize despite Select faults'
    # a persistent Select failure must not become a busy spin: 2 injected faults in a 10 s
    # window has to yield exactly 2 records, not thousands.
    $cTotalErrLines = if ($cErrExists) { @(Get-Content $cErrPath | Where-Object { $_.Trim() -ne '' }).Count } else { -1 }
    Check 'C.no-busy-spin' ($cTotalErrLines -eq 2) "total error lines=$cTotalErrLines (expected exactly 2)"
    # the listen loop must still have run to its window instead of crashing out early
    $cWindowOk = ($cSum -match 'window\s+\d+\s*s')
    Check 'C.window-recorded' $cWindowOk 'summary records a listen window'
}

# ---------------------------------------------------------------- report
$report = New-Object System.Collections.Generic.List[string]
$report.Add('=== test-responder-errorpath results ===')
$report.Add(('run root : {0}' -f $OutRoot))
$report.Add(('ports    : {0}..{1}' -f $FirstPort, $LastPort))
$report.Add('')
foreach ($r in $results) { $report.Add($r) }
$report.Add('')
$report.Add(('RESULT: {0} failure(s)' -f $failures))
[IO.File]::WriteAllLines((Join-Path $OutRoot 'results.txt'), $report, [Text.Encoding]::UTF8)
foreach ($r in $results) { Write-Host $r }
Write-Host ''
Write-Host ("RESULT: {0} failure(s)" -f $failures)
Write-Host ("evidence: {0}" -f $OutRoot)
exit $(if ($failures -eq 0) { 0 } else { 1 })
