# run-f3d-pressure-selftest.ps1 - F3-D: burst pressure against the layered counters.
#
# Design v0.3 section 5 asks whether the Agent/Relay accounting still closes when the input
# arrives far faster than the steady state. The input rate of interest comes from S5: the real
# client busy-polls WSARecvFrom at roughly 1.6M calls/s on its 62056 socket. That number is a
# property of the GAME's socket inside the game process, and this driver cannot reproduce it:
# it has no game and no Hook. What it CAN do, and what the accounting question actually needs,
# is push a tight loopback burst and check that
#   (a) loss stays visible - the counters must show it, never silently absorb it,
#   (b) the identity equations still close under loss,
#   (c) the processes keep serving and exit cleanly.
#
# This is a LOOPBACK prototype test. Nothing enters a game process. It does NOT measure the
# Hook detour's cost at 1.6M/s - that was checked mechanically in F2/S4 (zero blocking, no
# allocation on the hot path) and stays an M0-B question with the real client.
#
# Exit codes: 0 PASS, 1 assertion failed, 2 precondition failed.

param(
    [int]$AgentFrames = 40000,
    [int]$RelayFrames = 40000
)

$ErrorActionPreference = 'Continue'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$agentExe = Join-Path $here 'civlink-agent.exe'
$relayExe = Join-Path $here 'relay\target\release\civlink-relay.exe'
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$outRoot = 'C:\Users\dd\Desktop\injciv6-v0.3.3\M0A\captures'
$out = Join-Path $outRoot ("F3D-pressure-selftest-$stamp")
$fail = 0

function Check([string]$name, [bool]$ok, [string]$detail) {
    if ($ok) {
        Write-Host "[PASS] $name"
    } else {
        Write-Host "[FAIL] $name -> $detail"
        $script:fail++
    }
}

function Grab([string]$text, [string]$pattern) {
    $m = [regex]::Match($text, $pattern)
    if ($m.Success) { return $m.Groups[1].Value }
    return ''
}

foreach ($p in @($agentExe, $relayExe)) {
    if (-not (Test-Path $p)) {
        Write-Host "[!] missing $p (build it first)"
        exit 2
    }
}
foreach ($port in @(34718, 21348, 34720, 62056)) {
    $busy = Get-NetUDPEndpoint -LocalPort $port -ErrorAction SilentlyContinue
    if ($busy) {
        Write-Host "[!] udp:$port is already in use by pid=$($busy.OwningProcess) - stop it first"
        exit 2
    }
}

New-Item -ItemType Directory -Force -Path $out | Out-Null

# Tight-loop senders. PowerShell's own loop cannot come close to saturating a UDP socket, so the
# burst is sent from compiled C#; the point is to create real pressure, not to benchmark PS.
Add-Type -TypeDefinition @'
using System;
using System.Net;
using System.Net.Sockets;

public static class CivLinkBurst
{
    private static void WriteU32(byte[] b, int o, uint v)
    {
        b[o] = (byte)(v & 0xFF); b[o + 1] = (byte)((v >> 8) & 0xFF);
        b[o + 2] = (byte)((v >> 16) & 0xFF); b[o + 3] = (byte)((v >> 24) & 0xFF);
    }
    private static void WriteU64(byte[] b, int o, ulong v)
    {
        for (int i = 0; i < 8; i++) b[o + i] = (byte)((v >> (8 * i)) & 0xFF);
    }
    private static void WriteBe16(byte[] b, int o, int v)
    {
        b[o] = (byte)((v >> 8) & 0xFF); b[o + 1] = (byte)(v & 0xFF);
    }

    // CVLH2 frame exactly as the F1/F2/F3 drivers build it: 42 byte header + payload.
    // wirePort is where the datagram goes (the Agent's control port); hdrDstPort is what the
    // frame CLAIMS as the game destination. They differ on purpose: the forward stage only acts
    // on frames whose header destination is 62056.
    public static long SendCvlh2(int count, string dstIp, int wirePort, int hdrDstPort, int payloadLen, int startSeq)
    {
        IPEndPoint ep = new IPEndPoint(IPAddress.Parse(dstIp), wirePort);
        byte[] src = IPAddress.Parse("127.0.0.1").GetAddressBytes();
        byte[] dst = IPAddress.Parse(dstIp).GetAddressBytes();
        byte[] buf = new byte[42 + payloadLen];
        buf[0] = 0x43; buf[1] = 0x56; buf[2] = 0x4C; buf[3] = 0x48;
        buf[4] = 2; buf[5] = 0;
        WriteU64(buf, 10, 1);          // session id
        WriteU32(buf, 18, 2);          // logical socket id
        WriteU32(buf, 22, 1);          // socket generation
        buf[26] = 2;                   // AF_INET
        Array.Copy(src, 0, buf, 27, 4);
        WriteBe16(buf, 31, 21345);     // src port, network order
        Array.Copy(dst, 0, buf, 33, 4);
        WriteBe16(buf, 37, hdrDstPort); // dst port, network order
        buf[39] = 0x21;                // OBSERVED | VIA_WSASENDTO
        buf[40] = (byte)(payloadLen & 0xFF);
        buf[41] = (byte)((payloadLen >> 8) & 0xFF);
        for (int i = 0; i < payloadLen; i++) buf[42 + i] = (byte)(0x40 + (i & 0x3F));

        long sent = 0;
        using (Socket s = new Socket(AddressFamily.InterNetwork, SocketType.Dgram, ProtocolType.Udp))
        {
            for (int i = 0; i < count; i++)
            {
                WriteU32(buf, 6, (uint)(startSeq + i));
                buf[42] = (byte)((startSeq + i) & 0xFF);
                try { s.SendTo(buf, ep); sent++; }
                catch (SocketException) { /* counted by absence: sent stops growing */ }
            }
        }
        return sent;
    }

    // CVLR envelope: 20 byte header + payload, DATA frames addressed to a fixed peer.
    public static long SendRelay(int count, string dstIp, int dstPort, uint dstPeer, uint srcPeer, int payloadLen)
    {
        IPEndPoint ep = new IPEndPoint(IPAddress.Parse(dstIp), dstPort);
        byte[] buf = new byte[20 + payloadLen];
        buf[0] = 0x43; buf[1] = 0x56; buf[2] = 0x4C; buf[3] = 0x52;  // 'CVLR'
        buf[4] = 1;                                                  // version
        buf[5] = 0;                                                  // DATA
        WriteU32(buf, 6, dstPeer);
        WriteU32(buf, 10, srcPeer);
        // payload_len is u16 LITTLE endian in the CVLR header (the whole header is little endian);
        // writing it big endian makes the Relay read a huge length and reject every frame as
        // payload-too-large.
        buf[18] = (byte)(payloadLen & 0xFF);
        buf[19] = (byte)((payloadLen >> 8) & 0xFF);
        for (int i = 0; i < payloadLen; i++) buf[20 + i] = (byte)(0x60 + (i & 0x1F));

        long sent = 0;
        using (Socket s = new Socket(AddressFamily.InterNetwork, SocketType.Dgram, ProtocolType.Udp))
        {
            // Register THIS socket as peer srcPeer before bursting. The Relay resolves the
            // sender by the datagram's source address and fails closed for unregistered
            // sources - without this registration every burst frame lands in `no sender` and
            // the forwarding path under load would never be exercised. (A first draft of this
            // driver did exactly that and still passed, which is why the assertion set below
            // now demands forwarded > 0.)
            byte[] reg = new byte[20];
            reg[0] = 0x43; reg[1] = 0x56; reg[2] = 0x4C; reg[3] = 0x52;
            reg[4] = 1; reg[5] = 1;                     // version 1, REGISTER
            WriteU32(reg, 6, srcPeer);                  // the id this address gets registered as
            WriteU32(reg, 10, 0);
            reg[18] = 0; reg[19] = 0;
            for (int i = 0; i < 3; i++)
            {
                try { s.SendTo(reg, ep); } catch (SocketException) { }
                System.Threading.Thread.Sleep(20);
            }
            for (int i = 0; i < count; i++)
            {
                WriteU32(buf, 14, (uint)(i + 1));
                buf[20] = (byte)(i & 0xFF);
                try { s.SendTo(buf, ep); sent++; }
                catch (SocketException) { }
            }
        }
        return sent;
    }
}
'@ -ErrorAction Stop

# ---------------------------------------------------------------- part 1: Agent under burst
Write-Host ''
Write-Host '=== F3-D part 1: Agent ingest under a tight burst ==='
$peerPort = 21348
$aStop = Join-Path $out 'agent-stop'
$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = $agentExe
$psi.Arguments = @('--listen-seconds','120','--out-dir',('"' + $out + '"'),'--stop-file',('"' + $aStop + '"'),
                   '--forward-to',"127.0.0.1:$peerPort",'--forward-listen',"$peerPort",
                   '--simulate-datapath','--bind-ip','127.0.0.1','--loopback-selftest','--quiet') -join ' '
$psi.UseShellExecute = $false
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
$psi.CreateNoWindow = $true
$psi.WorkingDirectory = $here
$aproc = New-Object System.Diagnostics.Process
$aproc.StartInfo = $psi
[void]$aproc.Start()
$aout = $aproc.StandardOutput.ReadToEndAsync()
$aerr = $aproc.StandardError.ReadToEndAsync()

$bound = $false
for ($i = 0; $i -lt 60; $i++) {
    Start-Sleep -Milliseconds 100
    if (Get-NetUDPEndpoint -LocalPort 34718 -ErrorAction SilentlyContinue) { $bound = $true; break }
}
if (-not $bound) {
    Write-Host '[!] agent never bound 127.0.0.1:34718'
    if (-not $aproc.HasExited) { $aproc.Kill() }
    exit 2
}
$agentOn62056 = @(Get-NetUDPEndpoint -LocalPort 62056 -ErrorAction SilentlyContinue | Where-Object { $_.OwningProcess -eq $aproc.Id })
Check 'agent does not bind UDP :62056 under load' ($agentOn62056.Count -eq 0) "owned=$($agentOn62056.Count)"

Write-Host "[*] bursting $AgentFrames CVLH2 frames at 127.0.0.1:34718"
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$agentSent = [CivLinkBurst]::SendCvlh2($AgentFrames, '127.0.0.1', 34718, 62056, 8, 1)
$sw.Stop()
$sendSeconds = $sw.Elapsed.TotalSeconds
$sendRate = if ($sendSeconds -gt 0) { [int]($agentSent / $sendSeconds) } else { 0 }
Write-Host ("[*] sender: {0} datagrams in {1:N3} s ({2:N0} /s) - sender side only" -f $agentSent, $sendSeconds, $sendRate)

Start-Sleep -Milliseconds 1500
New-Item -ItemType File -Force -Path $aStop | Out-Null
$ok = $false
for ($i = 0; $i -lt 300; $i++) { if ($aproc.HasExited) { $ok = $true; break }; Start-Sleep -Milliseconds 100 }
if (-not $ok) { Write-Host '[!] agent did not exit on the stop file'; $aproc.Kill(); exit 1 }
$aproc.WaitForExit()
if ($aout) { $aout.Result | Out-File -FilePath (Join-Path $out 'agent-console.txt') -Encoding utf8 }
if ($aerr) { $aerr.Result | Out-File -FilePath (Join-Path $out 'agent-stderr.txt') -Encoding utf8 }
$agentExit = $aproc.ExitCode
"agent exit=$agentExit frames=$AgentFrames senderRate=$sendRate/s" | Out-File -FilePath (Join-Path $out 'agent-exit.txt') -Encoding utf8
Check 'agent exited 0 under burst' ($agentExit -eq 0) "exit=$agentExit"

$asum = Join-Path $out 'summary.txt'
if (-not (Test-Path $asum)) { Write-Host '[!] no agent summary.txt'; exit 1 }
$atext = [IO.File]::ReadAllText($asum, [Text.Encoding]::UTF8)

$datagrams = Grab $atext 'datagrams\s+:\s+(\d+)'
$received = Grab $atext 'received frames\s+:\s+(\d+) \(processed (\d+), rejected (\d+)\)'
$processed = Grab $atext 'received frames\s+:\s+\d+ \(processed (\d+), rejected (\d+)\)'
$rejected = Grab $atext 'received frames\s+:\s+\d+ \(processed \d+, rejected (\d+)\)'
$recvTotal = Grab $atext 'received frames\s+:\s+(\d+) \(processed'
$gaps = Grab $atext 'seq gaps=(\d+)'
$missing = Grab $atext 'missing_frames=(\d+)'
$firstSeq = Grab $atext 'first_seq=Some\((\d+)\)'
$lastSeq = Grab $atext 'last_seq=Some\((\d+)\)'
$framesA = Grab $atext 'frames seen\s+:\s+(\d+) \(accepted non-discovery'
$forwarded = Grab $atext 'forwarded\s+:\s+(\d+) \(payload bytes'
$ffail = Grab $atext 'forward fail\s+:\s+(\d+)'
$skipDp = Grab $atext 'skip not datapath:\s+(\d+)'
$skipTbl = Grab $atext 'skip key table\s+:\s+(\d+)'
$peerRecv = Grab $atext 'payloads recv\s+:\s+(\d+)'

# Numeric coercion: every Grab returns "" when the pattern misses, and "" must never compare
# equal to 0 by accident, so parse to int and treat a miss as -1.
function Num([string]$v) { if ($v -eq '') { return -1 } else { return [long]$v } }
$datagramsN = Num $datagrams
$recvN = Num $recvTotal
$procN = Num $processed
$rejN = Num $rejected
$gapsN = Num $gaps
$missingN = Num $missing
$framesN = Num $framesA
$fwdN = Num $forwarded
$ffailN = Num $ffail
$skipDpN = Num $skipDp
$skipTblN = Num $skipTbl
$peerN = Num $peerRecv

Write-Host ("[*] agent: datagrams={0} received={1} (processed {2}, rejected {3}) frames_seen={4} forwarded={5} held_back(dp={6} table={7} fail={8}) peer={9}" -f `
    $datagramsN, $recvN, $procN, $rejN, $framesN, $fwdN, $skipDpN, $skipTblN, $ffailN, $peerN)

# The invariant that matters: whatever arrived, the classification must add up. Loss is allowed
# and expected here - what is not allowed is loss that the counters cannot see.
Check 'agent: received == processed + rejected' ($recvN -ge 0 -and $recvN -eq ($procN + $rejN)) `
    "received=$recvN processed=$procN rejected=$rejN"
Check 'agent: datagrams >= received frames (no phantom frames)' ($datagramsN -ge $recvN -and $recvN -ge 0) `
    "datagrams=$datagramsN received=$recvN"
Check 'agent: frames_seen == received (every decoded frame reaches the forward stage)' ($framesN -eq $recvN) `
    "frames_seen=$framesN received=$recvN"
Check 'agent: forwarded + skips + fail == frames_seen' `
    ($framesN -ge 0 -and ($fwdN + $skipDpN + $skipTblN + $ffailN) -eq $framesN) `
    "forwarded=$fwdN skipDp=$skipDpN skipTbl=$skipTblN fail=$ffailN frames=$framesN"
Check 'agent: peer payloads recv <= forwarded (loopback may drop, never invent)' `
    ($peerN -ge 0 -and $peerN -le $fwdN) "peer=$peerN forwarded=$fwdN"
Check 'agent: seq accounting is self-consistent (frames + missing == last - first + 1)' `
    ((Num $firstSeq) -ge 1 -and (Num $lastSeq) -ge (Num $firstSeq) -and `
     ($recvN + $missingN) -eq ((Num $lastSeq) - (Num $firstSeq) + 1)) `
    "frames=$recvN missing=$missingN first=$(Num $firstSeq) last=$(Num $lastSeq)"
# A "gap" is one break in the sequence; "missing_frames" is how many sequence numbers are
# absent. One burst losing 24 consecutive frames produces 1 gap and 24 missing, so they are
# deliberately NOT asserted equal - that was a wrong assertion in the first draft of this
# driver, not a product defect. What must hold: zero gaps iff zero missing, and gaps can never
# exceed missing (every gap skips at least one number).
Check 'agent: gaps and missing_frames agree in kind (0 gaps <=> 0 missing, gaps <= missing)' `
    ((($gapsN -eq 0) -eq ($missingN -eq 0)) -and $gapsN -ge 0 -and $missingN -ge 0 -and $gapsN -le $missingN) `
    "gaps=$gapsN missing=$missingN"
Check 'agent: loss is reported (datagrams vs frames actually sent)' `
    ($datagramsN -le $agentSent) "datagrams=$datagramsN sent=$agentSent"

$lostA = $agentSent - $datagramsN
Write-Host ("[*] agent ingest: {0} sent, {1} seen by the socket, {2} lost in transit ({3:N2}%)" -f `
    $agentSent, $datagramsN, $lostA, (100.0 * $lostA / [Math]::Max($agentSent, 1)))
$ingestRate = if ($sendSeconds -gt 0) { [int]($recvN / $sendSeconds) } else { 0 }
Write-Host ("[*] agent decode+forward: {0:N0} frames/s sustained during the burst" -f $ingestRate)
"part1 agentFrames=$AgentFrames sent=$agentSent datagrams=$datagramsN received=$recvN lost=$lostA senderRate=$sendRate ingestRate=$ingestRate" |
    Out-File -FilePath (Join-Path $out 'agent-pressure.txt') -Encoding utf8

# ---------------------------------------------------------------- part 2: Relay under burst
Write-Host ''
Write-Host '=== F3-D part 2: Relay routing under a tight burst ==='
$rStop = Join-Path $out 'relay-stop'
$rpsi = New-Object System.Diagnostics.ProcessStartInfo
$rpsi.FileName = $relayExe
$rpsi.Arguments = @('--listen','127.0.0.1:34720','--listen-seconds','120','--out-dir',('"' + $out + '"'),
                    '--stop-file',('"' + $rStop + '"')) -join ' '
$rpsi.UseShellExecute = $false
$rpsi.RedirectStandardOutput = $true
$rpsi.RedirectStandardError = $true
$rpsi.CreateNoWindow = $true
$rpsi.WorkingDirectory = $out
$rproc = New-Object System.Diagnostics.Process
$rproc.StartInfo = $rpsi
[void]$rproc.Start()
$rout = $rproc.StandardOutput.ReadToEndAsync()
$rerr = $rproc.StandardError.ReadToEndAsync()

$rbound = $false
for ($i = 0; $i -lt 60; $i++) {
    Start-Sleep -Milliseconds 100
    if (Get-NetUDPEndpoint -LocalPort 34720 -ErrorAction SilentlyContinue) { $rbound = $true; break }
}
if (-not $rbound) { Write-Host '[!] relay never bound 127.0.0.1:34720'; if (-not $rproc.HasExited) { $rproc.Kill() }; exit 2 }

# Register the sink peer once, then burst DATA frames at it. The sink is a plain socket that
# only drains; the assertion is about the Relay's own accounting, not about the sink.
$sink = [System.Net.Sockets.UdpClient]::new(21349)
$sink.Client.ReceiveTimeout = 200
$reg = [byte[]]::new(20)
$reg[0] = 0x43; $reg[1] = 0x56; $reg[2] = 0x4C; $reg[3] = 0x52
$reg[4] = 1; $reg[5] = 1
[BitConverter]::GetBytes([uint32]777).CopyTo($reg, 6)
[BitConverter]::GetBytes([uint32]0).CopyTo($reg, 10)
[BitConverter]::GetBytes([uint16]0).CopyTo($reg, 18)
$relayEp = [System.Net.IPEndPoint]::new([System.Net.IPAddress]::Parse('127.0.0.1'), 34720)
for ($i = 0; $i -lt 5; $i++) { [void]$sink.Send($reg, $reg.Length, $relayEp); Start-Sleep -Milliseconds 30 }

Write-Host "[*] bursting $RelayFrames CVLR envelopes at 127.0.0.1:34720 (dst_peer=777)"
$sw2 = [System.Diagnostics.Stopwatch]::StartNew()
$relaySent = [CivLinkBurst]::SendRelay($RelayFrames, '127.0.0.1', 34720, 777, 101, 12)
$sw2.Stop()
Write-Host ("[*] sender: {0} datagrams in {1:N3} s" -f $relaySent, $sw2.Elapsed.TotalSeconds)

# Drain whatever the sink got, in the background of the stop sequence.
$sinkGot = 0
$sinkBytes = 0
$buf = [byte[]]::new(4096)
$deadline = (Get-Date).AddSeconds(3)
while ((Get-Date) -lt $deadline) {
    try { $n = $sink.Client.Receive($buf); $sinkGot++; $sinkBytes += $n }
    catch { break }
}
$sink.Close()

New-Item -ItemType File -Force -Path $rStop | Out-Null
$rok = $false
for ($i = 0; $i -lt 300; $i++) { if ($rproc.HasExited) { $rok = $true; break }; Start-Sleep -Milliseconds 100 }
if (-not $rok) { Write-Host '[!] relay did not exit on the stop file'; $rproc.Kill(); exit 1 }
$rproc.WaitForExit()
if ($rout) { $rout.Result | Out-File -FilePath (Join-Path $out 'relay-console.txt') -Encoding utf8 }
if ($rerr) { $rerr.Result | Out-File -FilePath (Join-Path $out 'relay-stderr.txt') -Encoding utf8 }
$relayExit = $rproc.ExitCode
"relay exit=$relayExit sent=$relaySent sinkGot=$sinkGot sinkBytes=$sinkBytes" |
    Out-File -FilePath (Join-Path $out 'relay-exit.txt') -Encoding utf8
Check 'relay exited 0 under burst' ($relayExit -eq 0) "exit=$relayExit"

$rsum = Join-Path $out 'relay-summary.txt'
if (-not (Test-Path $rsum)) { Write-Host '[!] no relay-summary.txt'; exit 1 }
$rtext = [IO.File]::ReadAllText($rsum, [Text.Encoding]::UTF8)

$rDatagrams = Num (Grab $rtext 'datagrams\s+:\s+(\d+)')
$rRegs = Num (Grab $rtext 'registers\s+:\s+(\d+)')
$rReq = Num (Grab $rtext 'forward requests\s+:\s+(\d+)')
$rBad = Num (Grab $rtext 'bad envelope\s+:\s+(\d+)')
$rUnknown = Num (Grab $rtext 'unknown flags\s+:\s+(\d+)')
$rFwd = Num (Grab $rtext 'forwarded\s+:\s+(\d+)')
$rNoRoute = Num (Grab $rtext 'no route\s+:\s+(\d+)')
$rSelf = Num (Grab $rtext 'self drop\s+:\s+(\d+)')
$rFail = Num (Grab $rtext 'forward fail\s+:\s+(\d+)')
$rNoSender = Num (Grab $rtext 'no sender\s+:\s+(\d+)')
$rFatal = Grab $rtext 'fatal\s+:\s+(\S+)'

Write-Host ("[*] relay: datagrams={0} registers={1} requests={2} bad={3} unknown={4} forwarded={5} no_route={6} self={7} fail={8} no_sender={9} fatal={10}" -f `
    $rDatagrams, $rRegs, $rReq, $rBad, $rUnknown, $rFwd, $rNoRoute, $rSelf, $rFail, $rNoSender, $rFatal)

Check 'relay: datagrams == registers + requests + bad + unknown (identity closes)' `
    ($rDatagrams -ge 0 -and $rDatagrams -eq ($rRegs + $rReq + $rBad + $rUnknown)) `
    "datagrams=$rDatagrams regs=$rRegs req=$rReq bad=$rBad unknown=$rUnknown"
Check 'relay: forwarded + no_route + self + fail + no_sender == requests' `
    ($rReq -ge 0 -and ($rFwd + $rNoRoute + $rSelf + $rFail + $rNoSender) -eq $rReq) `
    "fwd=$rFwd no_route=$rNoRoute self=$rSelf fail=$rFail no_sender=$rNoSender req=$rReq"
Check 'relay: fatal is none (a burst is not an error)' ($rFatal -eq 'none') "fatal=$rFatal"
Check 'relay: datagrams <= sent + registrations (no invented datagrams)' `
    ($rDatagrams -le ($relaySent + $rRegs)) "datagrams=$rDatagrams sent=$relaySent regs=$rRegs"
Check 'relay: sink received <= forwarded' ($sinkGot -le $rFwd) "sink=$sinkGot forwarded=$rFwd"
# The first draft of this driver registered only the sink and left the burst socket
# unregistered, so every frame was dropped by the fail-closed sender check - and the suite
# still passed, because every assertion was an inequality. These two are the ones that make
# "the burst went through the forwarding path" a real claim rather than a green light.
Check 'relay: the burst reached the forwarding path (forwarded > 0)' ($rFwd -gt 0) "forwarded=$rFwd"
Check 'relay: no frame was dropped as unregistered (no sender == 0)' ($rNoSender -eq 0) "no_sender=$rNoSender"
Check 'relay: sink actually received payloads (sink > 0)' ($sinkGot -gt 0) "sink=$sinkGot"
Check 'relay: loss is reported honestly (summary says how much was kept)' `
    (($rFwd + $rNoSender + $rBad) -le $rDatagrams) "fwd=$rFwd no_sender=$rNoSender bad=$rBad datagrams=$rDatagrams"

$lostR = $relaySent - $rDatagrams
Write-Host ("[*] relay ingest: {0} sent, {1} seen by the socket, {2} lost in transit ({3:N2}%)" -f `
    $relaySent, $rDatagrams, $lostR, (100.0 * $lostR / [Math]::Max($relaySent, 1)))
$rRate = if ($sw2.Elapsed.TotalSeconds -gt 0) { [int]($rFwd / $sw2.Elapsed.TotalSeconds) } else { 0 }
Write-Host ("[*] relay forwarded {0:N0} frames/s during the burst" -f $rRate)
"part2 relayFrames=$RelayFrames sent=$relaySent datagrams=$rDatagrams forwarded=$rFwd sinkGot=$sinkGot rate=$rRate" |
    Out-File -FilePath (Join-Path $out 'relay-pressure.txt') -Encoding utf8

# ---------------------------------------------------------------- boundary + verdict
$boundary = @(
    'F3-D pressure self-test - boundary statement',
    'Scope: loopback only, no game process, no Hook, no second machine.',
    'What the burst proves: under input far above steady state the layered counters still close,',
    'and datagram loss stays visible (sent vs socket-seen vs forwarded are all reported separately).',
    'What it does NOT prove: the Hook detour cost at the real client''s ~1.6M recv/s. That path is',
    'inside the game process and was only checked mechanically (F2/S4: no blocking, no allocation).',
    'It also does not prove long-run stability: one burst per process, roughly a few seconds.',
    "Sender rate is a property of this test driver, not of the product: $sendRate /s."
) -join [Environment]::NewLine
$boundary | Out-File -FilePath (Join-Path $out 'boundary.txt') -Encoding utf8

Write-Host ''
if ($fail -eq 0) {
    Write-Host "F3D-PRESSURE-SELFTEST: PASS (evidence: $out)"
    exit 0
}
Write-Host "F3D-PRESSURE-SELFTEST: FAIL ($fail assertion(s), evidence: $out)"
exit 1
