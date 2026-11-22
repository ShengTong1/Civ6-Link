# run-f5-dualmachine-a.ps1 - F5 dual-machine verification, PC-A side (the simulated host).
#
# Coordinates the one-shot cross-machine discovery proof:
#   1. starts civlink-agent.exe --sim-lan-listen 0.0.0.0 (LAN simulated host, all
#      discovery ports 62900..62999, room 'CivLink-Test-Room-2222')
#   2. waits up to -WaitSeconds for the operator to run run-f5-b-probe.ps1 on PC-B
#      (or to click Refresh in Civ6 LAN lobby on PC-B)
#   3. stops the agent cleanly, then asserts on the summary:
#        - requests seen > 0                 (PC-B's broadcast reached PC-A)
#        - replied sockets >= 1              (the host answered a client)
#        - pages sent == replied * 22        (the full fixture went out)
#        - send fail == 0 / no endpoint == 0 / max reached == 0 / bind fail == 0
#   4. writes F5-DUALMACHINE-A: PASS/FAIL + result.txt + evidence
#
# Usage (on PC-A, elevated not required - the agent has a firewall Allow rule):
#   powershell.exe -NoProfile -ExecutionPolicy Bypass -File run-f5-dualmachine-a.ps1
#     [-BinDir DIR]           civlink binaries + fixture dir (default: script dir)
#     [-OutRoot DIR]          evidence dir (default: Desktop\civlink-f5-a-out)
#     [-WaitSeconds 180]      how long to wait for PC-B to probe
#     [-ListenSeconds 240]    agent window (must exceed WaitSeconds)
#     [-RoomName NAME]        default CivLink-Test-Room-2222
#
# Exit codes: 0 PASS, 1 assertion failure, 2 setup error.

param(
    [string]$BinDir = '',
    [string]$OutRoot = '',
    [int]$WaitSeconds = 180,
    [int]$ListenSeconds = 240,
    [string]$RoomName = 'CivLink-Test-Room-2222'
)

$ErrorActionPreference = 'Continue'
$script:Checks = 0
$script:Failures = @()
function Check {
    param([string]$Name, [bool]$Cond, [string]$Detail = '')
    $script:Checks++
    if ($Cond) { Write-Host ("PASS {0} : {1}" -f $script:Checks, $Name) }
    else { Write-Host ("FAIL {0} : {1} {2}" -f $script:Checks, $Name, $Detail); $script:Failures += $Name }
}
function Get-Sha256Hex([string]$Path) { (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash }

if ($BinDir -eq '') { $BinDir = $PSScriptRoot }
if ($OutRoot -eq '') { $OutRoot = Join-Path ([Environment]::GetFolderPath('Desktop')) 'civlink-f5-a-out' }

$agentExe = Join-Path $BinDir 'civlink-agent.exe'
$fixture  = Join-Path $BinDir 'fixture-reply-set'
if (-not (Test-Path $agentExe)) { Write-Host 'SETUP: civlink-agent.exe missing in BinDir'; exit 2 }
if (-not (Test-Path $fixture))  { Write-Host 'SETUP: fixture-reply-set missing in BinDir'; exit 2 }

if (Test-Path $OutRoot) { Remove-Item -LiteralPath $OutRoot -Recurse -Force }
New-Item -ItemType Directory -Path $OutRoot | Out-Null
$stop = Join-Path $OutRoot 'STOP-agent'

# pre-check: no other agent running, ports free
Get-Process civlink-agent -ErrorAction SilentlyContinue | ForEach-Object {
    Write-Host "SETUP: civlink-agent already running (PID $($_.Id)) - stop it first"; exit 2
}
$busy = Get-NetUDPEndpoint -ErrorAction SilentlyContinue | Where-Object { $_.LocalPort -ge 62900 -and $_.LocalPort -le 62999 }
if ($busy) {
    Write-Host "SETUP: ports 62900..62999 busy: $($busy.LocalPort -join ',')"
    exit 2
}

# start the LAN simulated host
$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = $agentExe
$psi.Arguments = "--listen-seconds $ListenSeconds --out-dir `"$OutRoot`" --stop-file `"$stop`" --simulate `"$fixture`" --sim-lan-listen 0.0.0.0 --sim-room-name `"$RoomName`""
$psi.UseShellExecute = $false
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
$psi.CreateNoWindow = $true
$proc = [System.Diagnostics.Process]::Start($psi)
$so = $proc.StandardOutput.ReadToEndAsync()
$se = $proc.StandardError.ReadToEndAsync()
Start-Sleep -Seconds 2
if ($proc.HasExited) {
    Write-Host "SETUP: agent exited early (code $($proc.ExitCode)) - stderr: $($se.Result)"
    exit 2
}
$bound = (Get-NetUDPEndpoint -ErrorAction SilentlyContinue | Where-Object { $_.LocalPort -ge 62900 -and $_.LocalPort -le 62999 }).Count
Write-Host "READY: LAN simulated host up (PID $($proc.Id)), $bound/100 discovery ports bound, room '$RoomName'."
Write-Host "NOW on PC-B: run run-f5-b-probe.ps1 (or click Refresh in the Civ6 LAN lobby)."
Write-Host "Waiting up to ${WaitSeconds}s for PC-B..."

# NOTE (F5 audit D4): the agent writes summary.txt only at window end (listen-seconds
# expiry or stop-file), so polling for summary.txt mid-window can never fire early.
# We therefore wait a fixed -WaitSeconds for PC-B to probe, then stop the agent.
$deadline = (Get-Date).AddSeconds($WaitSeconds)
Write-Host "Waiting ${WaitSeconds}s for PC-B (fixed wait - agent writes summary only at window end)..."
while ((Get-Date) -lt $deadline) {
    Start-Sleep -Seconds 3
    if ($proc.HasExited) { break }
}

# stop the agent cleanly
[IO.File]::WriteAllText($stop, 'stop')
Start-Sleep -Seconds 2
if (-not $proc.HasExited) { $proc.Kill(); $proc.WaitForExit() }
$agentExit = $proc.ExitCode
[IO.File]::WriteAllText((Join-Path $OutRoot 'agent-console.txt'), $so.Result)
[IO.File]::WriteAllText((Join-Path $OutRoot 'agent-stderr.txt'), $se.Result)
[IO.File]::WriteAllText((Join-Path $OutRoot 'exit.txt'), "$agentExit")

$summaryPath = Join-Path $OutRoot 'summary.txt'
$summary = ''
if (Test-Path $summaryPath) { $summary = [IO.File]::ReadAllText($summaryPath) }

# ---- assertions -----------------------------------------------------------------
Check 'agent exited 0' ($agentExit -eq 0) "code=$agentExit"
Check 'agent stderr empty' ($se.Result.Trim().Length -eq 0) "stderr='$($se.Result)'"

$req = [regex]::Match($summary, 'requests seen\s*:\s*(\d+)')
Check 'requests seen > 0 (PC-B broadcast reached PC-A)' ($req.Success -and [int]$req.Groups[1].Value -gt 0) "got=$($req.Groups[1].Value)"

$rep = [regex]::Match($summary, 'replied sockets\s*:\s*(\d+)')
Check 'replied sockets >= 1 (host answered a client)' ($rep.Success -and [int]$rep.Groups[1].Value -ge 1) "got=$($rep.Groups[1].Value)"

$pg = [regex]::Match($summary, 'pages sent\s*:\s*(\d+)')
$replied = if ($rep.Success) { [int]$rep.Groups[1].Value } else { -1 }
Check 'pages sent == replied * 22 (full fixture out)' ($pg.Success -and [int]$pg.Groups[1].Value -eq $replied * 22) "got=$($pg.Groups[1].Value) replied=$replied"

$sf = [regex]::Match($summary, 'send fail\s*:\s*(\d+)')
$ne = [regex]::Match($summary, 'no endpoint\s*:\s*(\d+)')
$mx = [regex]::Match($summary, 'max reached\s*:\s*(\d+)')
$bf = [regex]::Match($summary, 'bind fail\s*:\s*(\d+)')
$cleanOk = ($sf.Success -and [int]$sf.Groups[1].Value -eq 0) -and
           ($ne.Success -and [int]$ne.Groups[1].Value -eq 0) -and
           ($mx.Success -and [int]$mx.Groups[1].Value -eq 0) -and
           ($bf.Success -and [int]$bf.Groups[1].Value -eq 0)
Check 'send fail / no endpoint / max reached / bind fail all 0' $cleanOk

# ---- result ---------------------------------------------------------------------
$stamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
$result = @"
F5-DUALMACHINE-A: $(if ($script:Failures.Count -eq 0) { 'PASS' } else { 'FAIL' }) ($($script:Checks) checks)
time        : $stamp
agent pid   : $($proc.Id)
room        : $RoomName
waited      : $WaitSeconds s
agent exit  : $agentExit
summary key : $req / $rep / $pg (requests / replied sockets / pages sent)
Evidence: PC-A simulated host answered a cross-machine discovery broadcast from PC-B.
Simulated-host evidence only - a real Civ6 client on PC-B showing the room is the
real-client confirmation. NOT a two-real-hosts multiplayer result, NOT E2-B/E3.
script sha256: $(Get-Sha256Hex $PSCommandPath)
agent sha256 : $(Get-Sha256Hex $agentExe)
"@
[IO.File]::WriteAllText((Join-Path $OutRoot 'result.txt'), $result)

Write-Host ''
Write-Host ('F5-DUALMACHINE-A: ' + $(if ($script:Failures.Count -eq 0) { 'PASS' } else { 'FAIL' }) + " ($($script:Checks) checks)")
if ($script:Failures.Count -gt 0) {
    Write-Host ('FAILED: ' + ($script:Failures -join ', '))
    exit 1
}
exit 0
