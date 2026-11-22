# run-c1-reserve-selftest.ps1 - M0-C C1 (v0.4.6) --reserve-62900 loopback self-test.
#
# Deterministic loopback proof that --reserve-62900 leaves 62900 free for the game's
# LAN-host socket while the Agent still answers Civ6-style discovery:
#   1. while the Agent runs with --reserve-62900, the test can ITSELF bind 127.0.0.1:62900
#      (this is exactly what the game's LAN-host socket does - the historical
#      "cannot create room" failure mode would make this bind fail with WSAEADDRINUSE)
#   2. the Agent binds the other 99 ports (62901..62999) and answers one 22-page burst
#      from the fallback reply source (127.0.0.1:62901), deduplicating by (src ip, src port)
#   3. summary records `port 62900 : reserved, not bound`, bind fail = 0,
#      reply source = 127.0.0.1:62901
#
# Evidence layout (out root):
#   agent-console.txt / agent-stderr.txt / summary.txt / frame-log.txt /
#   lan-fixture-manifest.txt / lan-page-01..22.bin / client-recv-01..22.bin /
#   port-62900-bind-check.txt / exit.txt / result.txt
#
# Assertions (12):
#   1. agent exit code is 0
#   2. agent stderr contains the reserve notice line but no other diagnostics
#   3. summary: LAN simulated host section present, listen ip 127.0.0.1
#   4. summary: `port 62900 : reserved, not bound`
#   5. summary: requests seen = 99 (62900 datagram is dropped - no listener, game slot)
#   6. summary: replied sockets = 1, pages sent = 22 (== replied * 22)
#   7. summary: reply source = 127.0.0.1:62901 (fallback port, NOT 62900)
#   8. summary: send fail / no endpoint / max reached / bind fail all 0
#   9. the test's own bind of 127.0.0.1:62900 while the Agent runs SUCCEEDS
#      (game slot free -> room creation is never blocked)
#   10. client received exactly 22 fixture pages (1104 B each, magic 59 60 69 9B at
#       [0..4], room name bytes at [24..46])
#
# Exit codes: 0 PASS, 1 assertion failure, 2 setup error.

param(
    [string]$BinDir = '',
    [string]$OutRoot = ''
)

$ErrorActionPreference = 'Continue'
$script:Checks = 0
$script:Failures = @()

function Check {
    param([string]$Name, $Cond, [string]$Detail = '')
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
if ($OutRoot -eq '') { $OutRoot = Join-Path $BinDir 'c1-reserve-selftest-out' }

$agentExe = Join-Path $BinDir 'civlink-agent.exe'
$fixture  = Join-Path $BinDir 'fixture-reply-set'
if (-not (Test-Path $agentExe)) { Write-Host 'SETUP: civlink-agent.exe missing in BinDir'; exit 2 }
if (-not (Test-Path $fixture))  { Write-Host 'SETUP: fixture-reply-set missing in BinDir'; exit 2 }

# clean up any stale agent from a previous crashed run (holds the discovery ports)
Get-Process -Name 'civlink-agent' -ErrorAction SilentlyContinue | Stop-Process -Force

if (Test-Path $OutRoot) { Remove-Item -LiteralPath $OutRoot -Recurse -Force }
New-Item -ItemType Directory -Path $OutRoot | Out-Null

# --- start the agent with --reserve-62900 --------------------------------------
$stopFile = Join-Path $OutRoot 'STOP-agent'
$args = @(
    '--listen-seconds', '30',
    '--out-dir', $OutRoot,
    '--stop-file', $stopFile,
    '--simulate', $fixture,
    '--sim-lan-listen', '127.0.0.1',
    '--sim-room-name', 'CivLink-Test-Room-2222',
    '--reserve-62900'
)
$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = $agentExe
$psi.Arguments = ($args | ForEach-Object { '"' + $_ + '"' }) -join ' '
$psi.UseShellExecute = $false
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
$psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
$psi.StandardErrorEncoding = [System.Text.Encoding]::UTF8
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

# --- discovery burst: one magic per port, all from one socket -------------------
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
# The burst includes one datagram to 127.0.0.1:62900. When a REAL Civilization VI is
# running on this machine it owns that port, answers the datagram itself, and its 22
# pages arrive on this same socket. Those pages are not the Agent's and must not be
# counted as such - the original script assumed "no game is running", which is false
# whenever the owner has a room open (audit: C1 evidence showed pages=44 = 22 game +
# 22 Agent).
$foreignPages = 0
while ($cli.Available -gt 0) {
    $ep = New-Object System.Net.IPEndPoint([System.Net.IPAddress]'0.0.0.0', 0)
    try {
        $data = $cli.Receive([ref]$ep)
    }
    catch {
        # Windows surfaces an ICMP port-unreachable (WSAECONNRESET 10054) on the
        # client socket: the burst includes one datagram to 127.0.0.1:62900, which
        # the test's probe socket bound and closed before the burst. Not an agent
        # defect - skip it and drain what is still queued.
        # (audit S-1: .NET may surface the code on either exception level)
        $errCode = $null
        if ($_.Exception -and $_.Exception.ErrorCode) { $errCode = $_.Exception.ErrorCode }
        elseif ($_.Exception.InnerException -and $_.Exception.InnerException.ErrorCode) { $errCode = $_.Exception.InnerException.ErrorCode }
        if ($errCode -eq 10054) { continue }
        throw
    }
    if ($ep.Port -ne 62901) {
        # Some other local process (normally the real game on 62900) answered.
        if ($data.Length -eq 1104) { $foreignPages++ }
        continue
    }
    $recvBytes += $data.Length
    if ($data.Length -eq 1104) { [void]$pages.Add($data) }
    if ($null -eq $firstPageHead -and $data.Length -ge 46) {
        $firstPageHead = ($data[0..3] | ForEach-Object { $_.ToString('X2') }) -join ' '
        $roomName = [System.Text.Encoding]::ASCII.GetString($data[24..45])
    }
}
$cli.Close()

# --- C1 core assertion: the game slot (62900) must be bindable while the Agent runs
# This is exactly what Civ6's LAN-host socket does when the owner creates/re-creates a
# room. Before C1 (Agent holding all 100 ports) this bind failed with WSAEADDRINUSE and
# room creation hung (RUNBOOK step-2 ordering bug, m25442).
# Placed AFTER the burst (audit S-7): the burst has already proven the Agent is up and
# serving (requests seen=99), so a probe success cannot be a slow-start false positive.
$bindCheck = ''
$bindSucceeded = $false
try {
    $probe = New-Object System.Net.Sockets.UdpClient
    $probe.Client.Bind([System.Net.IPEndPoint]::new([System.Net.IPAddress]'127.0.0.1', 62900))
    $bindSucceeded = $true
    $bindCheck = "bind 127.0.0.1:62900 SUCCEEDED (port left free by --reserve-62900)"
    $probe.Close()
}
catch {
    $bindCheck = "bind 127.0.0.1:62900 FAILED: $($_.Exception.Message)"
}
[IO.File]::WriteAllText((Join-Path $OutRoot 'port-62900-bind-check.txt'), $bindCheck)

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

# dump the pages for the record
for ($i = 0; $i -lt $pages.Count; $i++) {
    [IO.File]::WriteAllBytes((Join-Path $OutRoot ('client-recv-{0:D2}.bin' -f ($i + 1))), $pages[$i])
}

# summary.txt exists?
$summaryPath = Join-Path $OutRoot 'summary.txt'
$summary = ''
if (Test-Path $summaryPath) { $summary = [IO.File]::ReadAllText($summaryPath) }

# --- assertions ----------------------------------------------------------------
Check 'agent exited 0' ($exitCode -eq 0) "code=$exitCode"
$noticeLines = ($stderr -split "`n" | Where-Object { $_ -match 'reserved for the game host \(--reserve-62900\)' }).Count
$otherLines = ($stderr -split "`n" | Where-Object { $_.Trim() -ne '' -and $_ -notmatch 'reserved for the game host \(--reserve-62900\)' }).Count
$stderrClean = ($noticeLines -eq 1 -and $otherLines -eq 0)
Check 'agent stderr has only the reserve notice' $stderrClean "stderr='$stderr'"
$listenOk = $summary -match 'LAN simulated host \(F5'
Check 'summary has LAN simulated host section' $listenOk
$ipOk = $summary -match 'listen ip\s*: 127\.0\.0\.1'
Check 'summary listen ip 127.0.0.1' $ipOk
$resOk = $summary -match 'port 62900\s*: reserved, not bound'
Check 'summary port 62900 reserved' $resOk
$reqMatch = [regex]::Match($summary, 'requests seen\s*:\s*(\d+)')
Check 'requests seen 99 (62900 slot dropped)' ($reqMatch.Success -and [int]$reqMatch.Groups[1].Value -eq 99) "got=$($reqMatch.Groups[1].Value)"
$repMatch = [regex]::Match($summary, 'replied sockets\s*:\s*(\d+)')
Check 'replied sockets 1' ($repMatch.Success -and [int]$repMatch.Groups[1].Value -eq 1) "got=$($repMatch.Groups[1].Value)"
$pgMatch = [regex]::Match($summary, 'pages sent\s*:\s*(\d+)')
Check 'pages sent 22' ($pgMatch.Success -and [int]$pgMatch.Groups[1].Value -eq 22) "got=$($pgMatch.Groups[1].Value)"
$srcMatch = [regex]::Match($summary, 'reply source\s*:\s*127\.0\.0\.1:62901')
Check 'reply source 127.0.0.1:62901 (fallback, not 62900)' $srcMatch.Success "got=$($summary -split "`n" | Select-String 'reply source')"
$sfMatch = [regex]::Match($summary, 'send fail\s*:\s*(\d+)')
$neMatch = [regex]::Match($summary, 'no endpoint\s*:\s*(\d+)')
$mxMatch = [regex]::Match($summary, 'max reached\s*:\s*(\d+)')
$bfMatch = [regex]::Match($summary, 'bind fail\s*:\s*(\d+)')
$cleanOk = ($sfMatch.Success -and [int]$sfMatch.Groups[1].Value -eq 0) -and
           ($neMatch.Success -and [int]$neMatch.Groups[1].Value -eq 0) -and
           ($mxMatch.Success -and [int]$mxMatch.Groups[1].Value -eq 0) -and
           ($bfMatch.Success -and [int]$bfMatch.Groups[1].Value -eq 0)
Check 'send fail / no endpoint / max reached / bind fail all 0' $cleanOk
Check 'game slot 62900 bindable while Agent runs (room creation never blocked)' $bindSucceeded $bindCheck
Check 'client got 22 pages of 1104 B, magic + room name' ($pages.Count -eq 22 -and $recvBytes -eq 22 * 1104 -and $firstPageHead -eq '59 60 69 9B' -and $roomName -eq 'CivLink-Test-Room-2222') "pages=$($pages.Count) bytes=$recvBytes head='$firstPageHead' room='$roomName' (ignored $foreignPages page(s) from a real game on 62900)"

# --- result file ---------------------------------------------------------------
$result = @"
C1-RESERVE-SELFTEST: $(if ($script:Failures.Count -eq 0) { 'PASS' } else { 'FAIL' }) ($($script:Checks) checks)
Evidence: loopback only (127.0.0.1). NOT a real two-machine test; the client is a UDP
script, not a real Civ6 process. Proves the C1 mechanism: --reserve-62900 leaves the
game's 62900 LAN-host slot free (bindable while the Agent runs -> room (re-)creation is
never blocked) while the Agent still answers discovery from 62901 with the 22-page fixture.
script sha256 : $(Get-Sha256Hex $PSCommandPath)
agent sha256  : $(Get-Sha256Hex $agentExe)
"@
[IO.File]::WriteAllText((Join-Path $OutRoot 'result.txt'), $result)

Write-Host ''
Write-Host ('C1-RESERVE-SELFTEST: ' + $(if ($script:Failures.Count -eq 0) { 'PASS' } else { 'FAIL' }) + " ($($script:Checks) checks)")
if ($script:Failures.Count -gt 0) {
    Write-Host ('FAILED: ' + ($script:Failures -join ', '))
    exit 1
}
exit 0
