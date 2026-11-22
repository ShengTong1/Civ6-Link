# run-f1-sim-selftest.ps1 - CivLink F1 simulated-host mechanical self-test driver
#
# Like run-f1-selftest.ps1 but starts the Agent with --simulate: discovery requests that
# arrive via the Hook chain must be answered with the 22-page fixture, injected over
# loopback. hook_selftest.exe sends five datagrams:
#
#   1. 255.255.255.255:62905 (4 B, unbound socket)   -> deferred (no endpoint), counted
#   2. 127.0.0.1:62907       (4 B, same socket)      -> ONE reply of 22 pages
#   3. 127.0.0.1:50999       (4 B)                   -> not discovery, ignored
#   4. 127.0.0.1:62907       (1400 B)                -> oversize: hook emits a reject frame
#   5. 127.0.0.1:62908       (4 B, new socket)       -> deferred (no endpoint), counted
#
# Expected deterministic outcome:
#   sim: requests_seen=3 replied_sockets=1 pages_sent=22 send_fail=0
#        no_endpoint=2 max_reached=0 bind_fail=0
#   agent: datagrams=4 received=4 (processed 3, rejected 1), notify=1
#
# Everything here is mechanical: no Civ6, no network traffic beyond loopback, no claim about
# the game displaying anything. A PASS means "the simulated host answered a discovery request
# that came through the Hook chain with exactly the 22 fixture pages".
#
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File run-f1-sim-selftest.ps1
#        [-OutRoot <dir>] [-FixtureDir <dir>]
# Exit: 0 all checks passed, 1 a check failed, 2 a tool or precondition is missing.
[CmdletBinding()]
param(
    [string]$OutRoot = '',
    [string]$FixtureDir = ''
)
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$agent = Join-Path $here 'civlink-agent.exe'
$selftest = Join-Path $here 'hook_selftest.exe'
$dll = Join-Path $here 'civlink_hook.dll'

$fail = 0
function Check($what, $ok, $detail) {
    if ($ok) { Write-Host ("  PASS {0,-56} {1}" -f $what, $detail) }
    else { Write-Host ("  FAIL {0,-56} {1}" -f $what, $detail); $script:fail++ }
}

Write-Host "CivLink F1 simulated-host self-test"
foreach ($f in @($agent, $selftest, $dll)) {
    if (-not (Test-Path $f)) { Write-Host "[!] missing $f - run build-msvc.cmd first"; exit 2 }
}

# Fixture: the 22 reply pages captured in H4/E2-A. Default resolves from the repo layout.
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
if (-not (Test-Path $captures)) { New-Item -ItemType Directory -Force -Path $captures | Out-Null }
$outDir = Join-Path $captures "F1-sim-selftest-$stamp"
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
Write-Host "[*] evidence dir: $outDir"
Write-Host "[*] fixture dir:  $FixtureDir"

# The IPC port must be free; a leftover Agent would silently steal the frames.
$busy = Get-NetUDPEndpoint -LocalPort 34718 -ErrorAction SilentlyContinue
if ($busy) {
    Write-Host "[!] 127.0.0.1:34718 is already in use by pid=$($busy.OwningProcess) - stop it first"
    exit 2
}
# The simulated-host reply socket must be able to bind 127.0.0.1:62900. IPv6-only wildcard
# holders on ::1 do not conflict; an IPv4 wildcard (0.0.0.0) would make the bind fail and
# the agent would still run with replies disabled - that shows up as bind_fail=1 below.
$holder = Get-NetUDPEndpoint -LocalPort 62900 -ErrorAction SilentlyContinue |
    Where-Object { $_.LocalAddress -in @('0.0.0.0', '127.0.0.1') }
if ($holder) {
    Write-Host "[!] 127.0.0.1:62900 is already in use by pid=$($holder.OwningProcess) - the simulated host cannot bind its reply socket"
    exit 2
}

Write-Host "[*] starting agent with --simulate (25 s window, budget 20)"
$log = Join-Path $outDir 'agent-console.txt'
$agentProc = Start-Process -FilePath $agent -ArgumentList @(
    '--listen-seconds', '25', '--out-dir', $outDir,
    '--simulate', $FixtureDir, '--sim-max-replies', '20',
    '--sim-src-ip', '127.0.0.1', '--quiet'
) -PassThru -WindowStyle Hidden -RedirectStandardOutput $log
Start-Sleep -Milliseconds 1200
if ($agentProc.HasExited) {
    Write-Host "[!] agent exited immediately (code $($agentProc.ExitCode)); see $log"
    Get-Content $log -ErrorAction SilentlyContinue | ForEach-Object { Write-Host "    $_" }
    exit 2
}
Write-Host "[*] agent pid=$($agentProc.Id)"

Write-Host "[*] running hook_selftest.exe"
$hookLog = Join-Path $outDir 'hook-selftest.txt'
$hookProc = Start-Process -FilePath $selftest -PassThru -WindowStyle Hidden `
    -RedirectStandardOutput $hookLog -Wait
$hookExit = $hookProc.ExitCode
Get-Content $hookLog | ForEach-Object { Write-Host "    $_" }
Check "hook_selftest.exe exit code 0" ($hookExit -eq 0) "exit=$hookExit"

Write-Host "[*] waiting for agent to finish its window"
if (-not $agentProc.WaitForExit(30000)) {
    Write-Host "[!] agent did not exit in time - stopping it"
    Stop-Process -Id $agentProc.Id -Force
    $fail++
}

$summaryPath = Join-Path $outDir 'summary.txt'
if (-not (Test-Path $summaryPath)) {
    Write-Host "[!] agent wrote no summary.txt"
    Get-Content $log -ErrorAction SilentlyContinue | ForEach-Object { Write-Host "    $_" }
    exit 1
}
$summary = Get-Content $summaryPath
$text = $summary -join "`n"
Write-Host "--- agent summary ---"
$summary | ForEach-Object { Write-Host "    $_" }

function Grab($pattern) {
    $m = [regex]::Match($text, $pattern)
    if ($m.Success) { return [int64]$m.Groups[1].Value }
    return $null
}
$agentProcessed = Grab 'processed (\d+), rejected'
$agentRejected = Grab 'rejected (\d+)\)'
$agentReceived = Grab 'received frames : (\d+)'
$agentNotify = Grab 'oversize notify : (\d+)'
$simRequests = Grab 'requests seen   : (\d+)'
$simReplied = Grab 'replied sockets : (\d+)'
$simPages = Grab 'pages sent      : (\d+)'
$simSendFail = Grab 'send fail       : (\d+)'
$simNoEndpoint = Grab 'no endpoint     : (\d+)'
$simMaxReached = Grab 'max reached     : (\d+)'
$simBindFail = Grab 'bind fail       : (\d+)'

Check "agent received 4 frames (3 discovery + 1 notify)" ($agentReceived -eq 4) "received=$agentReceived"
Check "agent processed 3, rejected 1" ($agentProcessed -eq 3 -and $agentRejected -eq 1) "processed=$agentProcessed rejected=$agentRejected"
Check "agent notify frames == 1" ($agentNotify -eq 1) "notify=$agentNotify"
Check "sim requests seen == 3" ($simRequests -eq 3) "seen=$simRequests"
Check "sim replied exactly 1 socket" ($simReplied -eq 1) "replied=$simReplied"
Check "sim sent 22 pages (1 socket x 22)" ($simPages -eq 22) "pages=$simPages"
Check "sim send fail == 0" ($simSendFail -eq 0) "fail=$simSendFail"
Check "sim no endpoint == 2 (both unbound first frames)" ($simNoEndpoint -eq 2) "no_endpoint=$simNoEndpoint"
Check "sim max reached == 0" ($simMaxReached -eq 0) "max=$simMaxReached"
Check "sim bind fail == 0 (reply socket bound 127.0.0.1:62900)" ($simBindFail -eq 0) "bind_fail=$simBindFail"
Check "processed + rejected == received" (($agentProcessed + $agentRejected) -eq $agentReceived) ""

# The anonymized fixture pages the agent actually sent must be on disk, 22 x 1104 B.
$simPagesOk = $true
for ($i = 1; $i -le 22; $i++) {
    $p = Join-Path $outDir ('sim-page-{0:D2}.bin' -f $i)
    if (-not (Test-Path $p) -or (Get-Item $p).Length -ne 1104) { $simPagesOk = $false }
}
Check "sim-page-01..22.bin written, 22 x 1104 B" $simPagesOk ""
Check "sim-fixture-manifest.txt written" (Test-Path (Join-Path $outDir 'sim-fixture-manifest.txt')) ""

Write-Host ""
if ($fail -eq 0) {
    Write-Host "F1-SIM-SELFTEST: PASS (simulated host answered through the Hook chain; mechanical evidence only)"
    Write-Host "[*] evidence: $outDir"
    exit 0
} else {
    Write-Host "F1-SIM-SELFTEST: FAIL ($fail failed check(s))"
    Write-Host "[*] evidence: $outDir"
    exit 1
}
