# F0-verify.ps1 - audit one F0 directory (evidence produced by F0-run.cmd).
#
# F0 (REV-016) requires the simulated-host fixture to be reproducible and
# machine-checkable: every page of every response must be traceable to a file with
# a known digest, the response budget must be respected, and no receive/select error
# may be hidden. This script checks exactly those properties from the evidence
# directory and writes verify-report.txt next to the evidence.
#
# It does NOT and cannot check the one thing only a human sees: whether the Civ6
# lobby actually listed the room. That stays a separate observation (see the
# checklist printed at the end and the RESULT lines in the report).
#
# Usage:
#   powershell -NoProfile -ExecutionPolicy Bypass -File F0-verify.ps1 -EvidenceDir <dir>
#
# Exit codes: 0 = every machine-checkable property passed
#             1 = at least one check failed
#             2 = evidence directory missing / incomplete
#
# ASCII only. No BOM.

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$EvidenceDir
)

$ErrorActionPreference = 'Stop'

$report = New-Object System.Collections.Generic.List[string]
$failures = 0
$warnings = 0

function Line([string]$s) { $report.Add($s) }
function Pass([string]$s) { $report.Add("PASS  $s") }
function Fail([string]$s) { $script:failures++; $report.Add("FAIL  $s") }
function Warn([string]$s) { $script:warnings++; $report.Add("WARN  $s") }

if (-not (Test-Path -LiteralPath $EvidenceDir)) {
    Write-Host "F0-VERIFY: evidence directory not found: $EvidenceDir"
    exit 2
}
$EvidenceDir = (Resolve-Path -LiteralPath $EvidenceDir).Path

Line '=== F0 evidence verification ==='
Line ("time          : {0}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
Line ("evidence dir  : {0}" -f $EvidenceDir)
Line ("verifier      : F0-verify.ps1 sha256={0}" -f (Get-FileHash $MyInvocation.MyCommand.Path -Algorithm SHA256).Hash)
Line ''

# ---------------------------------------------------------------- 1. required files
$required = @('precheck.txt', 'fixture-hashes.txt', 'requests.log',
              'post-response-traffic.log', 'receive-errors.log', 'summary.txt')
$missing = @()
foreach ($f in $required) {
    if (-not (Test-Path -LiteralPath (Join-Path $EvidenceDir $f))) { $missing += $f }
}
for ($i = 1; $i -le 22; $i++) {
    $f = 'sent-reply-{0:d2}.bin' -f $i
    if (-not (Test-Path -LiteralPath (Join-Path $EvidenceDir $f))) { $missing += $f }
}
if ($missing.Count -gt 0) {
    Line '1. required files'
    Fail ("missing {0} file(s): {1}" -f $missing.Count, ($missing -join ', '))
    Line ''
    $earlyPath = Join-Path $EvidenceDir 'verify-report.txt'
    $report | Set-Content -LiteralPath $earlyPath -Encoding UTF8
    Write-Host ($report -join "`r`n")
    Write-Host ''
    Write-Host ("report: {0}" -f $earlyPath)
    exit 2
}
Line '1. required files'
Pass ("all required files present ({0} files + 22 page images)" -f $required.Count)
Line ''

# ---------------------------------------------------------------- 2. page images
# Every page must be exactly 1104 B and carry the advertisement header this project
# has established: magic at [0], page count at [156] = 22, and page index at [160]
# equal to its own 0-based position. A wrong index would make Civ6 treat the set as
# a malformed announcement, so it is checked per page rather than assumed.
Line '2. page images (length / header / page index)'
$pageHashes = @{}
for ($i = 1; $i -le 22; $i++) {
    $name = 'sent-reply-{0:d2}.bin' -f $i
    $p = Join-Path $EvidenceDir $name
    $bytes = [IO.File]::ReadAllBytes($p)
    $pageHashes[$i] = (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash
    if ($bytes.Length -ne 1104) { Fail ("{0}: length {1} != 1104" -f $name, $bytes.Length) }
    $magic = [BitConverter]::ToString($bytes[0..3])
    if ($magic -ne '59-60-69-9B') { Fail ("{0}: magic {1} != 59-60-69-9B" -f $name, $magic) }
    $pageCount = [BitConverter]::ToUInt16($bytes, 156)
    if ($pageCount -ne 22) { Fail ("{0}: page count field {1} != 22" -f $name, $pageCount) }
    $pageIndex = [BitConverter]::ToUInt16($bytes, 160)
    if ($pageIndex -ne ($i - 1)) { Fail ("{0}: page index field {1} != {2}" -f $name, $pageIndex, ($i - 1)) }
    $tail = [BitConverter]::ToString($bytes[1102..1103])
    if ($tail -ne '00-00') { Fail ("{0}: tail marker {1} != 00-00" -f $name, $tail) }
}
if ($failures -eq 0) { Pass 'all 22 pages: 1104 B, magic, count=22, index 0..21, zero tail marker' }
Line ''

# ---------------------------------------------------------------- 3. fixture manifest
# fixture-hashes.txt must document, for every page, the original digest, the sent
# digest and the offsets where the anonymisation rewrite changed bytes. The sent
# digest is recomputed here, so a manifest cannot claim a digest the file lacks.
Line '3. fixture-hashes.txt (original / sent digests, change offsets)'
$fhLines = @(Get-Content -LiteralPath (Join-Path $EvidenceDir 'fixture-hashes.txt'))
if ($fhLines.Count -ne 22) {
    Fail ("fixture-hashes.txt has {0} lines, expected 22" -f $fhLines.Count)
} else {
    $fhOk = $true
    for ($i = 1; $i -le 22; $i++) {
        $ln = $fhLines[$i - 1]
        if ($ln -notmatch '^page (\d{2}): original=([0-9A-F]{64}) sent=([0-9A-F]{64}) changedOffsets=\[(.*?)\]$') {
            Fail ("fixture-hashes.txt line {0} is not in the expected format" -f $i)
            $fhOk = $false
            continue
        }
        $idx = [int]$Matches[1]
        $orig = $Matches[2]
        $sent = $Matches[3]
        $offs = $Matches[4]
        if ($idx -ne $i) { Fail ("fixture-hashes.txt line {0} describes page {1}" -f $i, $idx); $fhOk = $false }
        if ($sent -ne $pageHashes[$i]) {
            Fail ("page {0:d2}: manifest sent digest {1} != file digest {2}" -f $i, $sent.Substring(0, 16), $pageHashes[$i].Substring(0, 16))
            $fhOk = $false
        }
        if ($orig -eq $sent) { Warn ("page {0:d2}: original and sent digest are identical (anonymisation changed nothing)" -f $i) }
        if ($offs -ne '') {
            # A 22-byte rewrite may legitimately keep some bytes identical (e.g. the
            # anonymous name happens to share a byte with the original), so the COUNT
            # is not asserted -- only that every recorded offset lies in the field.
            $parts = $offs -split ','
            foreach ($o in $parts) {
                $v = [int]$o
                if ($v -lt 24 -or $v -gt 45) { Fail ("page {0:d2}: change offset {1} outside 24..45" -f $i, $v); $fhOk = $false }
            }
        } else {
            Warn ("page {0:d2}: no change offsets recorded (room name already matched the anonymous name)" -f $i)
        }
    }
    if ($fhOk) { Pass 'all 22 manifest lines match their page images and keep rewrites inside 24..45' }
}
Line ''

# ---------------------------------------------------------------- 4. summary
Line '4. summary.txt'
$sumPath = Join-Path $EvidenceDir 'summary.txt'
$sum = @(Get-Content -LiteralPath $sumPath)
$summaryResponses = -1
$summaryBudget = -1
$summaryBound = -1
$summaryRequests = -1
$summaryRecvUnexpected = -1
$summarySelUnexpected = -1
foreach ($ln in $sum) {
    if ($ln -match '^responses sent\s+:\s+(\d+) \(budget (\d+)\)') {
        $summaryResponses = [int]$Matches[1]; $summaryBudget = [int]$Matches[2]
    }
    if ($ln -match '^bound ports\s+:\s+\d+\.\.(\d+) \((\d+) bound') { $summaryBound = [int]$Matches[2] }
    if ($ln -match '^requests logged\s+:\s+(\d+)') { $summaryRequests = [int]$Matches[1] }
    if ($ln -match '^receive errors\s+:\s+(\d+) unexpected') { $summaryRecvUnexpected = [int]$Matches[1] }
    if ($ln -match '^select errors\s+:\s+(\d+) unexpected') { $summarySelUnexpected = [int]$Matches[1] }
}
if ($summaryResponses -lt 0) { Fail 'summary.txt has no "responses sent" line' }
else { Pass ("summary reports responses sent = {0} (budget {1})" -f $summaryResponses, $summaryBudget) }
if ($summaryBound -gt 0) { Pass ("summary reports {0} discovery ports bound" -f $summaryBound) }
else { Fail 'summary.txt has no usable "bound ports" line' }
if ($summaryRecvUnexpected -eq 0) { Pass 'summary reports 0 unexpected receive errors' }
elseif ($summaryRecvUnexpected -gt 0) { Fail ("summary reports {0} unexpected receive errors" -f $summaryRecvUnexpected) }
else { Warn 'summary.txt has no "receive errors" line (pre-v2.2 evidence)' }
if ($summarySelUnexpected -eq 0) { Pass 'summary reports 0 unexpected select errors' }
elseif ($summarySelUnexpected -gt 0) { Fail ("summary reports {0} unexpected select errors" -f $summarySelUnexpected) }
else { Warn 'summary.txt has no "select errors" line (pre-v2.3 evidence) - the select branch was not accounted for in this run' }
if ($sum -match 'NOT a multiplayer validation') { Pass 'summary keeps the "not a multiplayer validation" boundary note' }
else { Warn 'summary.txt does not contain the expected boundary note' }
Line ''

# ---------------------------------------------------------------- 5. requests.log
# Each RESPONSE block must contain exactly 22 page lines, in order 01..22, each with
# the digest of the corresponding sent-reply image and with the reply's source port
# equal to the port the client targeted.
Line '5. requests.log (response blocks, page order, per-page digests)'
$reqLines = @(Get-Content -LiteralPath (Join-Path $EvidenceDir 'requests.log'))
$respIdx = @()
for ($i = 0; $i -lt $reqLines.Count; $i++) {
    if ($reqLines[$i] -match '-> RESPONSE #(\d+) \(from dstPort (\d+)\)') { $respIdx += ,@($i, [int]$Matches[1], [int]$Matches[2]) }
}
if ($respIdx.Count -eq 0) {
    Fail 'requests.log contains no RESPONSE block (the client never triggered a reply)'
} else {
    Pass ("requests.log contains {0} RESPONSE block(s)" -f $respIdx.Count)
    if ($summaryResponses -ge 0 -and $respIdx.Count -ne $summaryResponses) {
        Fail ("summary says {0} responses but requests.log has {1} RESPONSE blocks" -f $summaryResponses, $respIdx.Count)
    }
    if ($summaryBudget -gt 0 -and $respIdx.Count -gt $summaryBudget) {
        Fail ("{0} responses exceed the budget of {1}" -f $respIdx.Count, $summaryBudget)
    }
    for ($b = 0; $b -lt $respIdx.Count; $b++) {
        $start = $respIdx[$b][0]
        $stop = if ($b + 1 -lt $respIdx.Count) { $respIdx[$b + 1][0] } else { $reqLines.Count }
        $srcPort = $respIdx[$b][2]
        $pageLines = New-Object System.Collections.Generic.List[string]
        for ($j = $start + 1; $j -lt $stop; $j++) {
            if ($reqLines[$j] -match '^\s+page \d{2}: sent ') { $pageLines.Add($reqLines[$j]) }
        }
        if ($pageLines.Count -ne 22) {
            Fail ("RESPONSE #{0}: {1} page lines, expected 22" -f $respIdx[$b][1], $pageLines.Count)
            continue
        }
        $blockOk = $true
        for ($k = 0; $k -lt 22; $k++) {
            $ln = $pageLines[$k]
            if ($ln -notmatch '^\s+page (\d{2}): sent (\d+) B from port (\d+) to ([0-9.]+):(\d+) at ([\d:.]+)->([\d:.]+) sha256=([0-9A-F]{64})$') {
                Fail ("RESPONSE #{0}: page line {1} is not in the expected format" -f $respIdx[$b][1], ($k + 1))
                $blockOk = $false
                continue
            }
            $pageNo = [int]$Matches[1]
            $sentN = [int]$Matches[2]
            $fromPort = [int]$Matches[3]
            $digest = $Matches[8]
            if ($pageNo -ne ($k + 1)) {
                Fail ("RESPONSE #{0}: page line {1} is page {2} (out of order)" -f $respIdx[$b][1], ($k + 1), $pageNo)
                $blockOk = $false
            }
            if ($sentN -ne 1104) { Fail ("RESPONSE #{0} page {1:d2}: sent {2} B != 1104" -f $respIdx[$b][1], $pageNo, $sentN); $blockOk = $false }
            if ($fromPort -ne $srcPort) {
                Fail ("RESPONSE #{0} page {1:d2}: source port {2} != request target port {3}" -f $respIdx[$b][1], $pageNo, $fromPort, $srcPort)
                $blockOk = $false
            }
            if ($digest -ne $pageHashes[$pageNo]) {
                Fail ("RESPONSE #{0} page {1:d2}: logged digest differs from sent-reply image" -f $respIdx[$b][1], $pageNo)
                $blockOk = $false
            }
        }
        if ($blockOk) { Pass ("RESPONSE #{0}: 22 pages, order 01..22, 1104 B each, source port {1}, digests match" -f $respIdx[$b][1], $srcPort) }
    }
}
Line ''

# ---------------------------------------------------------------- 6. error accounting
# An empty receive-errors.log is the only acceptable proof of "no unexpected error"
# when the summary claims zero; a BOM-only file would be a silent lie either way.
Line '6. receive-errors.log (nothing may be swallowed)'
$errPath = Join-Path $EvidenceDir 'receive-errors.log'
$errBytes = [IO.File]::ReadAllBytes($errPath)
if ($errBytes.Length -eq 0) {
    if ($summaryRecvUnexpected -gt 0 -or $summarySelUnexpected -gt 0) {
        Fail ("receive-errors.log is empty but summary claims unexpected errors (recv={0}, select={1})" -f $summaryRecvUnexpected, $summarySelUnexpected)
    } elseif ($summarySelUnexpected -lt 0) {
        Warn 'receive-errors.log is 0 bytes and receive errors are 0, but this evidence predates the select-error counter (v2.3)'
    } else {
        Pass 'receive-errors.log is 0 bytes and both unexpected counters are 0'
    }
} else {
    if ($errBytes.Length -eq 3 -and $errBytes[0] -eq 0xEF -and $errBytes[1] -eq 0xBB -and $errBytes[2] -eq 0xBF) {
        Fail 'receive-errors.log contains only a UTF-8 BOM (a 0-byte record was written with a BOM)'
    } else {
        $eLines = @(Get-Content -LiteralPath $errPath | Where-Object { $_.Trim() -ne '' })
        Warn ("receive-errors.log has {0} non-empty line(s); inspect them, the run is only valid if every one is explained" -f $eLines.Count)
        foreach ($e in $eLines) { Line ("      | " + $e) }
    }
}
Line ''

# ---------------------------------------------------------------- 7. pre-check record
Line '7. precheck.txt (port ownership decided before binding)'
$preLines = @(Get-Content -LiteralPath (Join-Path $EvidenceDir 'precheck.txt'))
if ($preLines.Count -lt 2) {
    Warn 'precheck.txt is shorter than expected'
} else {
    if ($preLines[0] -match 'UDP endpoints in range 62900\.\.62999: (\d+)') {
        Pass ("pre-check recorded {0} pre-existing endpoint(s) in the discovery range" -f [int]$Matches[1])
    } else {
        Warn 'precheck.txt first line is not the expected range summary'
    }
    foreach ($pl in $preLines) { Line ("      | " + $pl) }
}
Line ''

# ---------------------------------------------------------------- 8. F0 checklist
# The F0 exit condition (REV-016 section 3) mixes machine-checkable facts with one
# human observation. The checklist keeps them apart so the report can never imply
# more than was shown.
Line '8. F0 exit condition (machine part checked here, human part for the operator)'
Line '   [machine] simulator receives every listenable request of one refresh without'
Line '             dying on a single failure ............ see section 5 (no early stop)'
Line '   [machine] complete announcement sent within its limits, per page length/order/'
Line '             index/digest verifiable ................. see sections 2, 3, 5'
Line '   [machine] no silent receive/select error ......... see section 6'
Line '   [human  ] 20 consecutive refreshes each showed the room in the Civ6 lobby'
Line ("             machine-observed responses this run: {0}" -f $(if ($summaryResponses -ge 0) { $summaryResponses } else { 'unknown' }))
Line '   [human  ] repeat listings / timeouts / port ownership recorded per refresh'
Line ''

# ---------------------------------------------------------------- verdict
Line '=== verdict ==='
if ($failures -eq 0 -and $warnings -eq 0) {
    Line 'MACHINE CHECKS: ALL PASS (0 failures, 0 warnings)'
} elseif ($failures -eq 0) {
    Line ("MACHINE CHECKS: PASS with {0} warning(s) - read them before quoting this run" -f $warnings)
} else {
    Line ("MACHINE CHECKS: FAIL ({0} failure(s), {1} warning(s))" -f $failures, $warnings)
}
Line 'Reminder: a passing machine check means the fixture behaved as designed.'
Line 'It does NOT mean two real Civ6 copies played each other. It is not E2-B, not'
Line 'M0-B, not a multiplayer validation, and it does not move any Gate.'

$reportPath = Join-Path $EvidenceDir 'verify-report.txt'
$report | Set-Content -LiteralPath $reportPath -Encoding UTF8

Write-Host $report
Write-Host ''
Write-Host ("report: {0}" -f $reportPath)

if ($failures -gt 0) { exit 1 }
exit 0
