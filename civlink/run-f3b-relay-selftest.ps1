#requires -Version 5.1
<#
  run-f3b-relay-selftest.ps1 - F3-B Relay routing prototype self-test (revision 3).

  Runs the real civlink-relay.exe on 127.0.0.1 and talks to it with plain UDP sockets that
  stand in for Agents. Every assertion is a machine check; no game, no second machine and no
  injection is involved.

  Evidence label: simulated data-plane peer on the loopback interface. This is NOT a real
  two-machine test, NOT injection into a game process and NOT a multiplayer validation.

  Revision 2 answers the F3-B audit (docs\F3B-REVIEW.md). What changed:
    * the two always-true "precheck" checks are gone
    * the datagram identity is a real identity: the Relay summary now prints
      datagrams == registers + forward_requests + bad_envelope + unknown_flags, and this
      script asserts exact per-category counts so the identity is not fed by the fixture
    * all five parser rejection paths are exercised: too-short, bad-magic, bad-version,
      payload-too-large, truncated
    * an unknown-flag control frame is exercised and must not be forwarded
    * a 5000-byte datagram is sent and the Relay must still be serving afterwards (audit H-1)
    * a B->A frame proves forwarding works in both directions (M-3)
    * `--listen 127.0.0.1:62056` must be refused by the binary itself (M-2)
    * registration loss is printed instead of being hidden behind `registers >= 5`
    * the non-quiet stdout path is covered, so relay-console.txt is no longer empty

  Exit codes: 0 = PASS, 1 = assertion failed, 2 = precheck failed, 3 = setup failed.
#>
[CmdletBinding()]
param(
    [string]$RelayExe = '',
    [string]$OutRoot = '',
    [int]$ListenSeconds = 40
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

# FNV-1a 64 shifted by hand with BigInteger.
# PowerShell casts uint64 multiplication to double and silently loses precision, so a plain
# [uint64] accumulator returns a wrong hash (found here: it reported c5620494...).
$script:FnvOffset = [System.Numerics.BigInteger]::Parse('14695981039346656037')
$script:FnvPrime = [System.Numerics.BigInteger]::Parse('1099511628211')
$script:Mod64 = [System.Numerics.BigInteger]::Parse('18446744073709551616')

function Get-Fnv1a64Hex {
    param([byte[]]$Data)
    $h = $script:FnvOffset
    foreach ($b in $Data) {
        $h = $h -bxor ([System.Numerics.BigInteger]$b)
        $h = ($h * $script:FnvPrime) % $script:Mod64
    }
    # BigInteger's 'x16' format specifier emits a sign nibble, so format plainly and keep
    # only the low 64 bits: 'x16' on 0xc5620494bd8475c1 comes out 17 characters long.
    $hex = '{0:x}' -f $h
    if ($hex.Length -gt 16) { $hex = $hex.Substring($hex.Length - 16) }
    return $hex.PadLeft(16, '0')
}

# Builds a CVLR envelope. The three override parameters exist so the five parser rejection
# paths can be produced from one constructor instead of five hand-assembled byte arrays.
function New-Envelope {
    param(
        [byte]$Flags,
        [uint32]$DstPeer,
        [uint32]$SrcPeer = 0,
        [uint32]$Seq = 0,
        [byte[]]$Payload = @(),
        [byte]$Version = 1,
        [int]$DeclaredPayloadLen = -1,
        [int]$TotalBytes = -1
    )
    $declared = if ($DeclaredPayloadLen -ge 0) { $DeclaredPayloadLen } else { $Payload.Length }
    $len = 20 + $Payload.Length
    if ($TotalBytes -ge 0) { $len = $TotalBytes }
    $buf = New-Object byte[] $len
    $buf[0] = 0x43; $buf[1] = 0x56; $buf[2] = 0x4C; $buf[3] = 0x52   # 'CVLR'
    $buf[4] = $Version
    $buf[5] = $Flags
    [Array]::Copy([BitConverter]::GetBytes([uint32]$DstPeer), 0, $buf, 6, 4)
    [Array]::Copy([BitConverter]::GetBytes([uint32]$SrcPeer), 0, $buf, 10, 4)
    [Array]::Copy([BitConverter]::GetBytes([uint32]$Seq), 0, $buf, 14, 4)
    [Array]::Copy([BitConverter]::GetBytes([uint16]$declared), 0, $buf, 18, 2)
    if ($Payload.Length -gt 0 -and $len -ge (20 + $Payload.Length)) {
        [Array]::Copy($Payload, 0, $buf, 20, $Payload.Length)
    }
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
$outDir = Join-Path $OutRoot ("F3B-relay-selftest-" + $stamp)
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

$relayListen = 34720
$stopFile = Join-Path $outDir 'stop.txt'
$relayOut = Join-Path $outDir 'relay-console.txt'
$relayErr = Join-Path $outDir 'relay-stderr.txt'

Write-Host ""
Write-Host "=== F3-B relay self-test (revision 3) ===" -ForegroundColor Cyan
Write-Host ("relay    : {0}" -f $RelayExe)
Write-Host ("evidence : {0}" -f $outDir)

# ---------------------------------------------------------------- negative: game port
# The H2 threshold must be enforced by the binary, not only by this script's preconditions
# (audit M-2). Run the Relay pointed at the game data-plane port and require a refusal.
$npOut = Join-Path $outDir 'negative-62056-console.txt'
$npErr = Join-Path $outDir 'negative-62056-stderr.txt'
$npPsi = New-Object System.Diagnostics.ProcessStartInfo
$npPsi.FileName = $RelayExe
$npPsi.Arguments = "--listen 127.0.0.1:62056 --listen-seconds 3 --quiet"
$npPsi.UseShellExecute = $false
$npPsi.RedirectStandardOutput = $true
$npPsi.RedirectStandardError = $true
$npPsi.CreateNoWindow = $true
$npPsi.WorkingDirectory = $outDir
$npProc = [System.Diagnostics.Process]::Start($npPsi)
$npOutTask = $npProc.StandardOutput.ReadToEndAsync()
$npErrTask = $npProc.StandardError.ReadToEndAsync()
$npExited = $npProc.WaitForExit(10000)
if (-not $npExited) { try { $npProc.Kill() } catch { } }
$null = $npProc.WaitForExit(2000)
$npCode = $npProc.ExitCode
$npStdout = $npOutTask.Result
$npStderr = $npErrTask.Result
Set-Content -LiteralPath $npOut -Value $npStdout -Encoding UTF8
Set-Content -LiteralPath $npErr -Value $npStderr -Encoding UTF8
Check 'relay refuses --listen 127.0.0.1:62056' ($npExited -and $npCode -eq 1) ("exit=" + $npCode)
Check 'refusal names the game data-plane port' ($npStderr -match 'must not use port 62056') $npStderr.Trim()
$still62056 = @(Get-NetUDPEndpoint -ErrorAction SilentlyContinue | Where-Object { $_.LocalPort -eq 62056 })
Check 'nothing bound 62056 after the refusal' ($still62056.Count -eq 0) ("endpoints=" + $still62056.Count)

# ---------------------------------------------------------------- precheck
$busy = @(Get-NetUDPEndpoint -ErrorAction SilentlyContinue | Where-Object { $_.LocalPort -eq $relayListen })
if ($busy.Count -gt 0) {
    Write-Host ("[!] precheck failed: port {0} already bound ({1})" -f $relayListen, $busy.Count) -ForegroundColor Red
    exit 2
}
Write-Host ("precheck : udp:{0} free" -f $relayListen)

# ---------------------------------------------------------------- start relay
$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = $RelayExe
# No --quiet here: the stdout summary path must be covered too (audit G-6).
$psi.Arguments = "--listen 127.0.0.1:$relayListen --listen-seconds $ListenSeconds --out-dir `"$outDir`" --stop-file `"$stopFile`""
$psi.UseShellExecute = $false
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
$psi.CreateNoWindow = $true
$psi.WorkingDirectory = $outDir
$clockStart = Get-Date
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
Check 'relay bound 127.0.0.1:34720' $ready
if (-not $ready) {
    try { $proc.Kill() } catch { }
    Set-Content -LiteralPath (Join-Path $outDir 'result.txt') -Value 'F3B-RELAY-SELFTEST: FAIL (relay did not bind)' -Encoding ASCII
    exit 3
}

# The Relay must not have grabbed the game data port.
$port62056 = @(Get-NetUDPEndpoint -ErrorAction SilentlyContinue | Where-Object { $_.LocalPort -eq 62056 })
Set-Content -LiteralPath (Join-Path $outDir 'bind-check.txt') -Value ("udp:{0} endpoints: {1}" -f 62056, $port62056.Count) -Encoding ASCII
Check 'relay does not own 62056' ($port62056.Count -eq 0) ("endpoints=" + $port62056.Count)

# ---------------------------------------------------------------- peer sockets
$relayAddr = New-Object System.Net.IPEndPoint ([System.Net.IPAddress]::Parse('127.0.0.1')), $relayListen
$peerA = New-Object System.Net.Sockets.UdpClient 0
$peerA.Client.ReceiveTimeout = 1500
$peerB = New-Object System.Net.Sockets.UdpClient 0
$peerB.Client.ReceiveTimeout = 1500
$addrA = $peerA.Client.LocalEndPoint
$addrB = $peerB.Client.LocalEndPoint
Write-Host ("peer A   : {0}" -f $addrA)
Write-Host ("peer B   : {0}" -f $addrB)

$peerIdA = 101
$peerIdB = 202

# REGISTER: A says "I am 101", B says "I am 202".
#
# Each registration is sent three times. That is not padding around a bug: the first run of
# this self-test lost peer A's single REGISTER datagram (the Relay then resolved the sender as
# unknown, so the dst=101 frame came out as no-route instead of self-drop). Loopback UDP can
# drop, and a real Agent re-registers periodically anyway, so the fixture does the same. The
# forwarding assertions below stay exact, and the registration loss is printed, not hidden.
$script:RegistrationsSent = 0
function Send-Register {
    param([System.Net.Sockets.UdpClient]$Client, [uint32]$PeerId, [int]$Times = 3)
    for ($k = 0; $k -lt $Times; $k++) {
        $r = New-Envelope -Flags 0x01 -DstPeer $PeerId
        [void]$Client.Send($r, $r.Length, $relayAddr)
        $script:RegistrationsSent++
        Start-Sleep -Milliseconds 40
    }
}
Send-Register -Client $peerA -PeerId $peerIdA
Send-Register -Client $peerB -PeerId $peerIdB
Start-Sleep -Milliseconds 120

# ---------------------------------------------------------------- payloads
$payload1 = [byte[]](0x17, 0x32, 0x00, 0x00, 0xFF, 0xFF, 0x4F, 0xAC)   # the observed S5 8B frame
$payload2 = New-Object byte[] 120
for ($i = 0; $i -lt 120; $i++) { $payload2[$i] = [byte](($i * 7 + 3) -band 0xFF) }
$payload3 = [byte[]](0x17, 0x32, 0x00, 0x00, 0xFF, 0xFF, 0x35, 0xBA)   # reverse-direction 8B

# Refresh A's registration immediately before the frames it sends, so self-drop is not
# decided by whether the earlier registration survived.
Send-Register -Client $peerA -PeerId $peerIdA -Times 2

$sent = @(
    @{ Name = 'seq1 dst=202 8B';  Bytes = (New-Envelope -Flags 0x00 -DstPeer $peerIdB -Seq 1 -Payload $payload1) },
    @{ Name = 'seq2 dst=999 no-route'; Bytes = (New-Envelope -Flags 0x00 -DstPeer 999 -Seq 2 -Payload $payload1) },
    @{ Name = 'seq3 dst=101 self';  Bytes = (New-Envelope -Flags 0x00 -DstPeer $peerIdA -Seq 3 -Payload $payload1) },
    @{ Name = 'seq4 dst=202 120B'; Bytes = (New-Envelope -Flags 0x00 -DstPeer $peerIdB -Seq 4 -Payload $payload2) }
)
foreach ($s in $sent) {
    [void]$peerA.Send($s.Bytes, $s.Bytes.Length, $relayAddr)
    Start-Sleep -Milliseconds 70
}

# ---------------------------------------------------------------- rejection paths (all five)
# too-short          : 12 bytes, cannot hold the 20-byte header
# bad-magic          : header-sized but not 'CVLR'
# bad-version        : 'CVLR' with version 2
# payload-too-large  : declared payload 1281 > 1280
# truncated          : declares 100 payload bytes, the datagram carries 60
# bad-magic          : header-sized, 'CVLR' corrupted. Built by hand because New-Envelope
#                      always writes a valid magic (the first revision claimed a bad-magic
#                      case that actually carried a good magic and parsed as DATA).
$badMagic = New-Object byte[] 24
$badMagic[4] = 1
$badCases = @(
    @{ Name = 'too-short'; Bytes = (New-Object byte[] 12) },
    @{ Name = 'bad-magic'; Bytes = $badMagic },
    @{ Name = 'bad-version'; Bytes = (New-Envelope -Flags 0x00 -DstPeer 0 -Version 2 -TotalBytes 24) },
    @{ Name = 'payload-too-large'; Bytes = (New-Envelope -Flags 0x00 -DstPeer 0 -DeclaredPayloadLen 1281 -TotalBytes 24) },
    @{ Name = 'truncated'; Bytes = (New-Envelope -Flags 0x00 -DstPeer 0 -DeclaredPayloadLen 100 -TotalBytes 60) }
)
foreach ($c in $badCases) {
    [void]$peerA.Send($c.Bytes, $c.Bytes.Length, $relayAddr)
    Start-Sleep -Milliseconds 60
}

# Unknown flag: a well-formed envelope this prototype does not route. It must be counted and
# dropped, never forwarded (this is the frame that proved the old datagram identity was only
# fed by the fixture).
$unknownFlagFrame = New-Envelope -Flags 0x02 -DstPeer $peerIdB -Seq 90 -Payload ([byte[]](1, 2, 3, 4))
[void]$peerA.Send($unknownFlagFrame, $unknownFlagFrame.Length, $relayAddr)
Start-Sleep -Milliseconds 60

# Oversize-shaped input (audit H-1): a 5000-byte datagram, far larger than the 4096-byte
# buffer the audit found. It is built as a well-formed CVLR header with a declared payload of
# 1281 bytes so the parser rejects it as payload-too-large; the point of the check is that the
# Relay is still serving afterwards. With RECV_BUF = 65535 an IPv4 UDP payload cannot exceed
# the buffer, so the WSAEMSGSIZE branch stays a guard rather than a reachable path.
$big = New-Envelope -Flags 0x00 -DstPeer 0 -DeclaredPayloadLen 1281 -TotalBytes 5000
[void]$peerA.Send($big, $big.Length, $relayAddr)
Start-Sleep -Milliseconds 1200
Check 'relay still serving after a 5000-byte datagram' (-not $proc.HasExited) ("HasExited=" + $proc.HasExited)

# Reverse direction: B -> A (audit M-3, the old fixture was one-way only).
Send-Register -Client $peerB -PeerId $peerIdB -Times 2
$revBytes = New-Envelope -Flags 0x00 -DstPeer $peerIdA -Seq 5 -Payload $payload3
[void]$peerB.Send($revBytes, $revBytes.Length, $relayAddr)
Start-Sleep -Milliseconds 250

# Unregistered source (audit round 2, H-2). The first revision of this document claimed the
# `no sender` branch was "reachable and covered", but the fixture only ever had two sockets and
# both were registered: the counter stayed at 0 and the branch was never entered. This socket is
# deliberately NEVER registered, and it declares src_peer=303 in the envelope so that a
# fail-closed implementation (envelope src_peer not trusted) and a naive one (trust it) produce
# different observable results: fail-closed drops the frame and counts `no sender`, while a
# naive Relay would resolve 303->this socket and then route dst=202 successfully.
$peerX = New-Object System.Net.Sockets.UdpClient 0
try {
    $peerX.Client.ReceiveTimeout = 500
    $unregistered = New-Envelope -Flags 0x00 -DstPeer $peerIdB -SrcPeer 303 -Seq 91 -Payload ([byte[]](0xDE, 0xAD, 0xBE, 0xEF))
    [void]$peerX.Send($unregistered, $unregistered.Length, $relayAddr)
    Start-Sleep -Milliseconds 250
} finally {
    $peerX.Close()
}

# ---------------------------------------------------------------- receive at both peers
function Receive-Frames {
    param([System.Net.Sockets.UdpClient]$Client, [int]$Max)
    $list = New-Object System.Collections.ArrayList
    for ($i = 0; $i -lt $Max; $i++) {
        try {
            $remote = New-Object System.Net.IPEndPoint ([System.Net.IPAddress]::Any), 0
            $raw = $Client.Receive([ref]$remote)
            if ($raw -and $raw.Length -gt 0) { [void]$list.Add((Read-Envelope -Raw $raw)) }
        } catch [System.Net.Sockets.SocketException] {
            break
        }
    }
    return , $list
}

$receivedB = Receive-Frames -Client $peerB -Max 6
$receivedA = Receive-Frames -Client $peerA -Max 6

Check 'peer B received 2 frames' ($receivedB.Count -eq 2) ("count=" + $receivedB.Count)
if ($receivedB.Count -ge 1) {
    $r1 = $receivedB[0]
    Check 'B frame 1 is seq=1' ($r1.Seq -eq 1) ("seq=" + $r1.Seq)
    Check 'B frame 1 dst_peer=202 preserved' ($r1.DstPeer -eq $peerIdB) ("dst=" + $r1.DstPeer)
    Check 'B frame 1 src_peer filled by relay = 101' ($r1.SrcPeer -eq $peerIdA) ("src=" + $r1.SrcPeer)
    Check 'B frame 1 payload byte-identical 8B' ([bool](($payload1.Length -eq $r1.Payload.Length) -and ((Compare-Object -ReferenceObject $payload1 -DifferenceObject $r1.Payload -SyncWindow 0 | Measure-Object).Count -eq 0))) ("len=" + $r1.Payload.Length)
    Check 'B frame 1 fnv1a64 matches sender' ((Get-Fnv1a64Hex -Data $r1.Payload) -eq (Get-Fnv1a64Hex -Data $payload1)) (Get-Fnv1a64Hex -Data $r1.Payload)
}
if ($receivedB.Count -ge 2) {
    $r2 = $receivedB[1]
    Check 'B frame 2 is seq=4' ($r2.Seq -eq 4) ("seq=" + $r2.Seq)
    Check 'B frame 2 payload 120B not truncated' ($r2.Payload.Length -eq 120) ("len=" + $r2.Payload.Length)
    Check 'B frame 2 payload byte-identical (all 120B)' ([bool](($payload2.Length -eq $r2.Payload.Length) -and ((Compare-Object -ReferenceObject $payload2 -DifferenceObject $r2.Payload -SyncWindow 0 | Measure-Object).Count -eq 0))) ''
    Check 'B frame 2 fnv1a64 matches sender' ((Get-Fnv1a64Hex -Data $r2.Payload) -eq (Get-Fnv1a64Hex -Data $payload2)) (Get-Fnv1a64Hex -Data $r2.Payload)
}
Check 'no-route/self/unknown-flag frames not delivered to B' (-not ($receivedB | Where-Object { $_.Seq -eq 2 -or $_.Seq -eq 3 -or $_.Seq -eq 90 })) ''

Check 'peer A received 1 frame' ($receivedA.Count -eq 1) ("count=" + $receivedA.Count)
if ($receivedA.Count -ge 1) {
    $ra = $receivedA[0]
    Check 'A frame is seq=5 (reverse direction)' ($ra.Seq -eq 5) ("seq=" + $ra.Seq)
    Check 'A frame dst_peer=101 preserved' ($ra.DstPeer -eq $peerIdA) ("dst=" + $ra.DstPeer)
    Check 'A frame src_peer filled by relay = 202' ($ra.SrcPeer -eq $peerIdB) ("src=" + $ra.SrcPeer)
    Check 'A frame payload byte-identical 8B' ([bool](($payload3.Length -eq $ra.Payload.Length) -and ((Compare-Object -ReferenceObject $payload3 -DifferenceObject $ra.Payload -SyncWindow 0 | Measure-Object).Count -eq 0))) ("len=" + $ra.Payload.Length)
}

# ---------------------------------------------------------------- stop and read summary
Set-Content -LiteralPath $stopFile -Value 'stop' -Encoding ASCII
$waited = $proc.WaitForExit(8000)
if (-not $waited) { try { $proc.Kill() } catch { } }
$null = $proc.WaitForExit(2000)
$exitCode = $proc.ExitCode
$clockStop = Get-Date
$stdout = $stdoutTask.Result
$stderr = $stderrTask.Result
Set-Content -LiteralPath (Join-Path $outDir 'exit.txt') -Value ("exitcode={0}" -f $exitCode) -Encoding ASCII
Set-Content -LiteralPath $relayOut -Value $stdout -Encoding UTF8
Set-Content -LiteralPath $relayErr -Value $stderr -Encoding UTF8

Check 'relay exited 0 on stop-file' ($exitCode -eq 0) ("exit=" + $exitCode)
Check 'relay stdout path covered (listening banner)' ($stdout -match 'listening on') ''
Check 'relay stderr empty on a clean run' ([string]::IsNullOrWhiteSpace($stderr)) $stderr.Trim()

$summaryPath = Join-Path $outDir 'relay-summary.txt'
$logPath = Join-Path $outDir 'relay-log.txt'
$summaryOk = Test-Path -LiteralPath $summaryPath
Check 'relay-summary.txt exists' $summaryOk ''
$summaryText = ''
if ($summaryOk) { $summaryText = [IO.File]::ReadAllText($summaryPath) }

function Get-Counter {
    param([string]$Text, [string]$Name)
    # The summary intentionally appends an explanation after some numbers
    # ("no sender : 0 (unregistered source, dropped ...)"), so the match must not require the
    # number to end the line - otherwise three counters read as -1 and the check fails for the
    # wrong reason.
    $m = [regex]::Match($Text, ('(?m)^{0}\s*:\s*(\d+)' -f [regex]::Escape($Name)))
    if ($m.Success) { return [int]$m.Groups[1].Value }
    return -1
}

# Per-category expectations that do not depend on how many registrations survived: the
# fixture sends exactly 6 DATA frames (5 from A, 1 reverse from B), 5 malformed datagrams, 1
# unknown-flag frame, 1 5000-byte datagram and 1 frame from an unregistered socket. Registration
# loss is measured, not asserted as ">= 5" (audit round 2, M-2).
$expectForwardRequests = 6
$expectBadEnvelope = 6
$expectUnknownFlags = 1
$expectForwarded = 3
$expectForwardBytes = 136
$expectNoRoute = 1
$expectSelfDrop = 1
$expectNoSender = 1
# The fixture sends each registration 3 times for A and B, plus 2 extra refreshes before the
# frames A sends and 2 more before B's reverse frame: 3+3+2+2 = 10 (audit round 2, M-2: this is
# asserted as an exact count instead of being divided by whichever number the Relay happened to
# count, which made the "PASS (N/N)" line self-referential).
$expectRegisters = 10

if ($summaryOk) {
    $dCount = Get-Counter $summaryText 'datagrams'
    $rCount = Get-Counter $summaryText 'registers'
    $fReq = Get-Counter $summaryText 'forward requests'
    $bEnv = Get-Counter $summaryText 'bad envelope'
    $uFlags = Get-Counter $summaryText 'unknown flags'
    $lostRegs = $expectRegisters - $rCount
    Write-Host ("  [info] registrations sent {0}, counted {1}, lost {2}" -f $expectRegisters, $rCount, $lostRegs)

    Check 'forward requests = 6 (5 from A + 1 reverse from B)' ($fReq -eq $expectForwardRequests) ("got=" + $fReq)
    Check 'bad envelope = 6 (all five reject paths + the 5000B frame)' ($bEnv -eq $expectBadEnvelope) ("got=" + $bEnv)
    Check 'unknown flags = 1' ($uFlags -eq $expectUnknownFlags) ("got=" + $uFlags)
    Check 'no sender = 1 (unregistered socket dropped fail-closed)' ((Get-Counter $summaryText 'no sender') -eq $expectNoSender) ("got=" + (Get-Counter $summaryText 'no sender'))
    Check 'registers counted = 10 (exact; loses are visible, not tolerated)' ($rCount -eq $expectRegisters) ("got=" + $rCount)
    Check 'datagrams = registers + 6 + 6 + 1' ($dCount -eq ($rCount + $expectForwardRequests + $expectBadEnvelope + $expectUnknownFlags)) ("{0} = {1} + 6 + 6 + 1" -f $dCount, $rCount)
    Check 'datagram identity line present and ==' ($summaryText -match '(?m)^datagram identity\s*:\s*datagrams ==') ''
    Check 'control frames = registers + 1' ((Get-Counter $summaryText 'control frames') -eq ($rCount + 1)) ("got=" + (Get-Counter $summaryText 'control frames'))
    Check 'peers seen = 2' ((Get-Counter $summaryText 'peers seen') -eq 2) ("got=" + (Get-Counter $summaryText 'peers seen'))
    Check 'forwarded = 3' ((Get-Counter $summaryText 'forwarded') -eq $expectForwarded) ("got=" + (Get-Counter $summaryText 'forwarded'))
    Check 'forward bytes = 136' ((Get-Counter $summaryText 'forward bytes') -eq $expectForwardBytes) ("got=" + (Get-Counter $summaryText 'forward bytes'))
    Check 'forward fail = 0' ((Get-Counter $summaryText 'forward fail') -eq 0) ''
    Check 'no route = 1' ((Get-Counter $summaryText 'no route') -eq $expectNoRoute) ("got=" + (Get-Counter $summaryText 'no route'))
    Check 'self drop = 1' ((Get-Counter $summaryText 'self drop') -eq $expectSelfDrop) ("got=" + (Get-Counter $summaryText 'self drop'))
    Check 'oversize = 0 (65535 buffer cannot overflow on IPv4 UDP)' ((Get-Counter $summaryText 'oversize') -eq 0) ("got=" + (Get-Counter $summaryText 'oversize'))
    Check 'fatal = none' ($summaryText -match '(?m)^fatal\s*:\s*none\s*$') ''
    Check 'reconciliation ==' ($summaryText -match '(?m)^reconciliation\s*:.*\s==\s') ''
    Check 'summary states plaintext (no encryption)' ($summaryText -match 'sees PLAINTEXT') ''
    # Attribution identity (audit round 2, M-2): the sum of the five terminal outcomes must equal
    # the number of frames that entered the forwarding stage, not merely "some number <= it".
    $fwdOut = (Get-Counter $summaryText 'forwarded')
    $nrOut = (Get-Counter $summaryText 'no route')
    $sdOut = (Get-Counter $summaryText 'self drop')
    $ffOut = (Get-Counter $summaryText 'forward fail')
    $nsOut = (Get-Counter $summaryText 'no sender')
    Check 'attribution closes: forwarded+no_route+self_drop+fail+no_sender == forward requests' (($fwdOut + $nrOut + $sdOut + $ffOut + $nsOut) -eq $fReq) ("{0}+{1}+{2}+{3}+{4} vs {5}" -f $fwdOut, $nrOut, $sdOut, $ffOut, $nsOut, $fReq)

    # Runtime: the summary's own elapsed time must agree with the wall clock this script saw.
    $mElapsed = [regex]::Match($summaryText, 'for ([0-9.]+) s')
    $measured = ($clockStop - $clockStart).TotalSeconds
    $reported = if ($mElapsed.Success) { [double]::Parse($mElapsed.Groups[1].Value, [Globalization.CultureInfo]::InvariantCulture) } else { -1 }
    Check 'summary runtime agrees with wall clock (+-3s)' ([bool]($reported -ge 0 -and [math]::Abs($reported - $measured) -le 3)) ("reported={0:N1}s measured={1:N1}s" -f $reported, $measured)
}

# ---------------------------------------------------------------- relay log
$logOk = Test-Path -LiteralPath $logPath
Check 'relay-log.txt exists' $logOk ''
$forwardLines = @()
if ($logOk) {
    $forwardLines = @([IO.File]::ReadAllLines($logPath) | Where-Object { $_ -match '\bforward seq=' })
}
Check 'relay-log has 3 forward lines' ($forwardLines.Count -eq 3) ("count=" + $forwardLines.Count)

function Get-LogField {
    param([string]$Line, [string]$Name)
    $m = [regex]::Match($Line, ('{0}=(\S+)' -f [regex]::Escape($Name)))
    if ($m.Success) { return $m.Groups[1].Value }
    return ''
}

if ($forwardLines.Count -ge 2) {
    $l1 = $forwardLines | Where-Object { (Get-LogField $_ 'seq') -eq '1' } | Select-Object -First 1
    Check 'log has forward for seq=1' ([bool]$l1) ''
    if ($l1) {
        Check 'log seq=1 hash matches sender' ((Get-LogField $l1 'hash') -eq (Get-Fnv1a64Hex -Data $payload1)) ((Get-LogField $l1 'hash'))
        Check 'log seq=1 len=8' ((Get-LogField $l1 'len') -eq '8') (Get-LogField $l1 'len')
        Check 'log seq=1 head matches sender' ((Get-LogField $l1 'head') -eq '17320000ffff4fac') (Get-LogField $l1 'head')
        Check 'log seq=1 src_peer=101' ((Get-LogField $l1 'src_peer') -eq '101') (Get-LogField $l1 'src_peer')
    }
}
if ($forwardLines.Count -ge 3) {
    $l2 = $forwardLines | Where-Object { (Get-LogField $_ 'seq') -eq '4' } | Select-Object -First 1
    Check 'log has forward for seq=4' ([bool]$l2) ''
    if ($l2) {
        Check 'log seq=4 hash matches sender' ((Get-LogField $l2 'hash') -eq (Get-Fnv1a64Hex -Data $payload2)) (Get-LogField $l2 'hash')
        Check 'log seq=4 len=120' ((Get-LogField $l2 'len') -eq '120') (Get-LogField $l2 'len')
    }
    $l3 = $forwardLines | Where-Object { (Get-LogField $_ 'seq') -eq '5' } | Select-Object -First 1
    Check 'log has forward for seq=5 (reverse direction)' ([bool]$l3) ''
    if ($l3) {
        Check 'log seq=5 src_peer=202 dst_peer=101' (((Get-LogField $l3 'src_peer') -eq '202') -and ((Get-LogField $l3 'dst_peer') -eq '101')) ("src=" + (Get-LogField $l3 'src_peer') + " dst=" + (Get-LogField $l3 'dst_peer'))
        Check 'log seq=5 hash matches sender' ((Get-LogField $l3 'hash') -eq (Get-Fnv1a64Hex -Data $payload3)) (Get-LogField $l3 'hash')
    }
}

if ($logOk) {
    $all = [IO.File]::ReadAllLines($logPath)
    Check 'log records no-route for seq=2' (@($all | Where-Object { $_ -match 'no-route.*seq=2' }).Count -eq 1) ''
    Check 'log records self-drop for seq=3' (@($all | Where-Object { $_ -match 'self-drop.*seq=3' }).Count -eq 1) ''
    Check 'log records too-short rejection' (@($all | Where-Object { $_ -match 'reject.*kind=too-short' }).Count -eq 1) ''
    Check 'log records bad-magic rejection' (@($all | Where-Object { $_ -match 'reject.*kind=bad-magic' }).Count -eq 1) ''
    Check 'log records bad-version rejection' (@($all | Where-Object { $_ -match 'reject.*kind=bad-version' }).Count -eq 1) ''
    Check 'log records payload-too-large rejection (2: crafted + the 5000B frame)' (@($all | Where-Object { $_ -match 'reject.*kind=payload-too-large' }).Count -eq 2) ''
    Check 'log records truncated rejection' (@($all | Where-Object { $_ -match 'reject.*kind=truncated' }).Count -eq 1) ''
    Check 'log records unknown-flags control frame' (@($all | Where-Object { $_ -match 'reject unknown-flags=0x02' }).Count -eq 1) ''
    Check 'log contains no forward for seq=2, 3 or 90' (-not (@($all | Where-Object { $_ -match '\bforward seq=(2|3|90)\b' }).Count -gt 0)) ''
}

try { $peerA.Close() } catch { }
try { $peerB.Close() } catch { }

# ---------------------------------------------------------------- verdict
# The denominator is a literal, not $script:Checks (audit round 2, M-2): printing
# "PASS (N/N)" from the counter's own value makes the line self-referential and hides a suite
# that silently skipped its guarded block.
$expectChecks = 68
$verdict = if ($script:Failures.Count -eq 0 -and $script:Checks -eq $expectChecks) {
    "F3B-RELAY-SELFTEST: PASS ($script:Checks/$expectChecks)"
} elseif ($script:Failures.Count -eq 0) {
    "F3B-RELAY-SELFTEST: FAIL (clean but $($script:Checks) of $expectChecks checks ran)"
} else {
    "F3B-RELAY-SELFTEST: FAIL ($($script:Failures.Count) of $script:Checks failed)"
}
$report = New-Object System.Collections.ArrayList
[void]$report.Add($verdict)
[void]$report.Add("evidence label: simulated data-plane peer on loopback; NOT a real two-machine test,")
[void]$report.Add("               NOT injection into a game process, NOT a multiplayer validation.")
[void]$report.Add("evidence dir : $outDir")
[void]$report.Add("relay exe    : $RelayExe")
[void]$report.Add(("relay sha256 : {0}" -f (Get-FileHash -LiteralPath $RelayExe -Algorithm SHA256).Hash))
[void]$report.Add(("relay bytes  : {0}" -f (Get-Item -LiteralPath $RelayExe).Length))
[void]$report.Add("script       : $PSCommandPath")
[void]$report.Add(("script sha256: {0}" -f (Get-FileHash -LiteralPath $PSCommandPath -Algorithm SHA256).Hash))
[void]$report.Add("peer A       : $addrA  (peer id $peerIdA)")
[void]$report.Add("peer B       : $addrB  (peer id $peerIdB)")
[void]$report.Add(("registrations sent: {0}" -f $script:RegistrationsSent))
[void]$report.Add(("payload1 fnv1a64 : {0}" -f (Get-Fnv1a64Hex -Data $payload1)))
[void]$report.Add(("payload2 fnv1a64 : {0}" -f (Get-Fnv1a64Hex -Data $payload2)))
[void]$report.Add(("payload3 fnv1a64 : {0}" -f (Get-Fnv1a64Hex -Data $payload3)))
if ($script:Failures.Count -gt 0) {
    [void]$report.Add('failed checks:')
    foreach ($f in $script:Failures) { [void]$report.Add("  - $f") }
}
Set-Content -LiteralPath (Join-Path $outDir 'result.txt') -Value ($report -join "`r`n") -Encoding UTF8

Write-Host ""
Write-Host $verdict -ForegroundColor $(if ($script:Failures.Count -eq 0 -and $script:Checks -eq $expectChecks) { 'Green' } else { 'Red' })
Write-Host ("evidence: {0}" -f $outDir)
if ($script:Failures.Count -eq 0 -and $script:Checks -eq $expectChecks) { exit 0 } else { exit 1 }
