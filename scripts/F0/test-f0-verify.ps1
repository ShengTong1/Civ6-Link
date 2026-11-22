# test-f0-verify.ps1 - prove that F0-verify.ps1 actually catches the failures it claims.
#
# A verifier that only ever passes on good input is worthless: it would happily bless a
# run whose page digests were faked or whose error log was silently emptied. This test
# builds mutated copies of a real F0 evidence directory and asserts, for each mutation,
# the exact verdict F0-verify.ps1 must produce.
#
# It never touches the source evidence: everything is copied into a scratch tree first.
#
# Usage:
#   powershell -NoProfile -ExecutionPolicy Bypass -File test-f0-verify.ps1 `
#       [-SeedDir <a known-good F0 evidence dir>] [-OutDir <scratch dir>]
#
# Exit codes: 0 = every case behaved as asserted, 1 = at least one case did not.
# ASCII only. No BOM.

[CmdletBinding()]
param(
    [string]$SeedDir = 'C:\Users\dd\Desktop\injciv6-v0.3.3\M0A\captures\E2B-synthetic-v22-real-20261113-122548',
    [string]$OutDir = ''
)

$ErrorActionPreference = 'Stop'
$verifier = Join-Path $PSScriptRoot 'F0-verify.ps1'
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
if ($OutDir -eq '') { $OutDir = Join-Path $PSScriptRoot ('..\..\..\M0A\captures\f0-selftest-' + $stamp) }
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$OutDir = (Resolve-Path -LiteralPath $OutDir).Path

$report = New-Object System.Collections.Generic.List[string]
$failures = 0
$cases = 0

function Line([string]$s) { $report.Add($s) }
function Check([string]$name, [bool]$ok, [string]$detail) {
    $script:cases++
    if (-not $ok) { $script:failures++ }
    $report.Add(('{0}  {1}{2}' -f $(if ($ok) { 'PASS' } else { 'FAIL' }), $name, $(if ($detail) { " -- $detail" } else { '' })))
}

function New-Case([string]$name) {
    $dir = Join-Path $OutDir $name
    if (Test-Path -LiteralPath $dir) { Remove-Item -LiteralPath $dir -Recurse -Force }
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    Copy-Item -Path (Join-Path $SeedDir '*') -Destination $dir -Recurse -Force
    if (Test-Path -LiteralPath (Join-Path $dir 'verify-report.txt')) { Remove-Item -LiteralPath (Join-Path $dir 'verify-report.txt') -Force }
    return $dir
}

function Invoke-Verifier([string]$dir) {
    $out = & powershell -NoProfile -ExecutionPolicy Bypass -File $verifier -EvidenceDir $dir 2>&1 | Out-String
    return [pscustomobject]@{ Code = $LASTEXITCODE; Text = $out }
}

if (-not (Test-Path -LiteralPath (Join-Path $SeedDir 'summary.txt'))) {
    Write-Host "TEST-F0-VERIFY: seed directory is not a usable F0 evidence dir: $SeedDir"
    exit 2
}

Line '=== test-f0-verify ==='
Line ("time      : {0}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
Line ("seed      : {0}" -f $SeedDir)
Line ("out dir   : {0}" -f $OutDir)
Line ("verifier  : sha256={0}" -f (Get-FileHash -LiteralPath $verifier -Algorithm SHA256).Hash)
Line ''

# ---------------------------------------------------------------- A. healthy seed
$dir = New-Case 'A-healthy'
$r = Invoke-Verifier $dir
Check 'A1 healthy evidence exits 0' ($r.Code -eq 0) ("exit={0}" -f $r.Code)
Check 'A2 healthy evidence reports ALL PASS or PASS with warnings' ($r.Text -match 'MACHINE CHECKS: (ALL PASS|PASS with)') ''
Check 'A3 report file was written' (Test-Path -LiteralPath (Join-Path $dir 'verify-report.txt')) ''

# ---------------------------------------------------------------- B. no response at all
# A run where the client never refreshed must not be reported as a passing fixture.
$dir = New-Case 'B-no-response'
[IO.File]::WriteAllText((Join-Path $dir 'requests.log'), '', (New-Object System.Text.UTF8Encoding($false)))
$sum = [IO.File]::ReadAllText((Join-Path $dir 'summary.txt'))
$sum = $sum -replace '(?m)^responses sent\s+:\s+\d+ \(budget \d+\)', 'responses sent  : 0 (budget 20)'
[IO.File]::WriteAllText((Join-Path $dir 'summary.txt'), $sum, (New-Object System.Text.UTF8Encoding($false)))
$r = Invoke-Verifier $dir
Check 'B1 zero responses exits 1' ($r.Code -eq 1) ("exit={0}" -f $r.Code)
Check 'B2 zero responses is reported as a failure' ($r.Text -match 'FAIL {2}requests\.log contains no RESPONSE block') ''

# ---------------------------------------------------------------- C. missing file
$dir = New-Case 'C-missing-file'
Remove-Item -LiteralPath (Join-Path $dir 'precheck.txt') -Force
$r = Invoke-Verifier $dir
Check 'C1 missing required file exits 2' ($r.Code -eq 2) ("exit={0}" -f $r.Code)
Check 'C2 missing file is named' ($r.Text -match 'precheck\.txt') ''

# ---------------------------------------------------------------- D. tampered page image
# The manifest digest is recomputed from the file, so flipping a content byte must be
# caught even though fixture-hashes.txt still claims the original digest.
$dir = New-Case 'D-tampered-page'
$pagePath = Join-Path $dir 'sent-reply-05.bin'
$bytes = [IO.File]::ReadAllBytes($pagePath)
$bytes[500] = $bytes[500] -bxor 0xFF
[IO.File]::WriteAllBytes($pagePath, $bytes)
$r = Invoke-Verifier $dir
Check 'D1 tampered page exits 1' ($r.Code -eq 1) ("exit={0}" -f $r.Code)
Check 'D2 tampered page is caught against the manifest' ($r.Text -match 'manifest sent digest .* != file digest') ''

# ---------------------------------------------------------------- E. broken page header
# A wrong page-index field would make Civ6 treat the announcement as malformed.
$dir = New-Case 'E-bad-page-index'
$pagePath = Join-Path $dir 'sent-reply-07.bin'
$bytes = [IO.File]::ReadAllBytes($pagePath)
$bytes[160] = 0x63
[IO.File]::WriteAllBytes($pagePath, $bytes)
$r = Invoke-Verifier $dir
Check 'E1 wrong page index exits 1' ($r.Code -eq 1) ("exit={0}" -f $r.Code)
Check 'E2 wrong page index is named' ($r.Text -match 'page index field 99 != 6') ''

# ---------------------------------------------------------------- F. BOM-only error log
# A 0-byte record written with a BOM is a silent lie about "no errors".
$dir = New-Case 'F-bom-error-log'
[IO.File]::WriteAllBytes((Join-Path $dir 'receive-errors.log'), [byte[]](0xEF, 0xBB, 0xBF))
$r = Invoke-Verifier $dir
Check 'F1 BOM-only error log exits 1' ($r.Code -eq 1) ("exit={0}" -f $r.Code)
Check 'F2 BOM-only error log is called out' ($r.Text -match 'only a UTF-8 BOM') ''

# ---------------------------------------------------------------- G. response over budget
# The extra block alone only breaks the "summary vs requests.log" agreement; to reach
# the dedicated budget check the recorded budget must also be lowered below it.
$dir = New-Case 'G-over-budget'
$req = [IO.File]::ReadAllText((Join-Path $dir 'requests.log'))
$req = $req + "`r`n[23:59:59.999] dstPort=62900 len=4 src=192.168.31.59:5000 iface=10 payload=8D-E8-FC-70 magic=True localSrc=True -> RESPONSE #3 (from dstPort 62900)`r`n"
[IO.File]::WriteAllText((Join-Path $dir 'requests.log'), $req, (New-Object System.Text.UTF8Encoding($false)))
$sum = [IO.File]::ReadAllText((Join-Path $dir 'summary.txt'))
$sum = $sum -replace '(?m)^responses sent\s+:\s+\d+ \(budget \d+\)', 'responses sent  : 3 (budget 2)'
[IO.File]::WriteAllText((Join-Path $dir 'summary.txt'), $sum, (New-Object System.Text.UTF8Encoding($false)))
$r = Invoke-Verifier $dir
Check 'G1 response beyond budget exits 1' ($r.Code -eq 1) ("exit={0}" -f $r.Code)
Check 'G2 budget violation is named' ($r.Text -match 'exceed the budget') ''

# ---------------------------------------------------------------- H. missing page image
$dir = New-Case 'H-missing-page'
Remove-Item -LiteralPath (Join-Path $dir 'sent-reply-11.bin') -Force
$r = Invoke-Verifier $dir
Check 'H1 missing page image exits 2' ($r.Code -eq 2) ("exit={0}" -f $r.Code)
Check 'H2 missing page image is named' ($r.Text -match 'sent-reply-11\.bin') ''

# ---------------------------------------------------------------- verdict
Line ''
Line ("cases: {0}   failures: {1}" -f $cases, $failures)
Line ("verdict: {0}" -f $(if ($failures -eq 0) { 'ALL ASSERTIONS PASS' } else { 'ASSERTION FAILURES' }))

$reportPath = Join-Path $OutDir 'test-report.txt'
$report | Set-Content -LiteralPath $reportPath -Encoding UTF8
Write-Host ($report -join "`r`n")
Write-Host ''
Write-Host ("report: {0}" -f $reportPath)

if ($failures -gt 0) { exit 1 }
exit 0
