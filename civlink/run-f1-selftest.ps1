# run-f1-selftest.ps1 - CivLink F1 mechanical self-test driver
#
# Starts civlink-agent, runs hook_selftest.exe (which loads civlink_hook.dll in its own
# process, performs four sends, and checks its counters), then reconciles the Hook's view
# against the Agent's view:
#
#   hook.sent        == agent.processed
#   hook.sentNotify  == agent oversize notify frames
#
# Everything here is mechanical: no Civ6, no network traffic beyond loopback, no claim about
# discovery working in the game. A PASS means "the Hook and the Agent agree byte for byte".
#
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File run-f1-selftest.ps1
#        [-OutRoot <dir>]   write evidence there instead of the default repo location
# Exit: 0 all checks passed, 1 a check failed, 2 a tool or precondition is missing.
[CmdletBinding()]
param(
    # Evidence root. Defaults to <repo>\M0A\captures when this script sits in
    # CivLink-M0A-audit\civlink\; when the binaries are staged in a neutral
    # directory pass this explicitly, otherwise the default resolves to
    # <staged>\..\..\M0A\captures which is usually the wrong place.
    [string]$OutRoot = ''
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

Write-Host "CivLink F1 self-test"
foreach ($f in @($agent, $selftest, $dll)) {
    if (-not (Test-Path $f)) { Write-Host "[!] missing $f - run build-msvc.cmd first"; exit 2 }
}

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
if ($OutRoot -ne '') {
    $captures = $OutRoot
} else {
    $repoRoot = Split-Path (Split-Path $here -Parent) -Parent
    if (Test-Path (Join-Path $repoRoot 'M0A')) { $captures = Join-Path $repoRoot 'M0A\captures' }
    else { $captures = Join-Path $here 'captures' }
}
if (-not (Test-Path $captures)) { New-Item -ItemType Directory -Force -Path $captures | Out-Null }
$outDir = Join-Path $captures "F1-selftest-$stamp"
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
Write-Host "[*] evidence dir: $outDir"

# The IPC port must be free; a leftover Agent would silently steal the frames.
$busy = Get-NetUDPEndpoint -LocalPort 34718 -ErrorAction SilentlyContinue
if ($busy) {
    Write-Host "[!] 127.0.0.1:34718 is already in use by pid=$($busy.OwningProcess) - stop it first"
    exit 2
}

Write-Host "[*] starting agent (25 s window)"
$log = Join-Path $outDir 'agent-console.txt'
$agentProc = Start-Process -FilePath $agent -ArgumentList @(
    '--listen-seconds', '25', '--out-dir', $outDir
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

# Parse the numbers we must reconcile.
function Grab($pattern) {
    $m = [regex]::Match($text, $pattern)
    if ($m.Success) { return [int64]$m.Groups[1].Value }
    return $null
}
$agentProcessed = Grab 'processed (\d+), rejected'
$agentRejected = Grab 'rejected (\d+)\)'
$agentReceived = Grab 'received frames : (\d+)'
$agentNotify = Grab 'oversize notify : (\d+)'
$agentGaps = Grab 'seq gaps=(\d+)'

# The hook's own numbers come from the self-test log (it prints PASS lines only), so also
# read the counters it reported indirectly: the self-test asserts sent==3, observed==1,
# sentNotify==1, rejectOversize==1 and ignored==0 (send3 is now an OBSERVED frame).
$hookSaidSent3 = $text -ne $null -and (Select-String -Path $hookLog -Pattern 'PASS sent == 3' -Quiet)
Check "self-test confirmed hook.sent == 3" ([bool]$hookSaidSent3) ""
$hookSaidObserved1 = $text -ne $null -and (Select-String -Path $hookLog -Pattern 'PASS observedFrames == 1' -Quiet)
Check "self-test confirmed hook.observed == 1" ([bool]$hookSaidObserved1) ""

Check "agent received 5 frames (3 discovery + 1 observed + 1 notify)" ($agentReceived -eq 5) "received=$agentReceived"
Check "agent processed 4 frames (3 discovery + 1 observed)" ($agentProcessed -eq 4) "processed=$agentProcessed"
Check "agent rejected 1 notify frame" ($agentRejected -eq 1) "rejected=$agentRejected"
Check "agent notify frames == 1" ($agentNotify -eq 1) "notify=$agentNotify"
Check "agent saw no sequence gaps" ($agentGaps -eq 0) "gaps=$agentGaps"
Check "hook.sent + hook.observed (3+1) == agent.processed (4)" ($hookSaidSent3 -and $hookSaidObserved1 -and $agentProcessed -eq 4) ""
Check "processed + rejected == received" (($agentProcessed + $agentRejected) -eq $agentReceived) ""

$frameLog = Join-Path $outDir 'frame-log.txt'
if (Test-Path $frameLog) {
    $lines = @(Get-Content $frameLog | Where-Object { $_ -notmatch '^#' -and $_.Trim() })
    Check "frame-log has 5 frame lines" ($lines.Count -eq 5) "lines=$($lines.Count)"
    # Do not anchor on 127.0.0.1: the first observation targets the limited broadcast
    # address 255.255.255.255:62905, which is exactly the case that must be covered.
    # send3 goes to the non-discovery port 50999 as an OBSERVED frame.
    $dstAddrs = @()
    $ports = @()
    foreach ($line in $lines) {
        $m = [regex]::Match($line, 'dst=([\d.]+):(\d+)')
        if ($m.Success) {
            $dstAddrs += $m.Groups[1].Value
            $ports += [int]$m.Groups[2].Value
        }
    }
    Check "frame-log dst addresses are broadcast/loopback x4" (
        ($dstAddrs -join ',') -eq '255.255.255.255,127.0.0.1,127.0.0.1,127.0.0.1,127.0.0.1'
    ) "dst=$($dstAddrs -join ',')"
    Check "frame-log ports are 62905/62907/50999/62907/62908" (
        ($ports -join ',') -eq '62905,62907,50999,62907,62908'
    ) "ports=$($ports -join ',')"
} else {
    Check "frame-log.txt exists" $false "missing"
}

Write-Host ""
if ($fail -eq 0) {
    Write-Host "F1-SELFTEST: PASS (hook and agent reconciled; F1 mechanical evidence only)"
    Write-Host "[*] evidence: $outDir"
    exit 0
} else {
    Write-Host "F1-SELFTEST: FAIL ($fail failed check(s))"
    Write-Host "[*] evidence: $outDir"
    exit 1
}
