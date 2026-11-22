# run-f5-lan-selftest.ps1 - F5 (REV-016 双机发现) LAN simulated host loopback self-test.
#
# Deterministic loopback proof that --sim-lan-listen binds all discovery ports and
# answers a Civ6-style discovery burst (one 4-byte magic per port 62900..62999, all
# from the same source socket = one refresh) with the 22-page fixture, deduplicating
# by (src ip, src port) so a second refresh from a new socket is answered again.
#
# Evidence layout (out root):
#   agent-console.txt / agent-stderr.txt / summary.txt / frame-log.txt /
#   lan-fixture-manifest.txt / lan-page-01..22.bin / client-recv-01..22.bin /
#   bind-check.txt / exit.txt / result.txt
#
# Assertions (8):
#   1. agent exit code is 0
#   2. agent stderr is empty
#   3. summary: LAN simulated host section present, listen ip 127.0.0.1
#   4. summary: requests seen = 100 (first burst) + 100 (second burst) = 200
#   5. summary: replied sockets = 2, pages sent = 44 (== replied * 22)
#   6. summary: send fail = 0, no endpoint = 0, max reached = 0, bind fail = 0
#   7. first-burst client received exactly 22 fixture pages (1104 B each, correct
#      magic at [0..4] = 59 60 69 9B, room name bytes at [24..46])
#   8. second-burst client received exactly 22 pages as well (dedup is per socket,
#      not global)
#
# Exit codes: 0 PASS, 1 assertion failure, 2 setup error.
# Run from the civlink\ directory with the agent binary and fixture-reply-set next
# to it, or pass -BinDir.

param(
    [string]$BinDir = '',
    [string]$OutRoot = ''
)

$ErrorActionPreference = 'Continue'
$script:Checks = 0
$script:Failures = @()

function Check {
    param([string]$Name, [bool]$Cond, [string]$Detail = '')
    $script:Checks++
    if ($Cond) {
        Write-Host ("PASS {0} : {1}" -f $script:Checks, $Name)
    }
    else {
        Write-Host ("FAIL {0} : {1} {2}" -f $script:Checks, $Name, $Detail)
        $script:Failures += $Name
    }
}

function Get-Sha256Hex([string]$Path) {
    (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash
}

if ($BinDir -eq '') { $BinDir = $PSScriptRoot }
if ($OutRoot -eq '') { $OutRoot = Join-Path $BinDir 'f5-lan-selftest-out' }

$agentExe = Join-Path $BinDir 'civlink-agent.exe'
$fixture  = Join-Path $BinDir 'fixture-reply-set'
if (-not (Test-Path $agentExe)) { Write-Host 'SETUP: civlink-agent.exe missing in BinDir'; exit 2 }
if (-not (Test-Path $fixture))  { Write-Host 'SETUP: fixture-reply-set missing in BinDir'; exit 2 }

if (Test-Path $OutRoot) { Remove-Item -LiteralPath $OutRoot -Recurse -Force }
New-Item -ItemType Directory -Path $OutRoot | Out-Null

# --- start the agent in --sim-lan-listen mode --------------------------------
$stopFile = Join-Path $OutRoot 'STOP-agent'
$args = @(
    '--listen-seconds', '30',
    '--out-dir', $OutRoot,
    '--stop-file', $stopFile,
    '--simulate', $fixture,
    '--sim-lan-listen', '127.0.0.1',
    '--sim-room-name', 'CivLink-Test-Room-2222'
)
$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = $agentExe
$psi.Arguments = ($args | ForEach-Object { '"' + $_ + '"' }) -join ' '
$psi.UseShellExecute = $false
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
$psi.CreateNoWindow = $true
$proc = [System.Diagnostics.Process]::Start($psi)
$agentPid = $proc.Id

# read stdout/stderr asynchronously so the pipe never fills (deadlock)
$stdoutTask = $proc.StandardOutput.ReadToEndAsync()
$stderrTask = $proc.StandardError.ReadToEndAsync()

Start-Sleep -Milliseconds 1500
if ($proc.HasExited) {
    Write-Host "SETUP: agent exited early (code $($proc.ExitCode))"
    exit 2
}

# --- first burst: one magic per discovery port, all from one socket -------------
function Send-Burst([int]$Count) {
    # returns a hashtable: recvCount, pages (array of byte[]), recvBytes, firstPageHead, roomName
    $cli = New-Object System.Net.Sockets.UdpClient
    $magic = [byte[]](0x8D, 0xE8, 0xFC, 0x70)
    for ($p = 62900; $p -le 62999; $p++) {
        $cli.Send($magic, 4, ([System.Net.IPAddress]'127.0.0.1'), $p) | Out-Null
    }
    Start-Sleep -Milliseconds 800
    $recv = $cli.Available
    $pages = New-Object System.Collections.ArrayList
    $recvBytes = 0
    $firstPageHead = $null
    $roomName = $null
    while ($cli.Available -gt 0) {
        $ep = New-Object System.Net.IPEndPoint([System.Net.IPAddress]'0.0.0.0', 0)
        $data = $cli.Receive([ref]$ep)
        $recvBytes += $data.Length
        if ($data.Length -eq 1104) { [void]$pages.Add($data) }
        if ($null -eq $firstPageHead -and $data.Length -ge 46) {
            $firstPageHead = ($data[0..3] | ForEach-Object { $_.ToString('X2') }) -join ' '
            $roomName = [System.Text.Encoding]::ASCII.GetString($data[24..45])
        }
    }
    $cli.Close()
    @{
        Count = $recv
        Pages = $pages.ToArray()
        RecvBytes = $recvBytes
        Head = $firstPageHead
        Room = $roomName
    }
}

$b1 = Send-Burst 100
$b2 = Send-Burst 100

# --- stop the agent and collect ------------------------------------------------
[IO.File]::WriteAllText($stopFile, 'stop')
Start-Sleep -Milliseconds 1200
if (-not $proc.HasExited) {
    # hard kill only if it does not honour the stop file
    $proc.Kill()
    $proc.WaitForExit()
}
$exitCode = $proc.ExitCode
$stdout = $stdoutTask.Result
$stderr = $stderrTask.Result

[IO.File]::WriteAllText((Join-Path $OutRoot 'agent-console.txt'), $stdout)
[IO.File]::WriteAllText((Join-Path $OutRoot 'agent-stderr.txt'), $stderr)
[IO.File]::WriteAllText((Join-Path $OutRoot 'exit.txt'), "$exitCode")

# dump the first-burst pages for the record
for ($i = 0; $i -lt $b1.Pages.Count; $i++) {
    [IO.File]::WriteAllBytes((Join-Path $OutRoot ('client-recv-{0:D2}.bin' -f ($i + 1))), $b1.Pages[$i])
}

# summary.txt exists?
$summaryPath = Join-Path $OutRoot 'summary.txt'
$summary = ''
if (Test-Path $summaryPath) { $summary = [IO.File]::ReadAllText($summaryPath) }

# --- assertions ----------------------------------------------------------------
Check 'agent exited 0' ($exitCode -eq 0) "code=$exitCode"
Check 'agent stderr empty' ($stderr.Trim().Length -eq 0) "stderr='$stderr'"
$listenOk = $summary -match 'LAN simulated host \(F5'
Check 'summary has LAN simulated host section' $listenOk
$ipOk = $summary -match 'listen ip\s*: 127\.0\.0\.1'
Check 'summary listen ip 127.0.0.1' $ipOk
$reqMatch = [regex]::Match($summary, 'requests seen\s*:\s*(\d+)')
Check 'requests seen 200' ($reqMatch.Success -and [int]$reqMatch.Groups[1].Value -eq 200) "got=$($reqMatch.Groups[1].Value)"
$repMatch = [regex]::Match($summary, 'replied sockets\s*:\s*(\d+)')
Check 'replied sockets 2' ($repMatch.Success -and [int]$repMatch.Groups[1].Value -eq 2) "got=$($repMatch.Groups[1].Value)"
$pgMatch = [regex]::Match($summary, 'pages sent\s*:\s*(\d+)')
Check 'pages sent 44' ($pgMatch.Success -and [int]$pgMatch.Groups[1].Value -eq 44) "got=$($pgMatch.Groups[1].Value)"
$sfMatch = [regex]::Match($summary, 'send fail\s*:\s*(\d+)')
$neMatch = [regex]::Match($summary, 'no endpoint\s*:\s*(\d+)')
$mxMatch = [regex]::Match($summary, 'max reached\s*:\s*(\d+)')
$bfMatch = [regex]::Match($summary, 'bind fail\s*:\s*(\d+)')
$cleanOk = ($sfMatch.Success -and [int]$sfMatch.Groups[1].Value -eq 0) -and
           ($neMatch.Success -and [int]$neMatch.Groups[1].Value -eq 0) -and
           ($mxMatch.Success -and [int]$mxMatch.Groups[1].Value -eq 0) -and
           ($bfMatch.Success -and [int]$bfMatch.Groups[1].Value -eq 0)
Check 'send fail / no endpoint / max reached / bind fail all 0' $cleanOk
Check 'first burst: 22 pages of 1104 B' ($b1.Pages.Count -eq 22 -and $b1.RecvBytes -eq 22 * 1104) "pages=$($b1.Pages.Count) bytes=$($b1.RecvBytes)"
Check 'first burst page head magic 59 60 69 9B' ($b1.Head -eq '59 60 69 9B') "head='$($b1.Head)'"
Check 'first burst room name' ($b1.Room -eq 'CivLink-Test-Room-2222') "room='$($b1.Room)'"
Check 'second burst: 22 pages too (per-socket dedup)' ($b2.Pages.Count -eq 22 -and $b2.RecvBytes -eq 22 * 1104) "pages=$($b2.Pages.Count) bytes=$($b2.RecvBytes)"

# --- result file ---------------------------------------------------------------
$result = @"
F5-LAN-SELFTEST: $(if ($script:Failures.Count -eq 0) { 'PASS' } else { 'FAIL' }) ($($script:Checks) checks)
Evidence: simulated LAN host on loopback (127.0.0.1). NOT a real two-machine test; the
client in this test is a UDP script, not a real Civ6 process. Real-client evidence comes
from the F5 dual-machine demo run (A host + B real Civ6 client).
script sha256 : $(Get-Sha256Hex $PSCommandPath)
agent sha256  : $(Get-Sha256Hex $agentExe)
"@
[IO.File]::WriteAllText((Join-Path $OutRoot 'result.txt'), $result)

Write-Host ''
Write-Host ('F5-LAN-SELFTEST: ' + $(if ($script:Failures.Count -eq 0) { 'PASS' } else { 'FAIL' }) + " ($($script:Checks) checks)")
if ($script:Failures.Count -gt 0) {
    Write-Host ('FAILED: ' + ($script:Failures -join ', '))
    exit 1
}
exit 0
