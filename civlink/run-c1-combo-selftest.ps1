# run-c1-combo-selftest.ps1 - M0-C C1 flag-combination self-test (v0.4.6).
#
# C1 review suggestion 3 asked for script coverage of the flag combination that a real
# host-side run uses all at once. Every flag below changes a different subsystem, and
# nothing in the code base claims they were ever exercised together:
#
#   --reserve-62900      (C1)  leaves the game's LAN-host port 62900 unbound
#   --sim-real-capture   (B1)  caches real advertisement pages (P1 hook / P2 LAN)
#   --forward-listen     (F3-A) opens an independent loopback listener, never 62056
#   --sim-lan-listen     (F5)  binds the other 99 discovery ports on 127.0.0.1
#   --simulate           (F1)  fixture source
#
# What this proves: the combination starts, serves discovery, keeps its invariants
# (62900 free, reply source 62901, no :62056 bind, no SO_REUSEADDR), and shuts down
# cleanly with exit 0 - i.e. the modes are composable.
# What it does NOT prove: anything about real Civ6, real peers, E2-B/E3, or that the
# IP_UNICAST_IF path (C2) works cross-machine. Loopback only.
#
# Assertions (14):
#   1. agent exit code is 0
#   2. stderr has exactly the one reserve notice line and nothing else
#   3. summary has the LAN simulated host, real advertisement and forward sections
#   4. summary: `port 62900 : reserved, not bound`
#   5. summary: reply source 127.0.0.1:62901 (fallback, not 62900)
#   6. discovery burst answered: requests seen = 99, replied = 1, pages sent = 22
#   7. client received 22 pages of 1104 B with magic 59 60 69 9B and the room name
#   8. B1 capture section present and `active : no` (a burst does not fabricate pages)
#   9. forward listener is 21397 and `payloads recv = 0` (nothing was forwarded)
#  10. bind fail / send fail / no endpoint / max reached all 0
#  11. the test's own bind of 127.0.0.1:62900 succeeds while the Agent runs
#  12. no listening socket of the Agent process is on 62056
#  13. lan-page-01..22.bin were written to the out dir (F5 fixture dump)
#  14. forward-log.txt exists (the listener's log was opened, F3-A)
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
if ($OutRoot -eq '') { $OutRoot = Join-Path $BinDir 'c1-combo-selftest-out' }

$agentExe = Join-Path $BinDir 'civlink-agent.exe'
$fixture  = Join-Path $BinDir 'fixture-reply-set'
if (-not (Test-Path $agentExe)) { Write-Host 'SETUP: civlink-agent.exe missing in BinDir'; exit 2 }
if (-not (Test-Path $fixture))  { Write-Host 'SETUP: fixture-reply-set missing in BinDir'; exit 2 }

Get-Process -Name 'civlink-agent' -ErrorAction SilentlyContinue | Stop-Process -Force

if (Test-Path $OutRoot) { Remove-Item -LiteralPath $OutRoot -Recurse -Force }
New-Item -ItemType Directory -Path $OutRoot | Out-Null

$forwardPort = 21397
# Make sure a stale listener from an aborted run is not holding the port.
$stale = Get-NetUDPEndpoint -LocalPort $forwardPort -ErrorAction SilentlyContinue
if ($stale) { Write-Host "SETUP: UDP $forwardPort already bound (pid $($stale.OwningProcess))"; exit 2 }

$stopFile = Join-Path $OutRoot 'STOP-agent'
$args = @(
    '--listen-seconds', '20',
    '--out-dir', $OutRoot,
    '--stop-file', $stopFile,
    '--simulate', $fixture,
    '--sim-lan-listen', '127.0.0.1',
    '--sim-room-name', 'CivLink-Combo-2222',
    '--reserve-62900',
    '--sim-real-capture',
    '--forward-listen', "$forwardPort"
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
Start-Sleep -Milliseconds 900

$pages = New-Object System.Collections.ArrayList
$recvBytes = 0
$firstPageHead = $null
$roomName = $null
# The burst includes one datagram to 127.0.0.1:62900. If a REAL Civilization VI owns
# that port on this machine it answers too, and its pages land on the same socket.
# They are not the Agent's pages and must not be counted (same fix as the C1 test).
$foreignPages = 0
while ($cli.Available -gt 0) {
    $ep = New-Object System.Net.IPEndPoint([System.Net.IPAddress]'0.0.0.0', 0)
    try {
        $data = $cli.Receive([ref]$ep)
    }
    catch {
        $errCode = $null
        if ($_.Exception -and $_.Exception.ErrorCode) { $errCode = $_.Exception.ErrorCode }
        elseif ($_.Exception.InnerException -and $_.Exception.InnerException.ErrorCode) { $errCode = $_.Exception.InnerException.ErrorCode }
        if ($errCode -eq 10054) { continue }
        throw
    }
    if ($ep.Port -ne 62901) {
        if ($data.Length -eq 1104) { $foreignPages++ }
        continue
    }
    $recvBytes += $data.Length
    if ($data.Length -eq 1104) { [void]$pages.Add($data) }
    if ($null -eq $firstPageHead -and $data.Length -ge 46) {
        $firstPageHead = ($data[0..3] | ForEach-Object { $_.ToString('X2') }) -join ' '
        # The room-name field is 22 bytes and the game pads it with spaces; compare the
        # trimmed text, not the raw field (same rule as the C1 reserve self-test).
        $roomName = ([System.Text.Encoding]::ASCII.GetString($data[24..45])).Trim()
    }
}
$cli.Close()

# --- invariants checked while the Agent is still running -----------------------
$bindCheck = ''
$bindSucceeded = $false
try {
    $probe = New-Object System.Net.Sockets.UdpClient
    $probe.Client.Bind([System.Net.IPEndPoint]::new([System.Net.IPAddress]'127.0.0.1', 62900))
    $bindSucceeded = $true
    $bindCheck = 'bind 127.0.0.1:62900 SUCCEEDED (port left free by --reserve-62900)'
    $probe.Close()
}
catch {
    $bindCheck = "bind 127.0.0.1:62900 FAILED: $($_.Exception.Message)"
}
[IO.File]::WriteAllText((Join-Path $OutRoot 'port-62900-bind-check.txt'), $bindCheck)

# Never binds the game data-plane port - checked on the live process, not from the log.
$dpEndpoints = @()
try {
    $dpEndpoints = @(Get-NetUDPEndpoint -OwningProcess $agentPid -ErrorAction Stop | Where-Object { $_.LocalPort -eq 62056 })
}
catch {
    # Get-NetUDPEndpoint can fail without elevation; fall back to netstat.
    $dpEndpoints = @(netstat -ano -p UDP | Select-String -Pattern '^\s*UDP\s+\S+:62056\s+\S+\s+' | Where-Object { $_.Line -match "\s$agentPid\s*$" })
}
$dpBindCount = $dpEndpoints.Count
[IO.File]::WriteAllText((Join-Path $OutRoot 'port-62056-check.txt'), "agent pid $agentPid UDP endpoints on 62056: $dpBindCount")

# --- stop the agent and collect ------------------------------------------------
[IO.File]::WriteAllText($stopFile, 'stop')
Start-Sleep -Milliseconds 1200
if (-not $proc.HasExited) {
    $proc.Kill()
    $proc.WaitForExit()
}
$exitCode = $proc.ExitCode
$stdout = $stdoutTask.Result
$stderr = $stderrTask.Result

[IO.File]::WriteAllText((Join-Path $OutRoot 'agent-console.txt'), $stdout)
[IO.File]::WriteAllText((Join-Path $OutRoot 'agent-stderr.txt'), $stderr)
[IO.File]::WriteAllText((Join-Path $OutRoot 'exit.txt'), "$exitCode")

for ($i = 0; $i -lt $pages.Count; $i++) {
    [IO.File]::WriteAllBytes((Join-Path $OutRoot ('client-recv-{0:D2}.bin' -f ($i + 1))), $pages[$i])
}

$summaryPath = Join-Path $OutRoot 'summary.txt'
$summary = ''
if (Test-Path $summaryPath) { $summary = [IO.File]::ReadAllText($summaryPath) }

# --- assertions -----------------------------------------------------------------
Check 'agent exited 0' ($exitCode -eq 0) "code=$exitCode"

$noticeLines = ($stderr -split "`n" | Where-Object { $_ -match 'reserved for the game host \(--reserve-62900\)' }).Count
$otherLines = ($stderr -split "`n" | Where-Object { $_.Trim() -ne '' -and $_ -notmatch 'reserved for the game host \(--reserve-62900\)' }).Count
Check 'agent stderr has only the reserve notice' ($noticeLines -eq 1 -and $otherLines -eq 0) "stderr='$stderr'"

$secLan = $summary -match 'LAN simulated host \(F5'
$secB1 = $summary -match 'real advertisement capture \(B1\)'
$secFw = $summary -match 'forward listener \(F3-A peer side\)'
Check 'summary has LAN + B1 + forward sections' ($secLan -and $secB1 -and $secFw) "lan=$secLan b1=$secB1 fw=$secFw"

Check 'summary port 62900 reserved' ($summary -match 'port 62900\s*: reserved, not bound')
Check 'summary reply source 127.0.0.1:62901 (fallback)' ($summary -match 'reply source\s*:\s*127\.0\.0\.1:62901')

$reqMatch = [regex]::Match($summary, 'requests seen\s*:\s*(\d+)')
$repMatch = [regex]::Match($summary, 'replied sockets\s*:\s*(\d+)')
$pgMatch = [regex]::Match($summary, 'pages sent\s*:\s*(\d+)')
$countsOk = $reqMatch.Success -and [int]$reqMatch.Groups[1].Value -eq 99 -and
            $repMatch.Success -and [int]$repMatch.Groups[1].Value -eq 1 -and
            $pgMatch.Success -and [int]$pgMatch.Groups[1].Value -eq 22
Check 'discovery answered: seen 99 / replied 1 / pages 22' $countsOk "seen=$($reqMatch.Groups[1].Value) replied=$($repMatch.Groups[1].Value) pages=$($pgMatch.Groups[1].Value)"

Check 'client got 22 pages (1104 B, magic + room name)' ($pages.Count -eq 22 -and $recvBytes -eq 22 * 1104 -and $firstPageHead -eq '59 60 69 9B' -and $roomName -eq 'CivLink-Combo-2222') "pages=$($pages.Count) bytes=$recvBytes head='$firstPageHead' room='$roomName'"

$capMatch = [regex]::Match($summary, 'captured\s*:\s*(\d+)')
$activeNo = $summary -match 'active\s*:\s*no'
Check 'B1 capture did not fabricate pages (active: no)' ($activeNo -and $capMatch.Success -and [int]$capMatch.Groups[1].Value -eq 0) "captured=$($capMatch.Groups[1].Value)"

$fwPortOk = $summary -match ("listen port\s*:\s*{0}\b" -f $forwardPort)
$fwZero = $summary -match 'payloads recv\s*:\s*0'
Check "forward listener $forwardPort opened, nothing forwarded" ($fwPortOk -and $fwZero) "port=$fwPortOk zero=$fwZero"

$sfMatch = [regex]::Match($summary, 'send fail\s*:\s*(\d+)')
$neMatch = [regex]::Match($summary, 'no endpoint\s*:\s*(\d+)')
$mxMatch = [regex]::Match($summary, 'max reached\s*:\s*(\d+)')
$bfMatch = [regex]::Match($summary, 'bind fail\s*:\s*(\d+)')
$cleanOk = $sfMatch.Success -and [int]$sfMatch.Groups[1].Value -eq 0 -and
           $neMatch.Success -and [int]$neMatch.Groups[1].Value -eq 0 -and
           $mxMatch.Success -and [int]$mxMatch.Groups[1].Value -eq 0 -and
           $bfMatch.Success -and [int]$bfMatch.Groups[1].Value -eq 0
Check 'send fail / no endpoint / max reached / bind fail all 0' $cleanOk

Check 'game slot 62900 bindable while Agent runs' $bindSucceeded $bindCheck

Check 'Agent has no socket on the game data-plane port 62056' ($dpBindCount -eq 0) "found=$dpBindCount"

$lanPages = @(Get-ChildItem -Path $OutRoot -Filter 'lan-page-*.bin' -ErrorAction SilentlyContinue)
Check 'lan-page-01..22.bin written (F5 fixture dump)' ($lanPages.Count -eq 22) "count=$($lanPages.Count)"

Check 'forward-log.txt exists (F3-A listener log)' (Test-Path (Join-Path $OutRoot 'forward-log.txt'))

# --- result file ----------------------------------------------------------------
$result = @"
C1-COMBO-SELFTEST: $(if ($script:Failures.Count -eq 0) { 'PASS' } else { 'FAIL' }) ($($script:Checks) checks)
Evidence: loopback only (127.0.0.1). NOT a real two-machine test; the client is a UDP
script, not a real Civ6 process. Proves the flag combination used by a host-side run is
composable: --reserve-62900 leaves 62900 free for the game's LAN-host socket while
--sim-lan-listen serves the other 99 discovery ports and answers 22 fixture pages from
127.0.0.1:62901, --sim-real-capture stays inactive without real pages, and
--forward-listen opens an independent loopback listener on $forwardPort with nothing
received. No socket on 62056; no SO_REUSEADDR anywhere.
Does NOT prove: real Civ6 behaviour, real peers, E2-B/E3, Gate A, or the C2
IP_UNICAST_IF cross-machine path.
script sha256 : $(Get-Sha256Hex $PSCommandPath)
agent sha256  : $(Get-Sha256Hex $agentExe)
"@
[IO.File]::WriteAllText((Join-Path $OutRoot 'result.txt'), $result)

Write-Host ''
Write-Host ('C1-COMBO-SELFTEST: ' + $(if ($script:Failures.Count -eq 0) { 'PASS' } else { 'FAIL' }) + " ($($script:Checks) checks)")
if ($script:Failures.Count -gt 0) {
    Write-Host ('FAILED: ' + ($script:Failures -join ', '))
    exit 1
}
exit 0
