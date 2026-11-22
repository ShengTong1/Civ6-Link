#requires -Version 5.1
<#
  run-f3e-fault-injection-selftest.ps1 - F3-E fault injection self-test (revision 1).

  Runs the real civlink-relay.exe on 127.0.0.1 and drives four fault scenarios with plain UDP
  sockets that stand in for Agents. No game, no second machine and no injection is involved.

  Evidence label: simulated data-plane peer on the loopback interface. This is NOT a real
  two-machine test, NOT injection into a game process and NOT a multiplayer validation.

  Scenario coverage (F3 design docs\F3-DIRECT-RELAY-DESIGN-20261114.md, §5.2 F3-E row):
    * E-1  fatal/exit 3 real case: a peer socket closes (simulating a peer Agent going away),
           the Relay keeps forwarding into the dead port, the loopback ICMP Port Unreachable
           makes the Relay's own recv_from fail with WSAECONNRESET (10054), which is not the
           WSAEMSGSIZE oversize case, so it must land in the fatal branch and exit 3 with the
           summary written first (F3-B audit round 3, E5: "fatal/exit 3 must have a real case").
           This is the only externally-controllable path into the fatal branch: an IPv4 UDP
           payload cannot exceed the 65535-byte receive buffer, so WSAEMSGSIZE stays a guard.
    * E-2  peer exits but the sender stops pushing: the Relay must stay alive and still exit 0
           on the stop file (a fault is not a licence to crash; DEGRADED/RECONNECTING semantics
           are M0-B targets, this prototype has no state machine).
    * E-3  the Relay itself is hard-killed (dropped link): the driver records "sent but no
           response", never treats silence as a protocol answer, and the kill is reported
           honestly (no clean summary is claimed).
    * E-4  channel down (Relay not running at all): sending still succeeds (UDP semantics),
           no response comes back, no protocol answer is fabricated.

  F3-E boundary, stated honestly: the prototype Agent/Relay has no state machine, so
  DEGRADED/RECONNECTING ("don't kick the player") is declared a M0-B specification target and
  is NOT implemented or claimed here. What this stage proves is that under each fault the
  counters stay truthful, no protocol answer is fabricated, the process does not crash where
  the design says it should not, and where the design says fatal, the real exit code is
  reported (3, not a laundered 0).

  Exit codes: 0 = PASS, 1 = assertion failed, 2 = precheck failed, 3 = setup failed.
#>
[CmdletBinding()]
param(
    [string]$RelayExe = '',
    [string]$OutRoot = ''
)

$ErrorActionPreference = 'Continue'
$script:Failures = New-Object System.Collections.ArrayList
$script:Checks = 0

function Check {
    param([string]$Name, [bool]$Ok, [string]$Detail = '')
    $script:Checks++
    if ($Ok) {
        Write-Host ("  [PASS] {0}{1}" -f $Name, $(if ($Detail) { "  ($Detail)" } else { '' }))
    } else {
        Write-Host ("  [FAIL] {0}{1}" -f $Name, $(if ($Detail) { "  ($Detail)" } else { '' }))
        [void]$script:Failures.Add($Name)
    }
}

# Builds a CVLR envelope (same constructor as the F3-B fixture).
function New-Envelope {
    param(
        [byte]$Flags,
        [uint32]$DstPeer,
        [uint32]$SrcPeer = 0,
        [uint32]$Seq = 0,
        [byte[]]$Payload = @()
    )
    $len = 20 + $Payload.Length
    $buf = New-Object byte[] $len
    $buf[0] = 0x43; $buf[1] = 0x56; $buf[2] = 0x4C; $buf[3] = 0x52   # 'CVLR'
    $buf[4] = 1
    $buf[5] = $Flags
    [Array]::Copy([BitConverter]::GetBytes([uint32]$DstPeer), 0, $buf, 6, 4)
    [Array]::Copy([BitConverter]::GetBytes([uint32]$SrcPeer), 0, $buf, 10, 4)
    [Array]::Copy([BitConverter]::GetBytes([uint32]$Seq), 0, $buf, 14, 4)
    [Array]::Copy([BitConverter]::GetBytes([uint16]$Payload.Length), 0, $buf, 18, 2)
    if ($Payload.Length -gt 0) { [Array]::Copy($Payload, 0, $buf, 20, $Payload.Length) }
    return $buf
}

function Read-Envelope {
    param([byte[]]$Raw)
    if ($Raw.Length -lt 20) { return $null }
    if (-not ($Raw[0] -eq 0x43 -and $Raw[1] -eq 0x56 -and $Raw[2] -eq 0x4C -and $Raw[3] -eq 0x52)) { return $null }
    $plen = [int]$Raw[18] + ([int]$Raw[19] -shl 8)
    if ($plen -gt ($Raw.Length - 20)) { $plen = $Raw.Length - 20 }
    $payload = New-Object byte[] $plen
    if ($plen -gt 0) { [Array]::Copy($Raw, 20, $payload, 0, $plen) }
    return [pscustomobject]@{
        Flags   = $Raw[5]
        DstPeer = [BitConverter]::ToUInt32($Raw, 6)
        SrcPeer = [BitConverter]::ToUInt32($Raw, 10)
        Seq     = [BitConverter]::ToUInt32($Raw, 14)
        Payload = $payload
    }
}

# ---------------------------------------------------------------- setup
$scriptDir = $PSScriptRoot
if (-not $RelayExe) {
    $RelayExe = Join-Path $scriptDir 'relay\target\release\civlink-relay.exe'
}
if (-not (Test-Path -LiteralPath $RelayExe)) {
    Write-Host "[!] relay exe not found: $RelayExe" -ForegroundColor Red
    exit 3
}
$RelayExe = (Resolve-Path -LiteralPath $RelayExe).Path

if (-not $OutRoot) {
    $OutRoot = Join-Path (Split-Path -Parent $PSScriptRoot) 'M0A\captures'
}
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$outDir = Join-Path $OutRoot ("F3E-fault-injection-selftest-" + $stamp)
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

$relayListen = 34720

Write-Host ""
Write-Host "=== F3-E fault injection self-test (revision 1) ===" -ForegroundColor Cyan
Write-Host ("relay    : {0}" -f $RelayExe)
Write-Host ("evidence : {0}" -f $outDir)

# ---------------------------------------------------------------- precheck
$busy = @(Get-NetUDPEndpoint -ErrorAction SilentlyContinue | Where-Object { $_.LocalPort -eq $relayListen })
if ($busy.Count -gt 0) {
    Write-Host ("[!] precheck failed: port {0} already bound ({1})" -f $relayListen, $busy.Count) -ForegroundColor Red
    exit 2
}
Write-Host ("precheck : udp:{0} free" -f $relayListen)

# ---------------------------------------------------------------- helpers
function Start-Relay {
    param([string]$OutDir, [int]$ListenSeconds, [string]$Tag)
    $stopFile = Join-Path $OutDir ($Tag + '-stop.txt')
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $RelayExe
    $psi.Arguments = "--listen 127.0.0.1:$relayListen --listen-seconds $ListenSeconds --out-dir `"$OutDir`" --stop-file `"$stopFile`""
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    $psi.WorkingDirectory = $OutDir
    $proc = [System.Diagnostics.Process]::Start($psi)
    $stdoutTask = $proc.StandardOutput.ReadToEndAsync()
    $stderrTask = $proc.StandardError.ReadToEndAsync()
    $ready = $false
    for ($i = 0; $i -lt 100; $i++) {
        Start-Sleep -Milliseconds 50
        if (@(Get-NetUDPEndpoint -ErrorAction SilentlyContinue | Where-Object { $_.LocalPort -eq $relayListen -and $_.LocalAddress -eq '127.0.0.1' }).Count -ge 1) {
            $ready = $true
            break
        }
    }
    Check ("E-{0}: relay bound 127.0.0.1:{1}" -f $Tag, $relayListen) $ready
    return [pscustomobject]@{
        Proc       = $proc
        StdoutTask = $stdoutTask
        StderrTask = $stderrTask
        StopFile   = $stopFile
        Ready      = $ready
    }
}

function Finish-Relay {
    param($R, [string]$OutDir, [string]$Tag, [bool]$KillInstead = $false, [int]$WaitMs = 8000)
    if (-not $R.Ready) {
        if (-not $R.Proc.HasExited) { try { $R.Proc.Kill() } catch { } }
        return [pscustomobject]@{ Exit = -1; Stdout = ''; Stderr = ''; Killed = $false; Gone = $false }
    }
    $gone = $false
    if ($KillInstead) {
        try { $R.Proc.Kill() } catch { }
        $gone = $R.Proc.WaitForExit(5000)
        if (-not $gone) { $gone = $R.Proc.HasExited }
    } else {
        Set-Content -LiteralPath $R.StopFile -Value 'stop' -Encoding ASCII
        $exited = $R.Proc.WaitForExit($WaitMs)
        if (-not $exited) { try { $R.Proc.Kill() } catch { } }
        $null = $R.Proc.WaitForExit(2000)
        $gone = $R.Proc.HasExited
    }
    $code = -1
    try { $code = $R.Proc.ExitCode } catch { }
    $stdout = ''
    $stderr = ''
    try { $stdout = $R.StdoutTask.Result } catch { }
    try { $stderr = $R.StderrTask.Result } catch { }
    Set-Content -LiteralPath (Join-Path $OutDir ($Tag + '-console.txt')) -Value $stdout -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $OutDir ($Tag + '-stderr.txt')) -Value $stderr -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $OutDir ($Tag + '-exit.txt')) -Value ("exitcode={0}" -f $code) -Encoding ASCII
    return [pscustomobject]@{ Exit = $code; Stdout = $stdout; Stderr = $stderr; Killed = $KillInstead; Gone = $gone }
}

function Get-Counter {
    param([string]$Text, [string]$Name)
    $m = [regex]::Match($Text, ('(?m)^{0}\s*:\s*(\d+)' -f [regex]::Escape($Name)))
    if ($m.Success) { return [int]$m.Groups[1].Value }
    return -1
}

function Send-Data {
    param([System.Net.Sockets.UdpClient]$Client, [uint32]$DstPeer, [uint32]$Seq, [byte[]]$Payload, [System.Net.IPEndPoint]$Target)
    $e = New-Envelope -Flags 0x00 -DstPeer $DstPeer -Seq $Seq -Payload $Payload
    [void]$Client.Send($e, $e.Length, $Target)
}

$payload1 = [byte[]](0x17, 0x32, 0x00, 0x00, 0xFF, 0xFF, 0x4F, 0xAC)   # the observed S5 8B frame
$payload2 = [byte[]](0x17, 0x32, 0x00, 0x00, 0xFF, 0xFF, 0x35, 0xBA)

# ================================================================ E-1: fatal/exit 3 real case
Write-Host ""
Write-Host "=== E-1: peer goes away, Relay forwards into the dead port, ICMP 10054 -> fatal -> exit 3 ===" -ForegroundColor Cyan

$e1Dir = Join-Path $outDir 'E1'
New-Item -ItemType Directory -Force -Path $e1Dir | Out-Null

$r1 = Start-Relay -OutDir $e1Dir -ListenSeconds 40 -Tag 'E1'
if (-not $r1.Ready) {
    Set-Content -LiteralPath (Join-Path $outDir 'result.txt') -Value 'F3E-FAULT-INJECTION-SELFTEST: FAIL (E-1 relay did not bind)' -Encoding ASCII
    exit 3
}

$relayAddr = New-Object System.Net.IPEndPoint ([System.Net.IPAddress]::Parse('127.0.0.1')), $relayListen
$peerA = New-Object System.Net.Sockets.UdpClient 0
$peerA.Client.ReceiveTimeout = 400
$peerB = New-Object System.Net.Sockets.UdpClient 0
$peerB.Client.ReceiveTimeout = 400
$addrA = $peerA.Client.LocalEndPoint
$addrB = $peerB.Client.LocalEndPoint
Write-Host ("peer A   : {0}  peer B : {1}" -f $addrA, $addrB)

$peerIdA = 101
$peerIdB = 202

# register both peers (3x each, loopback can drop a single datagram)
for ($k = 0; $k -lt 3; $k++) {
    $ra = New-Envelope -Flags 0x01 -DstPeer $peerIdA
    [void]$peerA.Send($ra, $ra.Length, $relayAddr)
    $rb = New-Envelope -Flags 0x01 -DstPeer $peerIdB
    [void]$peerB.Send($rb, $rb.Length, $relayAddr)
    Start-Sleep -Milliseconds 40
}
Start-Sleep -Milliseconds 120

# baseline: A -> B frame must arrive while B is alive (proves the link was up before the fault)
Send-Data -Client $peerA -DstPeer $peerIdB -Seq 1 -Payload $payload1 -Target $relayAddr
Start-Sleep -Milliseconds 250
try {
    $remote = New-Object System.Net.IPEndPoint ([System.Net.IPAddress]::Any), 0
    $raw = $peerB.Receive([ref]$remote)
    $baseline = Read-Envelope -Raw $raw
} catch {
    $baseline = $null
}
Check 'E-1 baseline frame reached B while B was alive' ([bool]($baseline -and $baseline.Seq -eq 1)) $(if ($baseline) { 'seq=' + $baseline.Seq } else { 'no frame' })

# the fault: peer B closes (peer Agent goes away)
try { $peerB.Close() } catch { }
Start-Sleep -Milliseconds 100

# push one frame into the dead port; the Relay's send_to succeeds (UDP semantics), the
# loopback ICMP Port Unreachable then makes the Relay's own recv_from return WSAECONNRESET.
Send-Data -Client $peerA -DstPeer $peerIdB -Seq 2 -Payload $payload2 -Target $relayAddr

# wait for the Relay to die on its own (fatal -> exit 3). The summary is written before exit.
$fatalExit = $null
$deadline = (Get-Date).AddSeconds(10)
while ((Get-Date) -lt $deadline) {
    Start-Sleep -Milliseconds 200
    if ($r1.Proc.HasExited) { $fatalExit = $r1.Proc.ExitCode; break }
}
if ($null -eq $fatalExit) {
    # did not die on its own: stop it and record what happened
    $fin = Finish-Relay -R $r1 -OutDir $e1Dir -Tag 'E1'
    Check 'E-1 relay died on its own with exit code 3' $false ("exit=" + $fin.Exit)
    Check 'E-1 stderr reports the fatal recv_from failure' ([bool]($fin.Stderr -match 'recv_from failed')) ($fin.Stderr.Trim())
} else {
    $stdout = ''
    $stderr = ''
    try { $stdout = $r1.StdoutTask.Result } catch { }
    try { $stderr = $r1.StderrTask.Result } catch { }
    Set-Content -LiteralPath (Join-Path $e1Dir 'E1-console.txt') -Value $stdout -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $e1Dir 'E1-stderr.txt') -Value $stderr -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $e1Dir 'E1-exit.txt') -Value ("exitcode={0}" -f $fatalExit) -Encoding ASCII
    Check 'E-1 relay died on its own with exit code 3' ($fatalExit -eq 3) ("exit=" + $fatalExit)
    Check 'E-1 stderr reports the fatal recv_from failure' ($stderr -match 'recv_from failed') ($stderr.Trim())
}

$e1SummaryPath = Join-Path $e1Dir 'relay-summary.txt'
$e1SummaryOk = Test-Path -LiteralPath $e1SummaryPath
Check 'E-1 relay-summary.txt exists (written before the fatal exit)' $e1SummaryOk ''
$e1Text = ''
if ($e1SummaryOk) { $e1Text = [IO.File]::ReadAllText($e1SummaryPath) }

if ($e1SummaryOk) {
    Check 'E-1 summary fatal line is not "none"' ($e1Text -match '(?m)^fatal\s*:\s*(?!none\s*$)') ''
    $d = Get-Counter $e1Text 'datagrams'
    $reg = Get-Counter $e1Text 'registers'
    $fReq = Get-Counter $e1Text 'forward requests'
    $bEnv = Get-Counter $e1Text 'bad envelope'
    $uF = Get-Counter $e1Text 'unknown flags'
    # registers: 3+3 sent; A may have lost some. forward requests: seq=1 and seq=2 both
    # entered the forwarding stage before the fatal error. bad/unknown: 0.
    Check 'E-1 datagram identity holds (datagrams == registers + forward_requests + bad + unknown)' ($d -eq ($reg + $fReq + $bEnv + $uF)) ("{0} vs {1}+{2}+{3}+{4}" -f $d, $reg, $fReq, $bEnv, $uF)
    Check 'E-1 forward requests = 2 (baseline + dead-port push)' ($fReq -eq 2) ("got=" + $fReq)
    Check 'E-1 forwarded = 2 (both send_to succeeded under UDP semantics)' ((Get-Counter $e1Text 'forwarded') -eq 2) ("got=" + (Get-Counter $e1Text 'forwarded'))
    Check 'E-1 bad envelope = 0 / unknown flags = 0' ($bEnv -eq 0 -and $uF -eq 0) ("bad=" + $bEnv + " unk=" + $uF)
    Check 'E-1 reconciliation line present' ($e1Text -match '(?m)^reconciliation\s*:') ''
}

# no protocol answer may be fabricated: peer A must see nothing back from the Relay.
try {
    $remote2 = New-Object System.Net.IPEndPoint ([System.Net.IPAddress]::Any), 0
    $rawA = $peerA.Receive([ref]$remote2)
    $gotA = Read-Envelope -Raw $rawA
} catch {
    $gotA = $null
}
Check 'E-1 no protocol answer fabricated for peer A' ($null -eq $gotA) $(if ($gotA) { 'unexpected frame seq=' + $gotA.Seq } else { 'no frame (timeout)' })

try { $peerA.Close() } catch { }

# ================================================================ E-2: peer exits, sender stops -> Relay survives
Write-Host ""
Write-Host "=== E-2: peer exits but no further traffic -> Relay stays alive, exits 0 on stop file ===" -ForegroundColor Cyan

$e2Dir = Join-Path $outDir 'E2'
New-Item -ItemType Directory -Force -Path $e2Dir | Out-Null

$r2 = Start-Relay -OutDir $e2Dir -ListenSeconds 40 -Tag 'E2'
if (-not $r2.Ready) {
    Set-Content -LiteralPath (Join-Path $outDir 'result.txt') -Value 'F3E-FAULT-INJECTION-SELFTEST: FAIL (E-2 relay did not bind)' -Encoding ASCII
    exit 3
}

$peerA2 = New-Object System.Net.Sockets.UdpClient 0
$peerA2.Client.ReceiveTimeout = 400
$peerB2 = New-Object System.Net.Sockets.UdpClient 0
$peerB2.Client.ReceiveTimeout = 400

for ($k = 0; $k -lt 3; $k++) {
    $ra = New-Envelope -Flags 0x01 -DstPeer $peerIdA
    [void]$peerA2.Send($ra, $ra.Length, $relayAddr)
    $rb = New-Envelope -Flags 0x01 -DstPeer $peerIdB
    [void]$peerB2.Send($rb, $rb.Length, $relayAddr)
    Start-Sleep -Milliseconds 40
}
Start-Sleep -Milliseconds 120

Send-Data -Client $peerA2 -DstPeer $peerIdB -Seq 1 -Payload $payload1 -Target $relayAddr
Start-Sleep -Milliseconds 250
try {
    $remote = New-Object System.Net.IPEndPoint ([System.Net.IPAddress]::Any), 0
    $raw = $peerB2.Receive([ref]$remote)
    $b2 = Read-Envelope -Raw $raw
} catch {
    $b2 = $null
}
Check 'E-2 baseline frame reached B' ([bool]($b2 -and $b2.Seq -eq 1)) $(if ($b2) { 'seq=' + $b2.Seq } else { 'no frame' })

# the fault: B exits. The sender then stops pushing (no traffic into the dead port).
try { $peerB2.Close() } catch { }
Start-Sleep -Milliseconds 1500

Check 'E-2 relay still alive after peer exit with no further traffic' (-not $r2.Proc.HasExited) ("HasExited=" + $r2.Proc.HasExited)

$fin2 = Finish-Relay -R $r2 -OutDir $e2Dir -Tag 'E2'
Check 'E-2 relay exits 0 on stop file' ($fin2.Exit -eq 0) ("exit=" + $fin2.Exit)
$e2Text = ''
if (Test-Path -LiteralPath (Join-Path $e2Dir 'relay-summary.txt')) {
    $e2Text = [IO.File]::ReadAllText((Join-Path $e2Dir 'relay-summary.txt'))
    Check 'E-2 summary fatal line is "none"' ($e2Text -match '(?m)^fatal\s*:\s*none\s*$') ''
    Check 'E-2 summary reconciliation holds' ($e2Text -match '(?m)^reconciliation\s*:.*\s==\s') ''
}
try { $peerA2.Close() } catch { }

# ================================================================ E-3: Relay itself hard-killed
Write-Host ""
Write-Host "=== E-3: Relay hard-killed (dropped link) -> driver records sent-but-no-response ===" -ForegroundColor Cyan

$e3Dir = Join-Path $outDir 'E3'
New-Item -ItemType Directory -Force -Path $e3Dir | Out-Null

$r3 = Start-Relay -OutDir $e3Dir -ListenSeconds 40 -Tag 'E3'
if (-not $r3.Ready) {
    Set-Content -LiteralPath (Join-Path $outDir 'result.txt') -Value 'F3E-FAULT-INJECTION-SELFTEST: FAIL (E-3 relay did not bind)' -Encoding ASCII
    exit 3
}

$peerA3 = New-Object System.Net.Sockets.UdpClient 0
$peerA3.Client.ReceiveTimeout = 400
for ($k = 0; $k -lt 3; $k++) {
    $ra = New-Envelope -Flags 0x01 -DstPeer $peerIdA
    [void]$peerA3.Send($ra, $ra.Length, $relayAddr)
    Start-Sleep -Milliseconds 40
}
Start-Sleep -Milliseconds 120

Send-Data -Client $peerA3 -DstPeer $peerIdB -Seq 1 -Payload $payload1 -Target $relayAddr
Start-Sleep -Milliseconds 200

# the fault: hard-kill the Relay process (simulates the Relay dropping off the network).
$fin3 = Finish-Relay -R $r3 -OutDir $e3Dir -Tag 'E3' -KillInstead $true
Check 'E-3 relay process gone after hard kill' $fin3.Gone ("gone=" + $fin3.Gone + " exit=" + $fin3.Exit)

# push after the kill: sending succeeds (UDP), but no response may come back and nothing may
# be fabricated.
Send-Data -Client $peerA3 -DstPeer $peerIdB -Seq 2 -Payload $payload2 -Target $relayAddr
try {
    $remote = New-Object System.Net.IPEndPoint ([System.Net.IPAddress]::Any), 0
    $raw = $peerA3.Receive([ref]$remote)
    $got3 = Read-Envelope -Raw $raw
} catch {
    $got3 = $null
}
Check 'E-3 no protocol answer fabricated after relay kill' ($null -eq $got3) $(if ($got3) { 'unexpected frame' } else { 'no frame (timeout)' })
try { $peerA3.Close() } catch { }

# ================================================================ E-4: channel down (no Relay at all)
Write-Host ""
Write-Host "=== E-4: Relay not running (channel down) -> sending succeeds, no response, no fabricated answer ===" -ForegroundColor Cyan

$e4Dir = Join-Path $outDir 'E4'
New-Item -ItemType Directory -Force -Path $e4Dir | Out-Null

$stillBusy = @(Get-NetUDPEndpoint -ErrorAction SilentlyContinue | Where-Object { $_.LocalPort -eq $relayListen })
Check 'E-4 udp:34720 is free again (all relays exited)' ($stillBusy.Count -eq 0) ("endpoints=" + $stillBusy.Count)

$peerA4 = New-Object System.Net.Sockets.UdpClient 0
$peerA4.Client.ReceiveTimeout = 400
Send-Data -Client $peerA4 -DstPeer $peerIdB -Seq 1 -Payload $payload1 -Target $relayAddr
try {
    $remote = New-Object System.Net.IPEndPoint ([System.Net.IPAddress]::Any), 0
    $raw = $peerA4.Receive([ref]$remote)
    $got4 = Read-Envelope -Raw $raw
} catch {
    $got4 = $null
}
Check 'E-4 no response and no fabricated answer when relay is down' ($null -eq $got4) $(if ($got4) { 'unexpected frame' } else { 'no frame (timeout)' })
try { $peerA4.Close() } catch { }

# ---------------------------------------------------------------- verdict
# 23 checks: E-1 12 (bind + baseline + died-3 + stderr + summary-ok + fatal-not-none +
# datagram-identity + fwd-requests + forwarded + bad/unk + reconciliation + no-fabricated),
# E-2 6 (bind + baseline + still-alive + exit-0 + fatal-none + reconciliation),
# E-3 3 (bind + gone + no-fabricated), E-4 2 (port-free + no-fabricated).
$expectChecks = 23
$verdict = if ($script:Failures.Count -eq 0 -and $script:Checks -eq $expectChecks) {
    "F3E-FAULT-INJECTION-SELFTEST: PASS ($script:Checks/$expectChecks)"
} elseif ($script:Failures.Count -eq 0) {
    "F3E-FAULT-INJECTION-SELFTEST: FAIL (clean but $($script:Checks) of $expectChecks checks ran)"
} else {
    "F3E-FAULT-INJECTION-SELFTEST: FAIL ($($script:Failures.Count) of $script:Checks failed)"
}
$report = New-Object System.Collections.ArrayList
[void]$report.Add($verdict)
[void]$report.Add("evidence label: simulated data-plane peer on loopback; NOT a real two-machine test,")
[void]$report.Add("               NOT injection into a game process, NOT a multiplayer validation.")
[void]$report.Add("DEGRADED/RECONNECTING state-machine semantics are M0-B targets; the F3 prototype")
[void]$report.Add("has no state machine and this stage does NOT claim them.")
[void]$report.Add("evidence dir : $outDir")
[void]$report.Add("relay exe    : $RelayExe")
[void]$report.Add(("relay sha256 : {0}" -f (Get-FileHash -LiteralPath $RelayExe -Algorithm SHA256).Hash))
[void]$report.Add(("relay bytes  : {0}" -f (Get-Item -LiteralPath $RelayExe).Length))
[void]$report.Add("script       : $PSCommandPath")
[void]$report.Add(("script sha256: {0}" -f (Get-FileHash -LiteralPath $PSCommandPath -Algorithm SHA256).Hash))
if ($script:Failures.Count -gt 0) {
    [void]$report.Add('failed checks:')
    foreach ($f in $script:Failures) { [void]$report.Add("  - $f") }
}
Set-Content -LiteralPath (Join-Path $outDir 'result.txt') -Value ($report -join "`r`n") -Encoding UTF8

Write-Host ""
Write-Host $verdict -ForegroundColor $(if ($script:Failures.Count -eq 0 -and $script:Checks -eq $expectChecks) { 'Green' } else { 'Red' })
Write-Host ("evidence: {0}" -f $outDir)
if ($script:Failures.Count -eq 0 -and $script:Checks -eq $expectChecks) { exit 0 } else { exit 1 }
