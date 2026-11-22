# synthetic-host-responder.ps1
# Bounded synthetic room-advertisement responder for Civ6 LAN discovery.
# Authorized by REV-013-REVIEW.md section 4 (single-host synthetic response experiment).
#
# v2 (2026-11-13) RANGE-BIND AMENDMENT
#   Passive probing with the whole discovery range bound showed that this build of
#   the Civ6 client does NOT reliably send its 4-byte 8d e8 fc 70 request to 62900:
#   a single request arrived on UDP 62957 while all of 62900..62999 were bound and
#   listened to. A single-port (62900-only) responder therefore can never receive it
#   (this is the structural reason the earlier runs logged zero requests).
#   v2 binds the complete 62900..62999 discovery range and replies from the SAME
#   socket that received the request, so the reply's source port equals the port the
#   client targeted. Every REV-013 execution condition is preserved, and the reply
#   budget is made *more* conservative: at most one response per request burst.
#
# Behaviour (each item maps to a REV-013-REVIEW execution condition):
#   C1  Pre-check: refuse to start if ANY process already holds a UDP port in
#       62900..62999 (no SO_REUSEADDR, no force-kill; exact bind failure -> stop).
#   C2  Respond to at most $MaxResponses Civ6 discovery requests whose payload is
#       EXACTLY 8d e8 fc 70 and whose source address belongs to a local interface.
#       Each response sends exactly 22 pages, each page once. Requests that arrive
#       within one burst window ($BurstWindowMs) count as one scan and get one reply.
#   C3  Replies go only to the request's local source address + ephemeral port, sent
#       from the socket bound to the port the request targeted. All fields of every
#       request/response are logged (src/dst IP:port, port, interface index,
#       timestamps, page order, per-page SHA256).
#   C4  No route/metric/NIC/firewall/Steam change. No DLL injection.
#   C5  The personal room name at offset 24..45 of every page is replaced with a
#       fixed-length anonymous ASCII name (same byte length, padding unchanged);
#       change offsets, original fixture hashes and sent fixture hashes logged.
#   C6  After the last response the sockets keep passively recording datagrams
#       (second-phase handshake) without ever replying.
#   C7  Summary uses only the restricted phrasings from REV-013-REVIEW.
#
# Usage:
#   powershell -NoProfile -ExecutionPolicy Bypass -File synthetic-host-responder.ps1 `
#       -FixtureDir <dir with reply-01.bin..reply-22.bin> -OutDir <evidence dir>
#
# Optional:
#   -FirstPort / -LastPort   discovery range, default 62900 / 62999
#   -MaxResponses N          default 3   (total responses across the run)
#   -BurstWindowMs N         default 3000 (requests inside one window = one scan)
#   -ListenSeconds           default 600 (total listen cap)
#   -PostResponseSec         default 90  (passive capture after the last response)
#   -RoomName                default 'CivLink-Test-Room-2222' (exactly 22 ASCII bytes)
#
# v2.2 (2026-11-13) RECEIVE-ERROR ACCOUNTING AMENDMENT
#   E2B-SYNTHETIC-CLIENT-REVIEW.md section 3 found a residual defect: the generic
#   catch branch was still a bare `catch { break }`, so an unexpected receive error
#   looked exactly like "no more datagrams queued". v2.2 separates the two:
#     * expected would-block / timed-out / connection-reset -> counted as `drained`,
#       loop simply moves on (these are the normal empty-queue tick);
#     * anything else -> counted as `unexpected`, written to receive-errors.log with
#       exception type + message + port + timestamp, and the summary reports the count.
#   Nothing is swallowed silently any more: every caught exception leaves a trace.
#   `-InjectReceiveFault N` is a TEST-ONLY seam used by
#   test-responder-errorpath.ps1 to prove the unexpected path is logged and that the
#   script survives it; it is 0 (disabled) for all experimental runs.
#
# v2.3 (2026-11-13) SELECT-ERROR ACCOUNTING AMENDMENT
#   REV-014-REVIEW.md section 4 found a second defect of the same family: Socket.Select()
#   still had a bare `catch { continue }`, so a Select failure was indistinguishable from
#   "no socket became readable" -- the loop spun on and the run silently observed
#   nothing. The 9/9 errorpath regression did NOT cover this branch (it only exercises
#   ReceiveMessageFrom failures, 1 datagram at a time, so Select never fails there).
#   v2.3 separates Select errors the same way v2.2 separated receive errors:
#     * expected abort/closed (Interrupted, OperationAborted, ConnectionReset,
#       ConnectionAborted) -> counted in `select expected`, loop continues;
#     * anything else -> counted as `unexpected`, written to receive-errors.log with
#       kind=SelectException, and reported on its own summary line;
#     * every Select failure sleeps 20 ms before retrying, so a persistent failure
#       cannot turn the listen loop into a busy spin that hides itself.
#   `-InjectSelectFault N` is a TEST-ONLY seam for test-responder-errorpath.ps1; it is 0
#   (disabled) for all experimental runs, including P2.

[CmdletBinding()]
param(
    [int]$FirstPort = 62900,
    [int]$LastPort = 62999,
    [int]$MaxResponses = 3,
    [int]$BurstWindowMs = 3000,
    [int]$ListenSeconds = 600,
    [int]$PostResponseSec = 90,
    [string]$FixtureDir = '',
    [string]$OutDir = '',
    [string]$RoomName = 'CivLink-Test-Room-2222',
    [int]$InjectReceiveFault = 0,
    [int]$InjectSelectFault = 0
)

$ErrorActionPreference = 'Stop'
$ts = Get-Date -Format 'yyyyMMdd-HHmmss'

# ---------------------------------------------------------------- paths
if ($OutDir -eq '') { $OutDir = Join-Path $PSScriptRoot ('..\..\M0A\captures\E2B-synthetic-' + $ts) }
if ($FixtureDir -eq '') { $FixtureDir = Join-Path $PSScriptRoot '..\..\M0A\captures\E2A-H4-reply-20261113\reply-set' }
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$log = New-Object System.Collections.Generic.List[string]
function Say([string]$s) { $log.Add($s); Write-Host $s }

Say '=== synthetic-host-responder v2.3 (REV-013-REVIEW 4 range-bind; v2.2 recv-err; v2.3 select-err) ==='
Say ("start          : {0}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'))
Say ("out dir        : {0}" -f $OutDir)
Say ("fixture dir    : {0}" -f $FixtureDir)
Say ("listen range   : {0}..{1} ({2} ports)" -f $FirstPort, $LastPort, ($LastPort - $FirstPort + 1))
Say ("max responses  : {0} (burst window {1} ms)" -f $MaxResponses, $BurstWindowMs)
Say ("room name      : '{0}' ({1} bytes)" -f $RoomName, ([Text.Encoding]::ASCII.GetByteCount($RoomName)))

# ---------------------------------------------------------------- C5: fixtures
$pages = @()
for ($i = 1; $i -le 22; $i++) {
    $p = Join-Path $FixtureDir ('reply-{0:d2}.bin' -f $i)
    if (-not (Test-Path $p)) { throw "missing fixture $p" }
    $pages += ,([IO.File]::ReadAllBytes($p))
}
if ($pages.Count -ne 22) { throw 'expected exactly 22 fixture pages' }

$roomBytes = [Text.Encoding]::ASCII.GetBytes($RoomName)
if ($roomBytes.Length -ne 22) { throw 'RoomName must be exactly 22 ASCII bytes' }

$fixtureHashes = New-Object System.Collections.Generic.List[string]
$sentPages = New-Object System.Collections.Generic.List[byte[]]
for ($i = 0; $i -lt 22; $i++) {
    $p = $pages[$i]
    if ($p.Length -ne 1104) { throw "page $($i+1) length $($p.Length) != 1104" }
    $origHash = (Get-FileHash (Join-Path $FixtureDir ('reply-{0:d2}.bin' -f ($i+1))) -Algorithm SHA256).Hash
    # C5: replace room name at offset 24..45 only
    $changed = New-Object System.Collections.Generic.List[int]
    for ($k = 24; $k -lt 46; $k++) {
        if ($p[$k] -ne $roomBytes[$k - 24]) { $changed.Add($k) }
    }
    $sent = [byte[]]::new(1104)
    [Array]::Copy($p, 0, $sent, 0, 164)          # header up to and incl. [160]
    [Array]::Copy($roomBytes, 0, $sent, 24, 22)  # room name
    [Array]::Copy($p, 164, $sent, 164, 1104 - 164)
    $sentPages.Add($sent)
    $sentFile = Join-Path $OutDir ('sent-reply-{0:d2}.bin' -f ($i+1))
    [IO.File]::WriteAllBytes($sentFile, $sent)
    $sentHash = (Get-FileHash $sentFile -Algorithm SHA256).Hash
    $fixtureHashes.Add(('page {0:d2}: original={1} sent={2} changedOffsets=[{3}]' -f ($i+1), $origHash, $sentHash, ($changed -join ',')))
}
[IO.File]::WriteAllLines((Join-Path $OutDir 'fixture-hashes.txt'), $fixtureHashes, [Text.Encoding]::UTF8)
Say "fixtures       : 22 pages loaded, anonymized, written to sent-reply-*.bin"
Say "fixture-hashes.txt written (original + sent SHA256 + change offsets)"

# ---------------------------------------------------------------- C1: pre-check (whole range)
$allEndpoints = @(Get-NetUDPEndpoint -ErrorAction SilentlyContinue)
$occupied = @($allEndpoints | Where-Object { $_.LocalPort -ge $FirstPort -and $_.LocalPort -le $LastPort })
$pre = New-Object System.Collections.Generic.List[string]
$pre.Add(('pre-check {0}: UDP endpoints in range {1}..{2}: {3}' -f (Get-Date -Format 'HH:mm:ss.fff'), $FirstPort, $LastPort, $occupied.Count))
$skipPorts = @()
if ($occupied.Count -gt 0) {
    foreach ($o in $occupied) {
        $proc = Get-Process -Id $o.OwningProcess -ErrorAction SilentlyContinue
        $pre.Add(("  port {0} held by pid {1} ({2}) local {3}" -f $o.LocalPort, $o.OwningProcess, $(if ($proc) { $proc.ProcessName } else { 'unknown' }), $o.LocalAddress))
        # An IPv4 (0.0.0.0 / specific v4) holder prevents our 0.0.0.0 bind; an IPv6-only
        # holder (::1) does not. Record which IPv4 ports must be skipped.
        if ($o.LocalAddress -notmatch ':') {
            if (-not ($skipPorts -contains $o.LocalPort)) { $skipPorts += $o.LocalPort }
        }
    }
}
$pre.Add(('  IPv4 ports to skip: {0}' -f $(if ($skipPorts.Count -gt 0) { ($skipPorts | Sort-Object) -join ',' } else { 'none' })))
[IO.File]::WriteAllLines((Join-Path $OutDir 'precheck.txt'), $pre, [Text.Encoding]::UTF8)
$rangeSize = $LastPort - $FirstPort + 1
if ($skipPorts.Count -ge $rangeSize) {
    Say 'PRE-CHECK FAILED: every IPv4 port in the discovery range is already occupied. Stopping (no force-kill, no REUSEADDR).'
    Say ('precheck.txt written: {0}' -f (Join-Path $OutDir 'precheck.txt'))
    exit 3
}
if ($skipPorts.Count -gt 0) {
    Say ('pre-check      : {0} of {1} range ports held by other processes; SKIPPING {2} (no force-kill, no REUSEADDR)' -f $skipPorts.Count, $rangeSize, (($skipPorts | Sort-Object) -join ','))
} else {
    Say ('pre-check      : UDP {0}..{1} free - OK (precheck.txt written)' -f $FirstPort, $LastPort)
}

# ---------------------------------------------------------------- bind the whole range (exact, no REUSEADDR)
$socks = New-Object System.Collections.Generic.List[object]
$bindFail = $null
$boundPorts = @()
for ($p = $FirstPort; $p -le $LastPort; $p++) {
    if ($skipPorts -contains $p) { continue }
    $s = [System.Net.Sockets.Socket]::new(
        [System.Net.Sockets.AddressFamily]::InterNetwork,
        [System.Net.Sockets.SocketType]::Dgram,
        [System.Net.Sockets.ProtocolType]::Udp)
    $s.SetSocketOption([Net.Sockets.SocketOptionLevel]::Socket, [Net.Sockets.SocketOptionName]::ReuseAddress, [int]0)
    try {
        $s.Bind([System.Net.IPEndPoint]::new([System.Net.IPAddress]::Any, $p))
        $s.ReceiveBufferSize = 65536
    } catch {
        # A port that disappears between pre-check and bind is skipped, never forced.
        $skipPorts += $p
        $s.Dispose()
        continue
    }
    $socks.Add([pscustomobject]@{ Port = $p; Sock = $s })
    $boundPorts += $p
}
if ($socks.Count -lt 1) {
    Say ('BIND FAILED: no port in {0}..{1} could be bound - stopping (exact bind policy)' -f $FirstPort, $LastPort)
    exit 3
}
Say ("socket         : bound 0.0.0.0 on {0} of {1} ports in {2}..{3} (skipped {4})" -f $socks.Count, ($LastPort - $FirstPort + 1), $FirstPort, $LastPort, $(if ($skipPorts.Count -gt 0) { ($skipPorts | Sort-Object) -join ',' } else { 'none' }))

# local interface addresses (C2 source filter, C3 destination scope)
$localIps = @(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | Select-Object -ExpandProperty IPAddress)
$localIps += '127.0.0.1'
$localIps = $localIps | Select-Object -Unique
Say ("local IPv4 set : {0}" -f ($localIps -join ', '))

# Civ6 magic request
$magic = [byte[]](0x8d, 0xe8, 0xfc, 0x70)

$reqLog = New-Object System.Collections.Generic.List[string]
$trafficLog = New-Object System.Collections.Generic.List[string]
$reqPath = Join-Path $OutDir 'requests.log'
$responsesUsed = 0
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$lastResponseAt = [DateTime]::MinValue
$seenPorts = New-Object System.Collections.Generic.List[int]

Say ('READY: waiting for Civ6 discovery requests on 0.0.0.0:{0}..{1}' -f $FirstPort, $LastPort)
Say ('       (refresh the Civ6 LAN lobby up to {0} times; replies go only to this machine)' -f $MaxResponses)
Say '       [Ctrl+C to stop early]'

# ---------------------------------------------------------------- C2/C3/C6: listen loop
# NOTE (v2.1 fix, 2026-11-13): the three out-parameters of ReceiveMessageFrom MUST be
# loop-local variables. Reusing script-scope variables as [ref] targets throws
# MethodInvocationException ("the type of the referenced object does not support the
# attempted operation") from the 2nd datagram of a burst onwards, which made the
# responder capture only 1 of the 100 datagrams a Civ6 LAN refresh emits.
# Verified: probe-E-diag.ps1 local=99/99 vs hoist=1/99 on the same broadcast burst.
$recvBuf = [byte[]]::new(65536)

# v2.2: receive-error accounting (see header note). Nothing may be swallowed silently.
$errPath = Join-Path $OutDir 'receive-errors.log'
$errLog = New-Object System.Collections.Generic.List[string]
$recvErrorsUnexpected = 0
$recvErrorsExpected = 0
$injectedFaultsLeft = $InjectReceiveFault
# v2.3: select-error accounting (see header note). Separate counters, separate summary line.
$selErrorsUnexpected = 0
$selErrorsExpected = 0
$injectedSelectFaultsLeft = $InjectSelectFault

while ($sw.Elapsed.TotalSeconds -lt $ListenSeconds) {
    # after the budget is spent: keep passively recording for PostResponseSec, then stop
    if ($responsesUsed -ge $MaxResponses -and $lastResponseAt -ne [DateTime]::MinValue) {
        $quiet = (Get-Date) - $lastResponseAt
        if ($quiet.TotalSeconds -ge $PostResponseSec) { break }
    }

    $readList = New-Object System.Collections.ArrayList
    foreach ($e in $socks) { [void]$readList.Add($e.Sock) }
    try {
        if ($injectedSelectFaultsLeft -gt 0) {
            $injectedSelectFaultsLeft--
            throw (New-Object System.InvalidOperationException ('INJECTED SELECT FAULT (remaining {0})' -f $injectedSelectFaultsLeft))
        }
        $null = [System.Net.Sockets.Socket]::Select($readList, $null, $null, 500000)
    } catch [System.Net.Sockets.SocketException] {
        # v2.3: a Select failure is NOT the same thing as "nothing became readable".
        $code = $_.Exception.SocketErrorCode
        $isAbort = ($code -eq 'Interrupted') -or ($code -eq 'OperationAborted') -or
                   ($code -eq 'ConnectionReset') -or ($code -eq 'ConnectionAborted')
        if ($isAbort) {
            $selErrorsExpected++
        } else {
            $selErrorsUnexpected++
            $errLog.Add(('[{0}] kind=SelectException code={1} msg={2} sockets={3}' -f (Get-Date -Format 'HH:mm:ss.fff'), $code, $_.Exception.Message, $socks.Count))
        }
        Start-Sleep -Milliseconds 20   # never busy-spin on a persistent Select failure
        continue
    } catch {
        # v2.3: any other Select failure must leave a trace, never masquerade as "no traffic".
        $selErrorsUnexpected++
        $ex = $_.Exception
        $errLog.Add(('[{0}] kind=SelectException({1}) msg={2} sockets={3}' -f (Get-Date -Format 'HH:mm:ss.fff'), $ex.GetType().Name, $ex.Message, $socks.Count))
        Start-Sleep -Milliseconds 20
        continue
    }
    if ($readList.Count -eq 0) { continue }

    foreach ($readySock in $readList) {
        $entry = $null
        foreach ($e in $socks) { if ([object]::ReferenceEquals($e.Sock, $readySock)) { $entry = $e; break } }
        if (-not $entry) { continue }
        $port = $entry.Port

        $gotDatagram = $false
        # drain every datagram currently queued on this socket, then let Select drive the
        # next readiness round. One Civ6 refresh emits one datagram per discovery port;
        # each of those ports needs its own readiness callback, so "drain" here means
        # "empty this socket's queue", not "service the whole burst in one callback".
        while ($true) {
            # loop-local out-parameters (see NOTE above): never reuse script-scope vars here
            $remoteEp = [System.Net.EndPoint][System.Net.IPEndPoint]::new([System.Net.IPAddress]::Any, 0)
            $flags = [System.Net.Sockets.SocketFlags]::None
            $pinfo = [System.Net.Sockets.IPPacketInformation]::new()
            try {
                if ($injectedFaultsLeft -gt 0) {
                    $injectedFaultsLeft--
                    throw (New-Object System.InvalidOperationException ('INJECTED TEST FAULT on port {0} (remaining {1})' -f $port, $injectedFaultsLeft))
                }
                $n = $entry.Sock.ReceiveMessageFrom($recvBuf, 0, $recvBuf.Length, [ref]$flags, [ref]$remoteEp, [ref]$pinfo)
            } catch [System.Net.Sockets.SocketException] {
                # v2.2: only a genuinely empty queue is "expected". Anything else is a defect.
                $code = $_.Exception.SocketErrorCode
                $isWouldBlock = ($code -eq 'WouldBlock') -or ($code -eq 'TimedOut') -or
                                ($code -eq 'ConnectionReset') -or ($code -eq 'Interrupted') -or
                                ($code -eq 'IOPending')
                if ($isWouldBlock) {
                    $recvErrorsExpected++
                    break   # normal empty-queue tick, nothing more queued on this socket
                }
                $recvErrorsUnexpected++
                $errLog.Add(('[{0}] port={1} kind=SocketException code={2} msg={3}' -f (Get-Date -Format 'HH:mm:ss.fff'), $port, $code, $_.Exception.Message))
                break
            } catch {
                # v2.2: an unexpected receive error must never masquerade as "no traffic".
                $recvErrorsUnexpected++
                $ex = $_.Exception
                $errLog.Add(('[{0}] port={1} kind={2} msg={3}' -f (Get-Date -Format 'HH:mm:ss.fff'), $port, $ex.GetType().Name, $ex.Message))
                break
            }
            if ($n -lt 1) { break }
            $gotDatagram = $true

        $srcIp = ($remoteEp -as [System.Net.IPEndPoint]).Address.ToString()
        $srcPort = ($remoteEp -as [System.Net.IPEndPoint]).Port
        $iface = $pinfo.Interface
        $now = Get-Date -Format 'HH:mm:ss.fff'
        $payload = New-Object byte[] $n
        [Array]::Copy($recvBuf, 0, $payload, 0, $n)
        $payloadHex = [BitConverter]::ToString($payload)

        $isMagic = ($n -eq 4) -and ($payloadHex -eq '8D-E8-FC-70')
        $isLocal = $localIps -contains $srcIp
        if ($isMagic -and $isLocal -and -not $seenPorts.Contains($port)) { $seenPorts.Add($port) }

        $line = "[$now] dstPort=$port len=$n src=${srcIp}:${srcPort} iface=$iface payload=$payloadHex magic=$isMagic localSrc=$isLocal"

        $sinceLastMs = if ($lastResponseAt -eq [DateTime]::MinValue) { [double]::MaxValue } else { ((Get-Date) - $lastResponseAt).TotalMilliseconds }

        if ($isMagic -and $isLocal -and $responsesUsed -lt $MaxResponses -and $sinceLastMs -ge $BurstWindowMs) {
            $responsesUsed++
            $line += " -> RESPONSE #$responsesUsed (from dstPort $port)"
            $reqLog.Add($line)
            Say $line
            # C2: send exactly 22 pages, each once, from the socket the request targeted
            $pageRecs = New-Object System.Collections.Generic.List[string]
            for ($i = 0; $i -lt 22; $i++) {
                $dst = [System.Net.IPEndPoint]::new([System.Net.IPAddress]::Parse($srcIp), $srcPort)
                $t0 = Get-Date -Format 'HH:mm:ss.fff'
                $sentN = $entry.Sock.SendTo($sentPages[$i], $dst)
                $t1 = Get-Date -Format 'HH:mm:ss.fff'
                $h = (Get-FileHash (Join-Path $OutDir ('sent-reply-{0:d2}.bin' -f ($i+1))) -Algorithm SHA256).Hash
                $pageRecs.Add(("      page {0:d2}: sent {1} B from port {2} to {3}:{4} at {5}->{6} sha256={7}" -f ($i+1), $sentN, $port, $srcIp, $srcPort, $t0, $t1, $h))
            }
            $lastResponseAt = Get-Date
            $reqLog.Add(('      replies to {0}:{1} (dstPort {2}, interface {3}) at {4}' -f $srcIp, $srcPort, $port, $iface, $lastResponseAt.ToString('HH:mm:ss.fff')))
            foreach ($r in $pageRecs) { $reqLog.Add($r); Say $r }
            # flush requests.log right after each response so evidence survives an
            # early stop and the external self-test can verify promptly
            [IO.File]::WriteAllLines($reqPath, $reqLog, [Text.Encoding]::UTF8)
        }
        elseif ($isMagic -and $isLocal -and $responsesUsed -lt $MaxResponses) {
            $line += " -> MATCH inside burst window ({0} ms < {1} ms); coalesced, no extra reply" -f [int]$sinceLastMs, $BurstWindowMs
            $trafficLog.Add($line)
            Say $line
        }
        elseif ($isMagic -and $isLocal) {
            $line += " -> MATCH but budget exhausted ($MaxResponses reached); passively recorded only"
            $trafficLog.Add($line)
            Say $line
        }
        else {
            $line += ' -> NOT a matching local Civ6 request; ignored (no reply)'
            $trafficLog.Add($line)
            Say $line
        }

            if ($entry.Sock.Available -le 0) { break }
        }
        if (-not $gotDatagram) { continue }
    }
}

# ---------------------------------------------------------------- finalize
foreach ($e in $socks) { $e.Sock.Dispose() }
$trfPath = Join-Path $OutDir 'post-response-traffic.log'
[IO.File]::WriteAllLines($reqPath, $reqLog, [Text.Encoding]::UTF8)
[IO.File]::WriteAllLines($trfPath, $trafficLog, [Text.Encoding]::UTF8)
# v2.2: persist receive errors even when the list is empty (absence must be provable).
# Written WITHOUT a BOM so that "no unexpected errors" is a genuine 0-byte file, not a
# 3-byte BOM-only file that a reader could mistake for content.
[IO.File]::WriteAllLines($errPath, $errLog, (New-Object System.Text.UTF8Encoding($false)))

$summary = New-Object System.Collections.Generic.List[string]
$summary.Add('=== synthetic-host-responder v2.3 summary ===')
$summary.Add(('run time        : {0} (window {1} s)' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), [int]$sw.Elapsed.TotalSeconds))
$summary.Add(('bound ports     : {0}..{1} ({2} bound, skipped {3})' -f $FirstPort, $LastPort, $socks.Count, $(if ($skipPorts.Count -gt 0) { ($skipPorts | Sort-Object) -join ',' } else { 'none' })))
$summary.Add(('responses sent  : {0} (budget {1})' -f $responsesUsed, $MaxResponses))
$summary.Add(('pages per resp  : 22 (each once, per-page SHA256 in requests.log)'))
$summary.Add(('request ports   : {0}' -f $(if ($seenPorts.Count -gt 0) { $seenPorts -join ',' } else { 'none' })))
$summary.Add(('requests logged : {0}  post-response datagrams: {1}' -f $reqLog.Count, $trafficLog.Count))
$summary.Add(('receive errors  : {0} unexpected, {1} expected(would-block) - see receive-errors.log' -f $recvErrorsUnexpected, $recvErrorsExpected))
$summary.Add(('select errors   : {0} unexpected, {1} expected(abort) - see receive-errors.log' -f $selErrorsUnexpected, $selErrorsExpected))
$summary.Add('')
$summary.Add('C7 restricted phrasings (REV-013-REVIEW section 4, item 7):')
if ($responsesUsed -gt 0) {
    $summary.Add('  OUTCOME-PENDING: client list result must be observed in the Civ6 lobby.')
    $summary.Add('  If a list item for the anonymous room appears: "本构建客户端在本机合成响应条件下接受该公告并显示列表项".')
    $summary.Add('  If it does not: "本轮未观察到列表项，原因未裁决".')
} else {
    $summary.Add('  No matching request was seen; no synthetic announcement was sent.')
    $summary.Add('  "本轮未观察到列表项，原因未裁决" (nothing was sent).')
}
$summary.Add('')
$summary.Add('Boundary notes:')
$summary.Add('  - Responder did NOT send any synthetic response to a remote host. Civ6 itself')
$summary.Add('    emitted its normal discovery broadcasts during the experiment (that is part of')
$summary.Add('    the authorised experiment); replies were unicast to the local Civ6 source only')
$summary.Add('  - Replies are sent from the same socket that received the request, so the reply')
$summary.Add('    source port equals the port the client targeted (see requests.log dstPort).')
$summary.Add('  - Room name was replaced at offset 24..45 in every page (fixture-hashes.txt).')
$summary.Add('  - No route/metric/NIC/firewall/Steam change; no DLL injection.')
$summary.Add('  - This is NOT E2-B, NOT M0-B, NOT a multiplayer validation.')
$summary.Add('')
$summary.Add('Parser/analyzer version: analyze-room-advert.ps1 v2 (SHA256 D94A79F7A0D109C50BB5A6792DE4B5271F6FE6B673D6340611EDB1D37E926DEE)')
$summary.Add('Fixture origin: E2A-H4-reply-20261113 reply-set, captured single-host on 2026-11-13.')
[IO.File]::WriteAllLines((Join-Path $OutDir 'summary.txt'), $summary, [Text.Encoding]::UTF8)

Say '=== done ==='
Say ("evidence dir   : {0}" -f $OutDir)
Say ("files          : precheck.txt fixture-hashes.txt requests.log post-response-traffic.log receive-errors.log summary.txt sent-reply-*.bin")
Say ("script sha256  : {0}" -f (Get-FileHash $MyInvocation.MyCommand.Path -Algorithm SHA256).Hash)
