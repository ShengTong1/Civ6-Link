# run-f1-live.ps1 - F1 live observation against the real Civ6 client.
#
# What this does (and nothing more):
#   1. starts civlink-agent on 127.0.0.1:34718 with an unbounded window and a stop file,
#   2. injects civlink_hook.dll into the real Civ6 process,
#   3. waits while the operator clicks Refresh in the LAN lobby,
#   4. reads the hook counters, stops the agent cleanly, prints the reconciliation.
#
# It does NOT modify game traffic, does NOT forward anything to a peer, and does NOT
# constitute a multiplayer / E2-B / Gate A result. It only answers: does the real client
# actually reach sendto/WSASendTo with a discovery broadcast, and do the frames reconcile.

[CmdletBinding()]
param(
    [string]$ExeName = 'CivilizationVI_DX12.exe',
    [int]$ProcessId = 0,
    [int]$InjectWaitSec = 8,
    [int]$AutoStopSeconds = 0,
    # Evidence root. Defaults to <repo>\M0A\captures when this script sits in
    # CivLink-M0A-audit\civlink\, otherwise to .\captures next to the script.
    [string]$OutRoot = ''
)

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot

$dll   = Join-Path $here 'civlink_hook.dll'
$ctl   = Join-Path $here 'civlink_ctl.exe'
$agent = Join-Path $here 'civlink-agent.exe'

foreach ($f in @($dll, $ctl, $agent)) {
    if (-not (Test-Path $f)) { Write-Host "[!] missing $f (run build-msvc.cmd first)"; exit 2 }
}

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
if ($OutRoot -ne '') {
    $captures = $OutRoot
} else {
    $repoRoot = Split-Path (Split-Path $here -Parent) -Parent
    if (Test-Path (Join-Path $repoRoot 'M0A')) { $captures = Join-Path $repoRoot 'M0A\captures' }
    else { $captures = Join-Path $here 'captures' }
}
$outDir = Join-Path $captures "F1-live-$stamp"
New-Item -ItemType Directory -Path $outDir -Force | Out-Null

$stopFile     = Join-Path $outDir 'STOP'
$agentConsole = Join-Path $outDir 'agent-console.txt'
$hookLog      = Join-Path $outDir 'hook-events.txt'

Write-Host "[*] evidence: $outDir"

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

# --- port precondition -------------------------------------------------------
$busy = @(Get-NetUDPEndpoint -LocalPort 34718 -ErrorAction SilentlyContinue)
if ($busy.Count -gt 0) {
    $ownerPids = ($busy | ForEach-Object { $_.OwningProcess } | Sort-Object -Unique) -join ','
    Write-Host "[!] 127.0.0.1:34718 is already bound (pid=$ownerPids) - stop that Agent first"
    exit 2
}

# --- start the agent ---------------------------------------------------------
$agentArgs = @('--listen-seconds', '0', '--out-dir', $outDir, '--stop-file', $stopFile, '--quiet')
$agentProc = Start-Process -FilePath $agent -ArgumentList $agentArgs -PassThru -WindowStyle Hidden `
    -RedirectStandardOutput $agentConsole
Start-Sleep -Milliseconds 700
if ($agentProc.HasExited) {
    Write-Host "[!] agent exited immediately (code=$($agentProc.ExitCode)) - see $agentConsole"
    exit 2
}
Write-Host "[*] agent pid=$($agentProc.Id) listening on 127.0.0.1:34718"

# --- inject ------------------------------------------------------------------
$injOut  = & $ctl inject -x $ExeName -p $targetPid -d $dll -w $InjectWaitSec *>&1
$injExit = $LASTEXITCODE
$injOut | Tee-Object -FilePath (Join-Path $outDir 'inject.txt')
if ($injExit -ne 0) {
    Write-Host "[!] inject failed (exit=$injExit)"
    New-Item -ItemType File -Path $stopFile -Force | Out-Null
    $agentProc.WaitForExit(8000) | Out-Null
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
Write-Host ""
Write-Host "=============================================================="
Write-Host " NOW: in Civ6 go to  Multiplayer > LAN  and click  Refresh"
Write-Host "      a few times (3-5 is plenty). Leave the lobby open."
Write-Host " Then press ENTER here so the window can be closed cleanly."
Write-Host " (or create the STOP file, or let -AutoStopSeconds expire)"
Write-Host "=============================================================="
Write-Host ""

# Poll while waiting so the operator can watch frames arrive.
$stopRequested = $false
$canReadKeys   = $true
$waited        = 0
while (-not $stopRequested) {
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
    if (Test-Path $stopFile) { $stopRequested = $true; break }
    if ($AutoStopSeconds -gt 0 -and $waited -ge $AutoStopSeconds) { $stopRequested = $true; break }
    if ($canReadKeys) {
        try {
            if ([Console]::KeyAvailable) {
                $null = [Console]::ReadKey($true)
                $stopRequested = $true
            }
        } catch {
            # No console attached (driven from a script): rely on the stop file only.
            $canReadKeys = $false
            Write-Host "    (no console - create the STOP file to end the window)"
        }
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
$after | Tee-Object -FilePath $hookLog

$summary  = Join-Path $outDir 'summary.txt'
$frameLog = Join-Path $outDir 'frame-log.txt'
Write-Host ""
if (Test-Path $summary) { Write-Host "--- agent summary ---"; Get-Content $summary }
else { Write-Host "[!] agent wrote no summary" }

# --- reconciliation ----------------------------------------------------------
$fail = 0
function Check([string]$what, [bool]$ok, [string]$detail = '') {
    if ($ok) { Write-Host ("  PASS {0,-52} {1}" -f $what, $detail) }
    else { Write-Host ("  FAIL {0,-52} {1}" -f $what, $detail); $script:fail++ }
}

if (Test-Path $summary) {
    $s = Get-Content $summary -Raw
    $processed = if ($s -match 'processed (\d+), rejected') { [int]$Matches[1] } else { -1 }
    $received  = if ($s -match 'received frames : (\d+)') { [int]$Matches[1] } else { -1 }

    $sentAfter  = Read-Counter $after 'sent'
    $sentNotify = Read-Counter $after 'sent notify'
    $ignored    = Read-Counter $after 'ignored'
    $hookFail   = Read-Counter $after 'send fail'

    if ($null -ne $sentBefore -and $null -ne $sentAfter) {
        $delta = [int64]$sentAfter - [int64]$sentBefore
        Check "hook captured at least one discovery send" ($delta -gt 0) "delta=$delta"
        Check "hook.sent delta == agent.processed" ($delta -eq $processed) "delta=$delta processed=$processed"
    } else {
        Check "hook counters readable" $false
    }
    Check "agent received at least one frame" ($received -gt 0) "received=$received"
    Check "hook send fail is 0" ($hookFail -eq 0) "sendFail=$hookFail"
    Write-Host ("  info ignored non-discovery = {0}" -f $ignored)
    Write-Host ("  info sent notify (oversize) = {0}" -f $sentNotify)

    $ports = @()
    if (Test-Path $frameLog) {
        foreach ($line in (Get-Content $frameLog)) {
            if ($line -match 'dst=[\d.]+:(\d+)') { $ports += [int]$Matches[1] }
        }
    }
    $inRange = @($ports | Where-Object { $_ -ge 62900 -and $_ -le 62999 })
    Check "every observed destination is a discovery port" `
        ($ports.Count -gt 0 -and $inRange.Count -eq $ports.Count) `
        "frames=$($ports.Count) inRange=$($inRange.Count)"
    $distinct = @($inRange | Sort-Object -Unique).Count
    Check "observed more than one discovery port" ($distinct -gt 1) "distinct=$distinct"
} else {
    Check "agent summary exists" $false
}

Write-Host ""
if ($fail -eq 0) {
    Write-Host "F1-LIVE: PASS (real client frames reconciled; F1 evidence only)"
} else {
    Write-Host "F1-LIVE: FAIL ($fail failed check(s))"
}
Write-Host "[*] evidence: $outDir"
Write-Host "[*] note: the hook stays mapped in the game process (B2 audit-run mode)."
Write-Host "          run 'civlink_ctl.exe shutdown -x $ExeName' or just exit Civ6."
if ($fail -eq 0) { exit 0 } else { exit 1 }
