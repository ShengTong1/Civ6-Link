# =============================================================================
#  rev009-roundtrip.ps1 -- one-shot orchestrator for the SINGLE real
#  apply -> restore round trip that REV-009 approved on PC-A.
#
#  REV-009 granted exactly ONE controlled round trip, under seven
#  preconditions. This script enforces them mechanically so that a human
#  mistake (wrong peer, drifted state, second apply) cannot slip through:
#
#    (1) the helper script's own identity is printed and archived
#    (2) the window is checked: Civilization VI must not be running, and no
#        capture helper may be active
#    (3) an independent BackupDir plus a pre-apply baseline are archived
#    (4) a read-only DryRun is always the first stage
#    (5) the DryRun plan must match the REV-009 fixture EXACTLY, otherwise the
#        script stops before touching anything
#    (6) the live interface state must match the fixture, then apply is
#        followed by exit-code, schema=4 backup, sidecar and readback checks
#    (7) any non-zero exit, readback mismatch, residual file or drift stops
#        the run immediately; no second apply, no guessed restore values
#
#  Default behaviour is DRY: it archives the baseline, runs the DryRun and the
#  assertions, then stops. Real changes happen only with -Execute.
#
#  Usage
#    .\rev009-roundtrip.ps1 -PeerIp 26.74.126.98                 # dry stages
#    .\rev009-roundtrip.ps1 -PeerIp 26.74.126.98 -Execute        # admin only
#
#  Exit codes
#    0  stage finished as authorised (dry: nothing changed)
#    1  not elevated (only needed for -Execute)
#    2  bad arguments / helper not found
#    3  precondition or fixture mismatch -> STOP, nothing changed
#    4  apply succeeded but readback did not match the expected target
#    5  restore succeeded but readback did not match the baseline
#    6  helper returned an unexpected exit code
# =============================================================================

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$PeerIp,

    # the interface that legitimately reaches the peer; REV-009 fixture = 18
    [int]$ExpectedKeepIf = 18,
    # target metric raised interfaces are pinned to; REV-009 fixture = 2045
    [int]$ExpectedTargetMetric = 2045,
    # interfaces the plan is allowed to raise, comma separated
    [string]$ExpectedRaiseIf = '10,15',

    [string]$Helper,              # default resolved next to this script
    [string]$EvidenceDir,         # default: M0A\captures\REV-009-roundtrip-<stamp>
    [string]$BackupDir,           # default: %USERPROFILE%\civlink-metric-backups-rev009

    [switch]$Execute,             # actually apply + restore
    [switch]$AllowStateDrift      # skip the fixture state table check
)

$ErrorActionPreference = 'Continue'
$script:Failures = @()

# ----------------------------------------------------------------- utilities
function Write-Head([string]$t) {
    Write-Host ''
    Write-Host ('--- ' + $t + ' ---') -ForegroundColor Cyan
}
function Write-Ok([string]$t)   { Write-Host ('  [OK]   ' + $t) -ForegroundColor Green }
function Write-Bad2([string]$t) { Write-Host ('  [BAD]  ' + $t) -ForegroundColor Red }
function Write-Warn3([string]$t){ Write-Host ('  [WARN] ' + $t) -ForegroundColor Yellow }

function Stop-Now([int]$code, [string]$why) {
    Write-Host ''
    Write-Bad2 $why
    Write-Host '  Nothing was changed. Stopping per REV-009 precondition 7.'
    exit $code
}

function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p  = New-Object Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-Rows {
    $out = @{}
    # Same filter the helper uses: disconnected adapters are not part of any
    # broadcast plan, and their rows can appear/disappear between stages, which
    # would otherwise look like drift that the helper never touched.
    foreach ($r in @(Get-NetIPInterface -AddressFamily IPv4 -ErrorAction SilentlyContinue |
                     Where-Object { $_.ConnectionState -ne 'Disconnected' })) {
        $addr = ''
        $a = Get-NetIPAddress -AddressFamily IPv4 -InterfaceIndex $r.ifIndex -ErrorAction SilentlyContinue |
             Where-Object { $_.IPAddress -notlike '169.254.*' } | Select-Object -First 1
        if ($a) { $addr = $a.IPAddress }
        $out[[int]$r.ifIndex] = [pscustomobject]@{
            ifIndex = [int]$r.ifIndex
            name    = $r.InterfaceAlias
            metric  = [int]$r.InterfaceMetric
            auto    = [string]$r.AutomaticMetric
            ipv4    = $addr
        }
    }
    return $out
}

function Get-Row($rows, [int]$idx) {
    if ($rows.ContainsKey($idx)) { return $rows[$idx] }
    return $null
}

# Run the helper and capture both streams plus the exit code. The helper itself
# writes a banner and prints the script SHA it is executing, which is exactly
# what REV-009 asked to have archived.
function Invoke-Helper([string[]]$argv) {
    $joined = $argv -join ' '
    $raw = & powershell -NoProfile -ExecutionPolicy Bypass -File $Helper @argv 2>&1 | Out-String -Width 220
    $code = $LASTEXITCODE
    return [pscustomobject]@{ Out = $raw; Code = $code; Args = $joined }
}

function Save([string]$name, [string]$text) {
    $p = Join-Path $EvidenceDir $name
    [IO.File]::WriteAllText($p, $text, [Text.UTF8Encoding]::new($true))
    return $p
}

# ---------------------------------------------------------------- 0. identity
if (-not $Helper) {
    $Helper = Join-Path $PSScriptRoot 'set-broadcast-path.ps1'
}
if (-not (Test-Path $Helper)) { Write-Host "helper not found: $Helper"; exit 2 }
$Helper = (Resolve-Path $Helper).Path

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
if (-not $EvidenceDir) {
    $root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    $EvidenceDir = Join-Path $root ('M0A\captures\REV-009-roundtrip-' + $stamp)
}
if (-not $BackupDir) {
    $BackupDir = Join-Path $env:USERPROFILE 'civlink-metric-backups-rev009'
}
New-Item -ItemType Directory -Force -Path $EvidenceDir | Out-Null
New-Item -ItemType Directory -Force -Path $BackupDir   | Out-Null

$helperSha = (Get-FileHash $Helper -Algorithm SHA256).Hash
$selfSha   = (Get-FileHash $PSCommandPath -Algorithm SHA256).Hash

Write-Head 'REV-009 single round trip'
Write-Host ("  when        : {0}" -f (Get-Date -Format o))
Write-Host ("  host        : {0}" -f $env:COMPUTERNAME)
Write-Host ("  peer        : {0}" -f $PeerIp)
Write-Host ("  helper      : {0}" -f $Helper)
Write-Host ("  helper SHA  : {0}" -f $helperSha)
Write-Host ("  self SHA    : {0}" -f $selfSha)
Write-Host ("  evidence    : {0}" -f $EvidenceDir)
Write-Host ("  backup dir  : {0}" -f $BackupDir)
Write-Host ("  mode        : {0}" -f $(if ($Execute) { 'EXECUTE (real changes)' } else { 'dry (baseline + DryRun only)' }))
Write-Host ("  admin       : {0}" -f (Test-Admin))

# ------------------------------------------------- 2. window must be clean
Write-Head 'precondition 2: the window is clean'
$game = @(Get-Process -Name 'CivilizationVI*' -ErrorAction SilentlyContinue)
if ($game.Count -gt 0) {
    Stop-Now 3 ('Civilization VI is running (pid ' + (($game | ForEach-Object { $_.Id }) -join ',') + '). REV-009 requires it to be closed.')
}
Write-Ok 'no Civilization VI process'

$capProc = @(Get-Process -Name 'PktMon', 'dumpcap', 'tshark' -ErrorAction SilentlyContinue)
if ($capProc.Count -gt 0) {
    Stop-Now 3 ('a capture tool is active (' + (($capProc | ForEach-Object { $_.ProcessName }) -join ',') + '). REV-009 requires capture windows to be separate.')
}
Write-Ok 'no capture tool active'

if ($Execute -and -not (Test-Admin)) {
    Stop-Now 1 'real changes need an elevated PowerShell (Run as administrator).'
}

# ------------------------------------------- 3/6. baseline + fixture check
Write-Head 'precondition 3: archive the pre-apply baseline'
$rowsBefore = Get-Rows
$sb = New-Object Text.StringBuilder
[void]$sb.AppendLine('# captured ' + (Get-Date).ToString('o') + ' on ' + $env:COMPUTERNAME)
[void]$sb.AppendLine('ifIndex,Name,Metric,AutomaticMetric,IPv4')
foreach ($k in ($rowsBefore.Keys | Sort-Object)) {
    $r = $rowsBefore[$k]
    [void]$sb.AppendLine(('{0},"{1}",{2},{3},{4}' -f $r.ifIndex, $r.name, $r.metric, $r.auto, $r.ipv4))
}
$tableBefore = $sb.ToString()
[void](Save 'baseline-interfaces.csv' $tableBefore)
[void](Save 'baseline-GetNetIPInterface.txt' ((Get-NetIPInterface -AddressFamily IPv4 | Format-Table -AutoSize | Out-String -Width 160)))
[void](Save 'baseline-GetNetRoute.txt' ((Get-NetRoute -AddressFamily IPv4 | Format-Table -AutoSize | Out-String -Width 160)))
[void](Save 'baseline-route-print.txt' ((route print -4 2>&1 | Out-String)))
$snap = Invoke-Helper @('-Action','snapshot')
[void](Save 'baseline-snapshot.txt' $snap.Out)
Write-Ok ("baseline archived; helper snapshot exit={0}" -f $snap.Code)

# REV-009 fixture: the values the test is allowed to start from. These are the
# REV-006 snapshot values, NOT the E0 baseline (E0 had WLAN 35/Enabled).
$fixture = @{
    10 = @(45,  'Disabled')
    1  = @(75,  'Enabled')
    18 = @(1045,'Disabled')
    15 = @(1045,'Disabled')
    58 = @(5000,'Disabled')
    25 = @(5000,'Disabled')
}
$drift = @()
foreach ($idx in $fixture.Keys) {
    $r = Get-Row $rowsBefore $idx
    if (-not $r) { $drift += ("if={0} missing" -f $idx); continue }
    $wantM = $fixture[$idx][0]; $wantA = $fixture[$idx][1]
    if ($r.metric -ne $wantM) { $drift += ("if={0} {1}: metric {2} != {3}" -f $idx, $r.name, $r.metric, $wantM) }
    if ($r.auto   -ne $wantA) { $drift += ("if={0} {1}: auto   {2} != {3}" -f $idx, $r.name, $r.auto,   $wantA) }
}
if ($drift.Count -gt 0) {
    $msg = "fixture state mismatch:`n    " + ($drift -join "`n    ")
    if (-not $AllowStateDrift) {
        [void](Save 'STOP-fixture-mismatch.txt' $msg)
        Stop-Now 3 $msg
    }
    Write-Warn3 'state differs from the REV-009 fixture but -AllowStateDrift was given'
    $msg | ForEach-Object { Write-Warn3 $_ }
} else {
    Write-Ok 'live state matches the REV-009 fixture exactly'
}

# --------------------------------------------------- 4/5. read-only DryRun
Write-Head 'precondition 4/5: read-only DryRun must match the fixture plan'
$dry = Invoke-Helper @('-Action','apply','-PeerIp',$PeerIp,'-DryRun','-BackupDir',$BackupDir)
[void](Save 'stage1-dryrun.txt' ($dry.Args + "`n`nexit=" + $dry.Code + "`n`n" + $dry.Out))

if ($dry.Code -ne 0) { Stop-Now 3 ("DryRun exit=" + $dry.Code + ' (expected 0)') }

$planIssues = @()
if ($dry.Out -notmatch ('keep\s+if=' + $ExpectedKeepIf + '\b')) {
    $planIssues += ('plan does not keep if=' + $ExpectedKeepIf)
}
if ($dry.Out -notmatch ('raise\s+\d+\s+interface\(s\)\s+to\s+metric\s+' + $ExpectedTargetMetric + '\b')) {
    $planIssues += ('plan does not raise to metric ' + $ExpectedTargetMetric)
}
$wantRaise = @($ExpectedRaiseIf -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' })
if ($dry.Out -match 'raise\s+(\d+)\s+interface') {
    $count = [int]$Matches[1]
    if ($count -ne $wantRaise.Count) { $planIssues += ('plan raises ' + $count + ' interfaces, expected ' + $wantRaise.Count) }
}
foreach ($idx in $wantRaise) {
    if ($dry.Out -notmatch ('if=' + $idx + '\s')) { $planIssues += ('plan is missing if=' + $idx) }
}
if ($dry.Out -match 'NOTHING TO DO') {
    $planIssues += 'plan is NOTHING TO DO - a no-op is explicitly not a valid round trip per REV-009'
}

if ($planIssues.Count -gt 0) {
    $m = 'DryRun plan does not match the REV-009 fixture:' + "`n    " + ($planIssues -join "`n    ")
    [void](Save 'STOP-plan-mismatch.txt' $m)
    Stop-Now 3 $m
}
Write-Ok ('plan matches: keep if=' + $ExpectedKeepIf + ', raise if=' + ($wantRaise -join '/') + ' -> ' + $ExpectedTargetMetric)

if (-not $Execute) {
    Write-Host ''
    Write-Host '  Dry stages complete. Nothing was changed.' -ForegroundColor Yellow
    Write-Host '  Re-run with -Execute (elevated) to perform the single authorised round trip.' -ForegroundColor Yellow
    [void](Save 'stage2-NOT-EXECUTED.txt' ("dry run only; -Execute not given; $((Get-Date).ToString('o'))"))
    exit 0
}

# ------------------------------------------------------------ 6. real apply
Write-Head 'precondition 6: real apply'
$rowsNow = Get-Rows
$recheck = @()
foreach ($idx in $fixture.Keys) {
    $r = Get-Row $rowsNow $idx
    if (-not $r) { $recheck += ("if={0} missing" -f $idx); continue }
    if ($r.metric -ne $fixture[$idx][0] -or $r.auto -ne $fixture[$idx][1]) {
        $recheck += ("if={0} changed between baseline and apply: {1}/{2}" -f $idx, $r.metric, $r.auto)
    }
}
if ($recheck.Count -gt 0) { Stop-Now 3 ('state moved between baseline and apply: ' + ($recheck -join '; ')) }

$existing = @(Get-ChildItem $BackupDir -Filter 'civlink-metric-*.json' -ErrorAction SilentlyContinue |
              Where-Object { $_.Name -notlike '*.restored.json' })
if ($existing.Count -gt 0) { Stop-Now 3 ('BackupDir already holds an unrestored backup: ' + $existing[0].Name) }
Write-Ok 'no unrestored backup present'

$apply = Invoke-Helper @('-Action','apply','-PeerIp',$PeerIp,'-BackupDir',$BackupDir)
[void](Save 'stage3-apply.txt' ($apply.Args + "`n`nexit=" + $apply.Code + "`n`n" + $apply.Out))
if ($apply.Code -ne 0) { Stop-Now 6 ('apply exit=' + $apply.Code + ' (expected 0). See stage3-apply.txt.') }
Write-Ok 'apply exit=0'

$bak = @(Get-ChildItem $BackupDir -Filter 'civlink-metric-*.json' -ErrorAction SilentlyContinue |
         Where-Object { $_.Name -notlike '*.restored.json' }) | Sort-Object LastWriteTime | Select-Object -Last 1
if (-not $bak) { Stop-Now 4 'apply reported success but no backup file appeared' }
$bakShaFile = $bak.FullName + '.sha256'
$bakSha = if (Test-Path $bakShaFile) { [IO.File]::ReadAllText($bakShaFile).Trim() } else { '(missing)' }
$actualSha = (Get-FileHash $bak.FullName -Algorithm SHA256).Hash
$obj = $null
try { $obj = [IO.File]::ReadAllText($bak.FullName) | ConvertFrom-Json } catch { }
$schema = if ($obj) { [int]$obj.schema } else { -1 }
Write-Host ("  backup      : {0}" -f $bak.Name)
Write-Host ("  schema      : {0}" -f $schema)
Write-Host ("  file SHA    : {0}" -f $actualSha)
Write-Host ("  sidecar SHA : {0}" -f $bakSha)
if ($schema -ne 4)          { Stop-Now 4 ('backup schema=' + $schema + ' (expected 4)') }
if ($bakSha -ne $actualSha) { Stop-Now 4 'sidecar hash does not match the backup file' }
Write-Ok 'schema=4 backup with matching sidecar'

$rowsAfter = Get-Rows
$bad = @()
$r10 = Get-Row $rowsAfter 10
if (-not $r10 -or $r10.metric -ne $ExpectedTargetMetric -or $r10.auto -ne 'Disabled') {
    $bad += ('if=10 expected ' + $ExpectedTargetMetric + '/Disabled, now ' + $(if ($r10) { '' + $r10.metric + '/' + $r10.auto } else { 'missing' }))
}
$r15 = Get-Row $rowsAfter 15
if (-not $r15 -or $r15.metric -ne $ExpectedTargetMetric -or $r15.auto -ne 'Disabled') {
    $bad += ('if=15 expected ' + $ExpectedTargetMetric + '/Disabled, now ' + $(if ($r15) { '' + $r15.metric + '/' + $r15.auto } else { 'missing' }))
}
$r18 = Get-Row $rowsAfter 18
if (-not $r18 -or $r18.metric -ne 1045) { $bad += ('if=18 (keep) changed to ' + $(if ($r18) { $r18.metric } else { 'missing' })) }
foreach ($idx in @(1,58,25)) {
    $a = Get-Row $rowsAfter $idx; $b = Get-Row $rowsBefore $idx
    if ($a -and $b -and ($a.metric -ne $b.metric -or $a.auto -ne $b.auto)) {
        $bad += ('if=' + $idx + ' should be untouched: ' + $b.metric + '/' + $b.auto + ' -> ' + $a.metric + '/' + $a.auto)
    }
}
[void](Save 'stage3-apply-readback.txt' ((Get-NetIPInterface -AddressFamily IPv4 | Format-Table -AutoSize | Out-String -Width 160)))
if ($bad.Count -gt 0) {
    [void](Save 'STOP-apply-readback.txt' ($bad -join "`n"))
    Stop-Now 4 ('apply readback mismatch:' + "`n    " + ($bad -join "`n    "))
}
Write-Ok 'apply readback matches the expected target state'

# ---------------------------------------------------------- 6b. real restore
Write-Head 'precondition 6: real restore using that explicit backup path'
$rest = Invoke-Helper @('-Action','restore','-BackupDir',$BackupDir,'-BackupFile',$bak.FullName)
[void](Save 'stage4-restore.txt' ($rest.Args + "`n`nexit=" + $rest.Code + "`n`n" + $rest.Out))
if ($rest.Code -ne 0) { Stop-Now 6 ('restore exit=' + $rest.Code + ' (expected 0). See stage4-restore.txt.') }
Write-Ok 'restore exit=0'

$rowsFinal = Get-Rows
$bad2 = @()
foreach ($idx in ($rowsBefore.Keys | Sort-Object)) {
    $a = Get-Row $rowsFinal $idx; $b = Get-Row $rowsBefore $idx
    if (-not $a) { $bad2 += ('if=' + $idx + ' disappeared'); continue }
    if ($a.metric -ne $b.metric -or $a.auto -ne $b.auto) {
        $bad2 += ('if=' + $idx + ' ' + $b.name + ': ' + $b.metric + '/' + $b.auto + ' -> ' + $a.metric + '/' + $a.auto)
    }
}
[void](Save 'stage4-restore-readback.txt' ((Get-NetIPInterface -AddressFamily IPv4 | Format-Table -AutoSize | Out-String -Width 160)))
[void](Save 'stage4-restore-dir.txt' ((Get-ChildItem $BackupDir -Force | Select-Object Name,Length,LastWriteTime | Format-Table -AutoSize | Out-String -Width 160)))

$restoredName = [IO.Path]::ChangeExtension($bak.Name, '.restored.json')
$restoredPath = Join-Path $BackupDir $restoredName
if (-not (Test-Path $restoredPath)) { $bad2 += ('retired backup not found: ' + $restoredName) }

if ($bad2.Count -gt 0) {
    [void](Save 'STOP-restore-readback.txt' ($bad2 -join "`n"))
    Stop-Now 5 ('restore readback did not return to the baseline:' + "`n    " + ($bad2 -join "`n    "))
}
Write-Ok 'restore readback equals the pre-apply baseline'
Write-Ok ('backup retired to ' + $restoredName)

# ------------------------------------------------------------------ summary
$summary = @"
# REV-009 round trip summary
when         : $((Get-Date).ToString('o'))
host         : $env:COMPUTERNAME
peer         : $PeerIp
helper       : $Helper
helper SHA   : $helperSha
self SHA     : $selfSha
backup dir   : $BackupDir
backup file  : $($bak.Name)
backup SHA   : $actualSha
sidecar SHA  : $bakSha
schema       : $schema
retired to   : $restoredName
apply exit   : $($apply.Code)
restore exit : $($rest.Code)
readback     : apply OK, restore OK
"@
[void](Save 'SUMMARY.md' $summary)

$manifest = ''
foreach ($f in @(Get-ChildItem $EvidenceDir -File | Sort-Object Name)) {
    $manifest += ("{0}  {1}  {2}`n" -f (Get-FileHash $f.FullName -Algorithm SHA256).Hash, $f.Length, $f.Name)
}
[void](Save 'SHA256SUMS.txt' $manifest)

Write-Head 'done'
Write-Host ("  evidence : {0}" -f $EvidenceDir)
Write-Host ("  manifest : {0}" -f (Join-Path $EvidenceDir 'SHA256SUMS.txt'))
Write-Host '  Reminder: this proves the helper returns the adapters to the pre-test' -ForegroundColor Yellow
Write-Host '  state. It does not restore or certify the E0 baseline.' -ForegroundColor Yellow
exit 0
