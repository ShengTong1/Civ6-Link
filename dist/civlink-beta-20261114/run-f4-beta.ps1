# run-f4-beta.ps1 - F4 release-candidate single-machine acceptance driver.
#
# What this does (and nothing more):
#   1. writes VERSIONS.txt from --version / usage of agent, relay, ctl (version check),
#   2. starts civlink-agent on 127.0.0.1:34718 in simulator-host mode (--simulate fixture)
#      plus datapath observation (--simulate-datapath --bind-ip 127.0.0.1, D4 single 20 B probe),
#   3. starts civlink-relay on 127.0.0.1:34720 (path state available, no peer expected),
#   4. injects civlink_hook.dll into the real Civ6 process,
#   5. waits while the operator clicks Refresh in the LAN lobby (discovery regression) and
#      optionally clicks Join once (datapath regression; the simulated host answers nothing,
#      so Join stalls on "retrieving host info" - that is the expected D4 behaviour, not a bug),
#   6. reads hook counters + agent summary (user-visible path state), stops everything cleanly,
#   7. asserts the layered reconciliation and writes the evidence pack.
#
# Boundaries (REV-016 F4): this is a SINGLE-MACHINE acceptance with a SIMULATED peer.
# It does NOT prove two real Civ6 processes joined a match, does NOT move Gate A/B,
# does NOT validate Relay under a real second peer. Release label: "模拟对端/发现助手测试版"
# only - never "双人真实联机已通过".

[CmdletBinding()]
param(
    [string]$ExeName = 'CivilizationVI_DX12.exe',
    [int]$ProcessId = 0,
    [int]$InjectWaitSec = 8,
    [int]$AutoStopSeconds = 0,
    # Where the four binaries and fixture live. Default: next to this script.
    [string]$BinDir = '',
    # Evidence root. Defaults to <repo>\M0A\captures when the repo is found.
    [string]$OutRoot = '',
    [string]$RoomName = 'CivLink-Beta-Room-2222'
)

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
if ($BinDir -eq '') { $BinDir = $here }

$dll   = Join-Path $BinDir 'civlink_hook.dll'
$ctl   = Join-Path $BinDir 'civlink_ctl.exe'
$agent = Join-Path $BinDir 'civlink-agent.exe'
$relay = Join-Path $BinDir 'civlink-relay.exe'
$fx    = Join-Path $BinDir 'fixture-reply-set'

foreach ($f in @($dll, $ctl, $agent, $relay)) {
    if (-not (Test-Path $f)) { Write-Host "[!] missing $f"; exit 2 }
}
if (-not (Test-Path (Join-Path $fx 'reply-01.bin'))) {
    Write-Host "[!] fixture not found at $fx (need reply-01.bin..reply-22.bin)"; exit 2
}

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
if ($OutRoot -ne '') { $captures = $OutRoot }
else {
    $repoRoot = Split-Path (Split-Path $here -Parent) -Parent
    if (Test-Path (Join-Path $repoRoot 'M0A')) { $captures = Join-Path $repoRoot 'M0A\captures' }
    else { $captures = Join-Path $here 'captures' }
}
$outDir = Join-Path $captures "F4-beta-$stamp"
New-Item -ItemType Directory -Path $outDir -Force | Out-Null

$stopAgent   = Join-Path $outDir 'STOP-agent'
$stopRelay   = Join-Path $outDir 'STOP-relay'
$agentConsole = Join-Path $outDir 'agent-console.txt'
$relayConsole = Join-Path $outDir 'relay-console.txt'

Write-Host "[*] evidence: $outDir"

# --- 0. version detection -----------------------------------------------------
$versions = @()
$versions += "civlink-agent: " + (& $agent --version 2>&1)
$versions += "civlink-relay: " + (& $relay --version 2>&1)
$versions += "civlink_ctl  : " + ((& $ctl 2>&1) | Select-Object -First 1)
$versions | Out-File -FilePath (Join-Path $outDir 'VERSIONS.txt') -Encoding UTF8
Write-Host "[*] versions:"
$versions | ForEach-Object { Write-Host "    $_" }

# --- target -------------------------------------------------------------------
$procs = @(Get-Process -Name ([IO.Path]::GetFileNameWithoutExtension($ExeName)) -ErrorAction SilentlyContinue)
if ($ProcessId -ne 0) { $procs = @($procs | Where-Object { $_.Id -eq $ProcessId }) }
if ($procs.Count -eq 0) {
    Write-Host "[!] $ExeName is not running - start Civ6 and open the LAN lobby first"
    exit 2
}
if ($procs.Count -gt 1) {
    Write-Host "[!] $($procs.Count) processes match - pass -ProcessId"
    $procs | ForEach-Object { Write-Host "      pid=$($_.Id)" }
    exit 2
}
$targetPid = $procs[0].Id
Write-Host "[*] target pid=$targetPid ($ExeName)"

# --- port preconditions -------------------------------------------------------
foreach ($port in @(34718, 34720)) {
    $busy = @(Get-NetUDPEndpoint -LocalPort $port -ErrorAction SilentlyContinue)
    if ($busy.Count -gt 0) {
        $ownerPids = ($busy | ForEach-Object { $_.OwningProcess } | Sort-Object -Unique) -join ','
        Write-Host "[!] port $port already bound (pid=$ownerPids) - stop that process first"
        exit 2
    }
}

# --- start agent (simulated host + datapath observer) --------------------------
$agentArgs = @('--listen-seconds', '0', '--out-dir', $outDir, '--stop-file', $stopAgent, '--quiet',
    '--simulate', $fx, '--sim-max-replies', '20', '--sim-src-ip', '127.0.0.1', '--sim-room-name', $RoomName,
    '--simulate-datapath', '--bind-ip', '127.0.0.1')
$agentProc = Start-Process -FilePath $agent -ArgumentList $agentArgs -PassThru -WindowStyle Hidden `
    -RedirectStandardOutput $agentConsole
Start-Sleep -Milliseconds 700
if ($agentProc.HasExited) {
    Write-Host "[!] agent exited immediately (code=$($agentProc.ExitCode)) - see $agentConsole"
    exit 2
}
Write-Host "[*] agent pid=$($agentProc.Id) simulated host on 127.0.0.1:62900, IPC 34718"

# --- start relay (path state available) ----------------------------------------
$relayArgs = @('--listen', '127.0.0.1:34720', '--listen-seconds', '0', '--out-dir', $outDir,
    '--stop-file', $stopRelay, '--quiet')
$relayProc = Start-Process -FilePath $relay -ArgumentList $relayArgs -PassThru -WindowStyle Hidden `
    -RedirectStandardOutput $relayConsole
Start-Sleep -Milliseconds 700
if ($relayProc.HasExited) {
    Write-Host "[!] relay exited immediately (code=$($relayProc.ExitCode))"
    New-Item -ItemType File -Path $stopAgent -Force | Out-Null
    $agentProc.WaitForExit(8000) | Out-Null
    exit 2
}
Write-Host "[*] relay pid=$($relayProc.Id) on 127.0.0.1:34720"

# --- inject --------------------------------------------------------------------
$injOut  = & $ctl inject -x $ExeName -p $targetPid -d $dll -w $InjectWaitSec *>&1
$injExit = $LASTEXITCODE
$injOut | Tee-Object -FilePath (Join-Path $outDir 'inject.txt')
if ($injExit -ne 0) {
    Write-Host "[!] inject failed (exit=$injExit)"
    New-Item -ItemType File -Path $stopAgent -Force | Out-Null
    New-Item -ItemType File -Path $stopRelay -Force | Out-Null
    $agentProc.WaitForExit(8000) | Out-Null
    $relayProc.WaitForExit(8000) | Out-Null
    exit $injExit
}

# --- counters ----------------------------------------------------------------
function Read-Counter([string[]]$text, [string]$label) {
    foreach ($line in $text) {
        if ($line -match ('^' + [regex]::Escape($label) + '\s*:\s*(\d+)')) { return [uint64]$Matches[1] }
    }
    return $null
}

$before = & $ctl counters -x $ExeName -p $targetPid *>&1
$before | Out-File -FilePath (Join-Path $outDir 'counters-before.txt') -Encoding UTF8
$sentBefore = Read-Counter $before 'sent'
Write-Host "[*] baseline hook counters: sent=$sentBefore"

$state0 = & $ctl status -x $ExeName -p $targetPid *>&1
$state0 | Out-File -FilePath (Join-Path $outDir 'path-state-before.txt') -Encoding UTF8
Write-Host "[*] path state:"
$state0 | ForEach-Object { Write-Host "    $_" }

Write-Host ""
Write-Host "=============================================================="
Write-Host " NOW: in Civ6 go to  Multiplayer > LAN  and click  Refresh"
Write-Host "      at least 3 times - the simulated room should appear"
Write-Host "      ('$RoomName'). Optionally click Join ONCE: the simulated"
Write-Host "      host answers nothing (D4), so Join stalls on"
Write-Host "      'retrieving host info' - that is expected, not a bug."
Write-Host " Then press ENTER here to close the window cleanly."
Write-Host " (or create the STOP files, or let -AutoStopSeconds expire)"
Write-Host "=============================================================="
Write-Host ""

$stopRequested = $false
$canReadKeys   = $true
$waited        = 0
while (-not $stopRequested) {
    Start-Sleep -Seconds 2
    $waited += 2
    $now     = & $ctl counters -x $ExeName -p $targetPid *>&1
    $sentNow = Read-Counter $now 'sent'
    if ($null -ne $sentNow) {
        Write-Host ("    t={0,3}s sent={1}" -f $waited, $sentNow)
    }
    if ((Test-Path $stopAgent) -and (Test-Path $stopRelay)) { $stopRequested = $true; break }
    if ($AutoStopSeconds -gt 0 -and $waited -ge $AutoStopSeconds) { $stopRequested = $true; break }
    if ($canReadKeys) {
        try {
            if ([Console]::KeyAvailable) {
                $null = [Console]::ReadKey($true)
                $stopRequested = $true
            }
        } catch {
            $canReadKeys = $false
            Write-Host "    (no console - create STOP-agent and STOP-relay to end)"
        }
    }
}

# --- clean stop ----------------------------------------------------------------
New-Item -ItemType File -Path $stopAgent -Force | Out-Null
New-Item -ItemType File -Path $stopRelay -Force | Out-Null
$agentProc.WaitForExit(8000) | Out-Null
$relayProc.WaitForExit(8000) | Out-Null
if (-not $agentProc.HasExited) { Stop-Process -Id $agentProc.Id -Force; Write-Host "[!] agent killed" }
if (-not $relayProc.HasExited) { Stop-Process -Id $relayProc.Id -Force; Write-Host "[!] relay killed" }

# DLL shutdown: disable hooks + drain, module stays mapped until process exit
# (B2 audit-run mode; the injector never FreeLibrarys a live process).
$shut = & $ctl shutdown -x $ExeName -p $targetPid *>&1
$shutExit = $LASTEXITCODE
$shut | Tee-Object -FilePath (Join-Path $outDir 'shutdown.txt')
Write-Host "[*] hook shutdown exit=$shutExit (B2: module left mapped until Civ6 exits)"

$after = & $ctl counters -x $ExeName -p $targetPid *>&1
$after | Out-File -FilePath (Join-Path $outDir 'counters-after.txt') -Encoding UTF8
$state1 = & $ctl status -x $ExeName -p $targetPid *>&1
$state1 | Out-File -FilePath (Join-Path $outDir 'path-state-after.txt') -Encoding UTF8

$summary  = Join-Path $outDir 'summary.txt'
$frameLog = Join-Path $outDir 'frame-log.txt'
if (Test-Path $summary) { Write-Host "--- agent summary ---"; Get-Content $summary }
else { Write-Host "[!] agent wrote no summary" }

# --- assertions ---------------------------------------------------------------
$fail = 0
function Check([string]$what, [bool]$ok, [string]$detail = '') {
    if ($ok) { Write-Host ("  PASS {0,-52} {1}" -f $what, $detail) }
    else { Write-Host ("  FAIL {0,-52} {1}" -f $what, $detail); $script:fail++ }
}

if (Test-Path $summary) {
    $s = Get-Content $summary -Raw
    $processed = if ($s -match 'processed (\d+), rejected') { [int]$Matches[1] } else { -1 }
    $received  = if ($s -match 'received frames : (\d+)') { [int]$Matches[1] } else { -1 }
    $seenSim   = if ($s -match 'requests seen\s*:\s*(\d+)') { [int]$Matches[1] } else { -1 }
    $replied   = if ($s -match 'replied sockets\s*:\s*(\d+)') { [int]$Matches[1] } else { -1 }
    $pages     = if ($s -match 'pages sent\s*:\s*(\d+)') { [int]$Matches[1] } else { -1 }
    $dpSeen    = if ($s -match 'frames seen\s*:\s*(\d+)') { [int]$Matches[1] } else { -1 }
    $dpReply   = if ($s -match 'reply sent\s*:\s*(\d+)') { [int]$Matches[1] } else { -1 }

    $sentAfter  = Read-Counter $after 'sent'
    $hookFail   = Read-Counter $after 'send fail'
    $obsAfter   = Read-Counter $after 'observed frames'
    $obsBefore  = Read-Counter $before 'observed frames'

    if ($null -ne $sentBefore -and $null -ne $sentAfter) {
        $delta = [int64]$sentAfter - [int64]$sentBefore
        Check "hook captured at least one discovery send" ($delta -gt 0) "delta=$delta"
        # layered reconciliation (F2): hook.sent + hook.observed == agent.processed
        $obsDelta = if ($null -ne $obsAfter -and $null -ne $obsBefore) { [int64]$obsAfter - [int64]$obsBefore } else { 0 }
        Check "hook.sent delta + observed delta == agent.processed" (($delta + $obsDelta) -eq $processed) "delta=$delta obsDelta=$obsDelta processed=$processed"
    } else {
        Check "hook counters readable" $false
    }
    Check "agent received at least one frame" ($received -gt 0) "received=$received"
    Check "simulated host saw requests and replied" ($seenSim -gt 0 -and $replied -gt 0) "seen=$seenSim replied=$replied"
    Check "sim pages sent == 22 x replied" ($pages -eq (22 * $replied)) "pages=$pages replied=$replied"
    Check "hook send fail is 0" ($hookFail -eq 0) "sendFail=$hookFail"
    Check "shutdown exit 0/1/2 accepted" (($shutExit -eq 0) -or ($shutExit -eq 1) -or ($shutExit -eq 2)) "exit=$shutExit"
    Write-Host ("  info datapath observed = {0} (join attempts surface 62056 frames)" -f $dpSeen)
    Write-Host ("  info D4 reply sent = {0} (at most one 20 B probe per run)" -f $dpReply)

    $ports = @()
    if (Test-Path $frameLog) {
        foreach ($line in (Get-Content $frameLog)) {
            if ($line -match 'dst=[\d.]+:(\d+)') { $ports += [int]$Matches[1] }
        }
    }
    # discovery frames must all land in 62900..62999; a Join attempt may surface
    # datapath frames to 62056 (F2 observation), which is expected, not a failure.
    $dpPorts    = @($ports | Where-Object { $_ -eq 62056 })
    $discovery  = @($ports | Where-Object { $_ -ge 62900 -and $_ -le 62999 })
    $bad        = @($ports | Where-Object { $_ -ne 62056 -and ($_ -lt 62900 -or $_ -gt 62999) })
    Check "every discovery destination in 62900..62999 (62056 = datapath join frames)" `
        ($ports.Count -gt 0 -and $bad.Count -eq 0) `
        "frames=$($ports.Count) discovery=$($discovery.Count) datapath62056=$($dpPorts.Count)"
} else {
    Check "agent summary exists" $false
}

Write-Host ""
if ($fail -eq 0) {
    Write-Host "F4-BETA: PASS (single-machine, simulated-host acceptance; F4 evidence only)"
} else {
    Write-Host "F4-BETA: FAIL ($fail failed check(s))"
}
Write-Host "[*] evidence: $outDir"
Write-Host "[*] label: 模拟对端/发现助手测试版 - NOT 双人真实联机"
Write-Host "[*] hook stays mapped until Civ6 exits (B2 audit-run mode)."
if ($fail -eq 0) { exit 0 } else { exit 1 }
