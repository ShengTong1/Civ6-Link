# run-f1-integration.ps1 - F1 integration: simulated host + real Civ6 client.
#
# Closes the F1 loop the codex review (m14211) said was still open: the discovery request
# leaves the game through civlink_hook.dll, arrives at the Agent via the CVLH2 channel, the
# Agent ANSWERS it as a simulated host (22 fixture pages injected over loopback), and the
# game's LAN lobby displays the simulated room.
#
# This is the first product-shaped path in the REV-016 plan: the simulated host is reachable
# ONLY through the DLL->Agent chain - the same shape a Relay would take in F3. The result is
# evidence labelled "simulated host -> real Civ6 client". It is NOT E2-B, NOT a multiplayer
# result, and does NOT move any Gate.
#
# Usage (must run from the NEUTRAL staging dir, not the Low-IL repo tree):
#   powershell -NoProfile -ExecutionPolicy Bypass -File run-f1-integration.ps1 `
#       -BinDir C:\Users\dd\Desktop\civlink-f1 -RefreshSeconds 120
# Exit: 0 all checks passed, 1 a check failed, 2 precondition missing, 6 inject failed.
[CmdletBinding()]
param(
    [string]$BinDir = '',
    [string]$ExeName = 'CivilizationVI_DX12.exe',
    [int]$ProcessId = 0,
    [string]$FixtureDir = '',
    [string]$OutRoot = '',
    [int]$RefreshSeconds = 120,
    [int]$SimMaxReplies = 10,
    # Empty = auto-detect the interface the discovery broadcast actually exits on, so the
    # simulated replies carry that interface's IP as source - the shape proven to display in
    # the F0 regression. Falls back to 127.0.0.1 (loopback) if detection fails.
    [string]$SimSrcIp = '',
    [string]$SimRoomName = 'CivLink-Test-Room-2222'
)

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
if ($BinDir -eq '') { $BinDir = $here }
$dll   = Join-Path $BinDir 'civlink_hook.dll'
$ctl   = Join-Path $BinDir 'civlink_ctl.exe'
$agent = Join-Path $BinDir 'civlink-agent.exe'

foreach ($f in @($dll, $ctl, $agent)) {
    if (-not (Test-Path $f)) { Write-Host "[!] missing $f - stage the F1 binaries in $BinDir"; exit 2 }
}

# Fixture: the 22 reply pages captured in H4/E2-A.
if ($FixtureDir -eq '') {
    $repoRoot = Split-Path (Split-Path $here -Parent) -Parent
    $FixtureDir = Join-Path $repoRoot 'M0A\captures\E2A-H4-reply-20261113\reply-set'
}
$fixtureOk = (Test-Path $FixtureDir) -and ((Get-ChildItem (Join-Path $FixtureDir 'reply-*.bin')).Count -eq 22)
if (-not $fixtureOk) { Write-Host "[!] fixture missing at $FixtureDir (need reply-01..22.bin)"; exit 2 }

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
if ($OutRoot -ne '') {
    $captures = $OutRoot
} else {
    $repoRoot = Split-Path (Split-Path $here -Parent) -Parent
    if (Test-Path (Join-Path $repoRoot 'M0A')) { $captures = Join-Path $repoRoot 'M0A\captures' }
    else { $captures = Join-Path $here 'captures' }
}
$outDir = Join-Path $captures "F1-integration-$stamp"
New-Item -ItemType Directory -Path $outDir -Force | Out-Null

$stopFile     = Join-Path $outDir 'STOP'
$agentConsole = Join-Path $outDir 'agent-console.txt'

Write-Host "[*] evidence: $outDir"
Write-Host "[*] fixture:  $FixtureDir"

# --- target ------------------------------------------------------------------
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

# --- simulated host source address ------------------------------------------
if ($SimSrcIp -eq '') {
    try {
        $route = Find-NetRoute -RemoteIPAddress 255.255.255.255 -ErrorAction Stop | Select-Object -First 1
        $ip = Get-NetIPAddress -InterfaceIndex $route.InterfaceIndex -AddressFamily IPv4 -ErrorAction Stop |
            Where-Object { $_.PrefixOrigin -notin @('WellKnown', 'Anycast') } |
            Select-Object -First 1
        if ($ip) { $SimSrcIp = $ip.IPAddress }
    } catch { }
    if ($SimSrcIp -eq '') { $SimSrcIp = '127.0.0.1' }
}
Write-Host "[*] simulated host reply source: $SimSrcIp`:62900 (room '$SimRoomName')"

# --- port preconditions ------------------------------------------------------
$busy = @(Get-NetUDPEndpoint -LocalPort 34718 -ErrorAction SilentlyContinue)
if ($busy.Count -gt 0) {
    $ownerPids = ($busy | ForEach-Object { $_.OwningProcess } | Sort-Object -Unique) -join ','
    Write-Host "[!] 127.0.0.1:34718 is already bound (pid=$ownerPids) - stop that Agent first"
    exit 2
}
$holders = @(Get-NetUDPEndpoint -LocalPort 62900 -ErrorAction SilentlyContinue |
    Where-Object { $_.LocalAddress -notmatch ':' -and $_.LocalAddress -in @('0.0.0.0', '127.0.0.1', $SimSrcIp) })
if ($holders.Count -gt 0) {
    $ownerPids = ($holders | ForEach-Object { $_.OwningProcess } | Sort-Object -Unique) -join ','
    Write-Host "[!] $SimSrcIp:62900 is already bound (pid=$ownerPids) - the simulated host cannot reply"
    exit 2
}

# --- start the agent with --simulate ------------------------------------------
$agentArgs = @(
    '--listen-seconds', '0', '--out-dir', $outDir, '--stop-file', $stopFile,
    '--simulate', $FixtureDir, '--sim-max-replies', "$SimMaxReplies",
    '--sim-src-ip', $SimSrcIp, '--sim-room-name', $SimRoomName, '--quiet'
)
$agentProc = Start-Process -FilePath $agent -ArgumentList $agentArgs -PassThru -WindowStyle Hidden `
    -RedirectStandardOutput $agentConsole
Start-Sleep -Milliseconds 1200
if ($agentProc.HasExited) {
    Write-Host "[!] agent exited immediately (code=$($agentProc.ExitCode)) - see $agentConsole"
    Get-Content $agentConsole -ErrorAction SilentlyContinue | ForEach-Object { Write-Host "    $_" }
    exit 2
}
Write-Host "[*] agent pid=$($agentProc.Id) listening on 127.0.0.1:34718 (simulated host up)"

# --- inject ------------------------------------------------------------------
$injOut  = & $ctl inject -x $ExeName -p $targetPid -d $dll -w 8 *>&1
$injExit = $LASTEXITCODE
$injOut | Tee-Object -FilePath (Join-Path $outDir 'inject.txt')
if ($injExit -ne 0) {
    Write-Host "[!] inject failed (exit=$injExit)"
    $statusOut = & $ctl status -x $ExeName -p $targetPid *>&1
    Write-Host $statusOut
    if (($statusOut -join ' ') -match 'shut down') {
        Write-Host "[!] the hook in this game process was already shut down by an earlier run."
        Write-Host "    A shut-down hook cannot be re-armed: restart Civ6 (close and reopen),"
        Write-Host "    re-enter the LAN lobby, then run this driver again."
    }
    New-Item -ItemType File -Path $stopFile -Force | Out-Null
    $agentProc.WaitForExit(8000) | Out-Null
    exit 6
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

Write-Host ""
Write-Host "=============================================================="
Write-Host " NOW: in Civ6's LAN lobby click  Refresh  3 times,"
Write-Host "      spread over the next $RefreshSeconds seconds."
Write-Host "      Then tell me whether the room '$SimRoomName' shows up."
Write-Host "=============================================================="
Write-Host ""

# Fixed poll window: the driver cannot read the game UI (no screenshots by design),
# so the machine side just watches the hook counters while the operator clicks.
$waited = 0
while ($waited -lt $RefreshSeconds) {
    Start-Sleep -Seconds 2
    $waited += 2
    $now     = & $ctl counters -x $ExeName -p $targetPid *>&1
    $sentNow = Read-Counter $now 'sent'
    $failNow = Read-Counter $now 'send fail'
    $rejNow  = Read-Counter $now 'reject oversize'
    $ignNow  = Read-Counter $now 'ignored'
    if ($null -ne $sentNow) {
        Write-Host ("    t={0,3}s sent={1} fail={2} oversize={3} ignored={4}" -f $waited, $sentNow, $failNow, $rejNow, $ignNow)
    }
}

# --- stop the agent cleanly --------------------------------------------------
New-Item -ItemType File -Path $stopFile -Force | Out-Null
$agentProc.WaitForExit(8000) | Out-Null
if (-not $agentProc.HasExited) {
    Stop-Process -Id $agentProc.Id -Force
    Write-Host "[!] agent had to be killed - summary may be incomplete"
}

$after = & $ctl counters -x $ExeName -p $targetPid *>&1
$after | Out-File -FilePath (Join-Path $outDir 'counters-after.txt') -Encoding UTF8

$summary = Join-Path $outDir 'summary.txt'
Write-Host ""
if (Test-Path $summary) { Write-Host "--- agent summary ---"; Get-Content $summary }
else { Write-Host "[!] agent wrote no summary" }

# --- reconciliation + simulated-host checks ----------------------------------
$fail = 0
function Check([string]$what, [bool]$ok, [string]$detail = '') {
    if ($ok) { Write-Host ("  PASS {0,-56} {1}" -f $what, $detail) }
    else { Write-Host ("  FAIL {0,-56} {1}" -f $what, $detail); $script:fail++ }
}

$reportLines = @()
if (Test-Path $summary) {
    $s = Get-Content $summary -Raw
    $processed = if ($s -match 'processed (\d+), rejected') { [int]$Matches[1] } else { -1 }
    $rejected  = if ($s -match 'rejected (\d+)\)') { [int]$Matches[1] } else { -1 }
    $simSeen   = if ($s -match 'requests seen   : (\d+)') { [int]$Matches[1] } else { -1 }
    $simReplied = if ($s -match 'replied sockets : (\d+)') { [int]$Matches[1] } else { -1 }
    $simPages  = if ($s -match 'pages sent      : (\d+)') { [int]$Matches[1] } else { -1 }
    $simFail   = if ($s -match 'send fail       : (\d+)') { [int]$Matches[1] } else { -1 }
    $simNoEp   = if ($s -match 'no endpoint     : (\d+)') { [int]$Matches[1] } else { -1 }
    $simMax    = if ($s -match 'max reached     : (\d+)') { [int]$Matches[1] } else { -1 }
    $simBind   = if ($s -match 'bind fail       : (\d+)') { [int]$Matches[1] } else { -1 }

    $sentAfter  = Read-Counter $after 'sent'
    $sentNotify = Read-Counter $after 'sent notify'
    $ignored    = Read-Counter $after 'ignored'
    $hookFail   = Read-Counter $after 'send fail'

    $delta = -1
    if ($null -ne $sentBefore -and $null -ne $sentAfter) { $delta = [int64]$sentAfter - [int64]$sentBefore }

    $reportLines += "F1-INTEGRATION verify report - $stamp"
    $reportLines += "room            : $SimRoomName"
    $reportLines += "sim source      : $SimSrcIp:62900"
    $reportLines += "hook sent delta : $delta (before=$sentBefore after=$sentAfter)"
    $reportLines += "agent processed : $processed rejected=$rejected"
    $reportLines += "sim seen/replied: $simSeen / $simReplied sockets, $simPages pages"
    $reportLines += "sim fail        : send=$simFail no_endpoint=$simNoEp max=$simMax bind=$simBind"
    $reportLines += "hook fail/notify/ignored: $hookFail / $sentNotify / $ignored"

    Check "hook captured discovery sends" ($delta -gt 0) "delta=$delta"
    Check "hook.sent delta == agent.processed" ($delta -eq $processed) "delta=$delta processed=$processed"
    Check "agent rejected 0 frames" ($rejected -eq 0) "rejected=$rejected"
    Check "sim saw at least one discovery request" ($simSeen -ge 1) "seen=$simSeen"
    Check "sim replied at least one socket" ($simReplied -ge 1) "replied=$simReplied"
    Check "sim sent 22 pages per replied socket" ($simPages -eq 22 * $simReplied) "pages=$simPages replied=$simReplied"
    Check "sim send fail == 0" ($simFail -eq 0) "sendFail=$simFail"
    Check "sim bind fail == 0" ($simBind -eq 0) "bindFail=$simBind"
    Check "sim budget not exhausted" ($simMax -eq 0) "maxReached=$simMax"
} else {
    Check "agent summary exists" $false
}

$reportLines | Out-File -FilePath (Join-Path $outDir 'verify-report.txt') -Encoding UTF8

Write-Host ""
if ($fail -eq 0) {
    Write-Host "F1-INTEGRATION: PASS (simulated host answered the real client through the Hook chain)"
} else {
    Write-Host "F1-INTEGRATION: FAIL ($fail failed check(s))"
}
Write-Host "[*] evidence: $outDir"
Write-Host "[*] note: the hook stays mapped in the game process (B2 audit-run mode)."
Write-Host "          run 'civlink_ctl.exe shutdown -x $ExeName' or just exit Civ6."
if ($fail -eq 0) { exit 0 } else { exit 1 }
