# run-f2-mechanical-selftest.ps1 - CivLink F2 mechanical self-test (S4)
#
# Proves (mechanically, no game, no remote peer):
#   * civlink_hook.dll: all six detours installed; discovery predicate; OBSERVED frame
#     for outbound traffic incl. the data-plane port 62056; bind/recvfrom/WSARecvFrom
#     observed without touching caller buffers (WSA_IO_PENDING canary path);
#   * civlink-agent --simulate-datapath: D4 single 20B local probe rule end to end,
#     fail-closed --bind-ip, loopback self-test mode;
#   * layered reconciliation: hook.sent + hook.observed == agent.processed,
#     hook.sentNotify == agent.rejected, all on the same frame set.
#
# Does NOT prove: Civ6 usage, H2/R1 bind coexistence, real peers, join, Gate A/B.
#
# Usage: run from the project's civlink\ dir. Requires the four binaries next to this
# script (civlink_hook.dll, civlink_agent.exe, hook_selftest.exe, civlink_ctl.exe) and a
# free TCP/UDP 127.0.0.1:34718. Exit: 0 = PASS, 1 = FAIL, 2 = precondition error.

$ErrorActionPreference = 'Continue'
$here = $PSScriptRoot
$agentExe   = Join-Path $here 'civlink-agent.exe'
$hookSelftestExe = Join-Path $here 'hook_selftest.exe'

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$outDir = Join-Path 'C:\Users\dd\Desktop\injciv6-v0.3.3\M0A\captures' "F2-mechanical-selftest-$stamp"
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

$fail = 0
function Check([string]$what, [bool]$ok, [string]$detail = '') {
    Write-Host ("  {0} {1,-58} {2}" -f ($(if ($ok) { 'PASS' } else { 'FAIL' })), $what, $detail)
    if (-not $ok) { $script:fail++ }
}

# ---- precondition: 34718 free ----
$pre = Get-NetUDPEndpoint -LocalAddress 127.0.0.1 -LocalPort 34718 -ErrorAction SilentlyContinue
if ($pre) { Write-Host "FAIL: 127.0.0.1:34718 already in use"; exit 2 }
foreach ($b in @($agentExe, $hookSelftestExe)) {
    if (-not (Test-Path $b)) { Write-Host "FAIL: missing $b"; exit 2 }
}

# ---- start agent: discovery observer + simulated data-plane (loopback self-test) ----
$agentArgs = @('--listen-seconds', '30', '--out-dir', $outDir,
               '--simulate-datapath', '--bind-ip', '127.0.0.1', '--loopback-selftest',
               '--quiet', '--stop-file', (Join-Path $outDir 'stop'))
$agent = Start-Process -FilePath $agentExe -ArgumentList $agentArgs -PassThru -NoNewWindow
Start-Sleep -Milliseconds 600
if ($agent.HasExited) { Write-Host "FAIL: agent exited early code=$($agent.ExitCode)"; exit 1 }

# ---- run hook self-test (agent must be listening) ----
$stamp2 = Get-Date -Format 'HH:mm:ss.fff'
$selftestOut = & $hookSelftestExe 2>&1 | ForEach-Object { $_.ToString() }
$selftestExit = $LASTEXITCODE
$selftestOut | Set-Content (Join-Path $outDir 'hook-selftest-console.txt') -Encoding UTF8
Write-Host "hook_selftest exit=$selftestExit (started $stamp2)"
$selftestOut | Where-Object { $_ -match '^  FAIL|^FATAL|HOOK-SELFTEST' } | ForEach-Object { Write-Host "  $_" }

# ---- stop agent via stop-file and wait for a clean summary ----
Set-Content -Path (Join-Path $outDir 'stop') -Value 'stop' -Encoding ASCII
$agentOk = $agent.WaitForExit(20000)
if (-not $agentOk) { Write-Host "FAIL: agent did not exit within 20s"; $agent.Kill(); exit 1 }
$summary = Get-Content (Join-Path $outDir 'summary.txt') -ErrorAction SilentlyContinue

# ---- hook-side assertions (the hook self-test itself checks most; verify exit) ----
Check 'hook_selftest exit == 0' ($selftestExit -eq 0) "exit=$selftestExit"
Check 'hook-selftest console has HOOK-SELFTEST: PASS' (
    (($selftestOut -join "`n") -match 'HOOK-SELFTEST: PASS'))

# ---- agent-side layered reconciliation (format: "received frames : 7 (processed 6, rejected 1)") ----
$t = $summary -join "`n"
Check 'agent summary exists' ($summary.Count -gt 0)
Check 'agent reconciliation ==' ($t -match 'reconciliation\s*:\s*processed \+ rejected = \d+ == received = \d+')
Check 'agent received 7 frames (3 discovery + 3 observed + 1 notify)' ($t -match 'received frames\s*:\s*7\s*\(processed 6, rejected 1\)')
Check 'agent processed 6 (3 discovery + 3 observed)' ($t -match 'processed 6')
Check 'agent rejected 1 (oversize notify)' ($t -match 'rejected 1')
Check 'agent oversize notify 1' ($t -match 'oversize notify\s*:\s*1 frame')

# ---- layered reconciliation across hook and agent ----
$hookSentLine = ($selftestOut -join "`n")
# hook_selftest asserts sent==3, observedFrames==3 internally; cross-check with agent:
# 3 discovery + 3 observed = 6 processed on the agent side; notify = 1 rejected.
Check 'hook sent(3) + observed(3) == agent processed(6)' (
    ($hookSentLine -match 'PASS sent == 3') -and
    ($hookSentLine -match 'PASS observedFrames == 3') -and
    ($t -match 'processed 6'))
Check 'hook sentNotify(1) == agent rejected(1)' (
    ($hookSentLine -match 'PASS sentNotify == 1') -and ($t -match 'rejected 1'))

# ---- data-plane D4 single-probe rule (agent side) ----
Check 'datapath: bind ip 127.0.0.1' ($t -match 'bind ip\s*:\s*127\.0\.0\.1')
Check 'datapath: frames seen 3 (the three OBSERVED frames)' ($t -match 'frames seen\s*:\s*3')
Check 'datapath: frames on 62056 2' ($t -match 'frames on 62056\s*:\s*2')
Check 'datapath: reply sent 1 (D4, at most ONE)' ($t -match 'reply sent\s*:\s*1')
Check 'datapath: no_endpoint 0' ($t -match 'no_endpoint=0')
Check 'datapath: not_local 2 (unbound-socket frames)' ($t -match 'not_local=2')
Check 'datapath: already_sent 0 (no second local frame)' ($t -match 'already_sent=0')
Check 'datapath: send fail 0' ($t -match 'send fail\s*:\s*0')
Check 'datapath: reply bytes 20' ($t -match 'reply bytes\s*:\s*20')
Check 'datapath: mode LOOPBACK SELF-TEST' ($t -match 'mode\s*:\s*LOOPBACK SELF-TEST')

# ---- the agent never binds :62056 (codex D2 §2.2) ----
Check 'agent never binds 62056 (D2, summary note)' ($t -match 'agent never binds :62056')

Write-Host ""
if ($fail -eq 0) {
    Write-Host "F2-MECHANICAL-SELFTEST: PASS (all checks, evidence in $outDir)"
    exit 0
} else {
    Write-Host "F2-MECHANICAL-SELFTEST: FAIL ($fail check(s)) - evidence in $outDir"
    exit 1
}
