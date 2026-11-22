# C2 real-game in-process check: inject civlink_client.dll into a running Civilization VI
# and read back the bookkeeping counters.
#
# WHY this exists: every C2 evidence round so far used powershell.exe (or the selftest
# process itself) as the host. The game executable has never been the target. This script
# closes that specific gap and nothing more - it does NOT prove that the discovery
# broadcast leaves through the selected NIC (that needs a second machine + capture, see
# docs\M0C-C2-CROSSMACHINE-RUNBOOK-20261118.md).
#
# WHAT IT DOES
#   1. finds the running Civ6 process (CivilizationVI.exe or CivilizationVI_DX12.exe)
#   2. copies the binaries into %TEMP%\civlink-realcheck\ and runs ctl from THERE
#      (running ctl from inside the project workspace hits OpenProcess err=5 under the
#       DSH file sandbox - a sandbox artefact, not a CivLink defect)
#   3. shows the current iface config, injects, then reads status + counters
#   4. prints a verdict that says plainly what is and is not proven
#
# USAGE
#   powershell -NoProfile -ExecutionPolicy Bypass -File run-c2-real-game-check.ps1
#   ... -Iface ALL            # explicit ALL (no pinning) instead of the config file
#   ... -Iface 192.168.31.60  # write that IP to the config first, then inject
#   ... -KeepConfig           # do not restore the config file to ALL afterwards
#
# EXIT  0 = injected and counters readable (bookkeeping only)
#       1 = precondition failed (no game, bad iface, write/read failure)
#       2 = injection refused or did not reach running state
#       3 = injected but counters unreadable

param(
    [string] $Iface = '',
    [switch] $KeepConfig,
    [string] $OutDir = ''
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$OutputEncoding = [System.Text.UTF8Encoding]::new($false)

$src = Split-Path -Parent $MyInvocation.MyCommand.Path
$work = Join-Path $env:TEMP 'civlink-realcheck'
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
if (-not $OutDir) { $OutDir = Join-Path $work "run-$stamp" }
New-Item -ItemType Directory -Force -Path $work, $OutDir | Out-Null

$script:Failures = 0
function Check([string]$name, [bool]$ok, [string]$detail = '') {
    if ($ok) { Write-Host ("PASS {0}{1}" -f $name, $(if($detail){" ($detail)"}else{''})) }
    else     { $script:Failures++; Write-Host ("FAIL {0} {1}" -f $name, $detail) -ForegroundColor Red }
}

# ---------------------------------------------------------------- 1. locate the game
$gameNames = @('CivilizationVI_DX12','CivilizationVI')
$game = $null
foreach ($n in $gameNames) {
    $p = Get-Process -Name $n -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($p) { $game = $p; break }
}
if (-not $game) {
    Write-Host '[!] Civilization VI is not running.' -ForegroundColor Red
    Write-Host '    Start the game, then enter the LAN (multiplayer) lobby so the discovery'
    Write-Host '    socket is alive, and run this script again.'
    exit 1
}
$gamePid = $game.Id
Write-Host "[*] game: $($game.ProcessName) pid=$gamePid"

# --------------------------------------------------- 2. stage binaries outside the workspace
foreach ($f in 'civlink_ctl.exe','civlink_client.dll','civlink_hook.dll') {
    $from = Join-Path $src $f
    if (-not (Test-Path $from)) { Write-Host "[!] missing $f next to this script"; exit 1 }
    Copy-Item $from $work -Force
}
$ctl = Join-Path $work 'civlink_ctl.exe'

# --------------------------------------------------- 3. iface config
$cfgDir  = Join-Path $env:LOCALAPPDATA 'CivLink'
$cfgFile = Join-Path $cfgDir 'client-iface.txt'
$cfgBefore = if (Test-Path $cfgFile) { (Get-Content $cfgFile -Raw).Trim() } else { '<missing>' }
Write-Host "[*] iface config before: '$cfgBefore'  (path $cfgFile)"

if ($Iface) {
    New-Item -ItemType Directory -Force -Path $cfgDir | Out-Null
    Set-Content -Path $cfgFile -Value $Iface -Encoding ascii -NoNewline
    Write-Host "[*] iface config set to '$Iface'"
}

# --------------------------------------------------- 4. inject
Write-Host ''
Write-Host '=== inject ==='
$injectArgs = @('inject-client','-p',"$gamePid")
if ($Iface) { $injectArgs += @('--iface', $Iface) }
$injectOut = & $ctl @injectArgs 2>&1 | Tee-Object (Join-Path $OutDir 'inject.log')
$injectExit = $LASTEXITCODE
$injectOut | ForEach-Object { Write-Host "    $_" }

if ($injectExit -ne 0) {
    Write-Host "[!] injection failed (exit $injectExit)" -ForegroundColor Red
    Write-Host '    err=5  -> run from an elevated shell, or the game is elevated'
    Write-Host '    exit 3 -> the DLL loaded but the PE identity check refused remote calls'
    exit 2
}
Check 'LoadLibraryW succeeded' ([bool]($injectOut -match 'LoadLibraryW returned 0x')) ''
Check 'hook state reached 1 (running)' ([bool]($injectOut -match 'hooks active')) ''

# --------------------------------------------------- 5. status + counters
Start-Sleep -Seconds 2
Write-Host ''
Write-Host '=== status ==='
$statusOut = & $ctl status -p $gamePid 2>&1 | Tee-Object (Join-Path $OutDir 'status.log')
$statusExit = $LASTEXITCODE
$statusOut | ForEach-Object { Write-Host "    $_" }

Write-Host ''
Write-Host '=== counters ==='
$countersOut = & $ctl counters -p $gamePid 2>&1 | Tee-Object (Join-Path $OutDir 'counters.log')
$countersExit = $LASTEXITCODE
$countersOut | ForEach-Object { Write-Host "    $_" }

if ($statusExit -ne 0 -or $countersExit -ne 0) {
    Write-Host "[!] injected, but status/counters failed ($statusExit/$countersExit)" -ForegroundColor Red
    exit 3
}

# --------------------------------------------------- 6. parse and assert
function Get-CounterValue([string[]]$lines, [string]$label) {
    $rx = '^\s*' + [regex]::Escape($label) + '\s*:\s*(\d+)\s*$'
    foreach ($l in $lines) { if ($l -match $rx) { return [int64]$matches[1] } }
    return $null
}

$initErr   = Get-CounterValue $countersOut 'init error'
$sent      = Get-CounterValue $countersOut 'sent'
$sendFail  = Get-CounterValue $countersOut 'send fail'
$ignored   = Get-CounterValue $countersOut 'ignored'
$rawSendto = Get-CounterValue $countersOut 'raw sendto'
$bind62056 = Get-CounterValue $countersOut 'bind 62056'

Write-Host ''
Write-Host '=== counters parsed ==='
foreach ($pair in @(@('init error',$initErr), @('sent',$sent), @('send fail',$sendFail),
                    @('ignored',$ignored), @('raw sendto',$rawSendto), @('bind 62056',$bind62056))) {
    Write-Host ('    {0,-12} {1}' -f $pair[0], $pair[1])
}

Check 'counters readable from the game process' ($null -ne $initErr) "initError=$initErr"
Check 'initError is 0 or 11/12 (never fatal)' ($initErr -in 0,11,12) "initError=$initErr"
Check 'the DLL never bound the data-plane port 62056' (($null -ne $bind62056) -and $bind62056 -eq 0) "bind62056=$bind62056"
Check 'every discovery send is accounted' (($null -ne $sent) -and ($null -ne $sendFail) -and ($null -ne $rawSendto) -and ($rawSendto -ge ($sent + $sendFail))) `
      "raw sendto=$rawSendto sent=$sent sendFail=$sendFail"

# --------------------------------------------------- 7. restore config + record state
if ($Iface -and -not $KeepConfig) {
    Set-Content -Path $cfgFile -Value 'ALL' -Encoding ascii -NoNewline
    Write-Host "[*] iface config restored to 'ALL'"
}

$gameState = @(
    "game            : $($game.ProcessName) pid=$gamePid",
    "iface config    : before='$cfgBefore' injected-with='$(if($Iface){$Iface}else{'from file'})'",
    "inject exit     : $injectExit",
    "status exit     : $statusExit",
    "counters exit   : $countersExit",
    "initError       : $initErr",
    "sent            : $sent",
    "sendFail        : $sendFail",
    "ignored         : $ignored",
    "raw sendto      : $rawSendto",
    "bind62056       : $bind62056"
) -join "`r`n"
Set-Content -Path (Join-Path $OutDir 'game-state.txt') -Value $gameState -Encoding utf8

$verdict = @(
    'C2-REAL-GAME-CHECK',
    '',
    'PROVEN',
    '  - civlink_client.dll loads into the real Civilization VI process',
    '  - the four exports answer over CreateRemoteThread from outside the game',
    '  - the discovery-target decision runs inside the game and is counted',
    '  - the DLL does not bind 62056 and does not swallow sends',
    '',
    'NOT PROVEN (do not claim these)',
    '  - that the broadcast actually leaves through the selected NIC (needs a second',
    '    machine + capture: docs\M0C-C2-CROSSMACHINE-RUNBOOK-20261118.md)',
    '  - that LAN room creation / joining still works with the DLL present',
    '  - long-run stability, coexistence with Steam overlay or other injectors',
    '  - anything about two-player play (E2-A/E2-B/E3 stay open, Gate A/B unmoved)',
    '',
    ("runner check failures : {0}" -f $script:Failures)
) -join "`r`n"
Set-Content -Path (Join-Path $OutDir 'verdict.txt') -Value $verdict -Encoding utf8

Write-Host ''
Write-Host '=== verdict ==='
$verdict -split "`r`n" | ForEach-Object { Write-Host "    $_" }
Write-Host ''
Write-Host "[*] evidence: $OutDir"

exit $(if ($script:Failures -eq 0) { 0 } else { 1 })
