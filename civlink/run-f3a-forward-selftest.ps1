# run-f3a-forward-selftest.ps1 - F3-A direct forward prototype, LOOPBACK self-test.
#
# Design v0.3 section 3.2/3.4: forward 62056 datapath payloads VERBATIM, once per frame,
# to ONE peer Agent port. This driver proves the mechanism mechanically on 127.0.0.1:
#   * a 62056 datapath frame is forwarded and the peer side receives the exact payload
#   * a 62900..62999 discovery frame is NOT forwarded (design rule 3: F1 path)
#   * a non-62056 / non-discovery frame is counted as "skip not datapath" and NOT forwarded
#   * the Agent never binds UDP :62056 (checked against the live process)
#   * no retransmit: one delivered payload per forwarded frame
#   * payload identity is checked by SHA-256 on BOTH sides (forward line and peer-recv line)
#   * the peer's first sender is the forwarder's own socket port (identity binding)
#   * the D2 red line holds on every entry point: --port, --forward-listen and --forward-to
#     all refuse 62056 (three negative cases, each asserted to fail closed)
#
# Note the topology: --forward-to and --forward-listen point at the SAME loopback port, so
# this is a same-process two-role self-loop, not two independent Agents. The payload and
# identity assertions below are what keep that honest; a second Agent is F3-B/F3-E work.
#
# It is NOT a multiplayer result and NOT a game-process injection. Exit codes:
#   0 PASS, 1 assertion failed, 2 precondition failed (port busy / binary missing).

$ErrorActionPreference = 'Continue'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$agentExe = Join-Path $here 'civlink-agent.exe'
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$outRoot = 'C:\Users\dd\Desktop\injciv6-v0.3.3\M0A\captures'
$out = Join-Path $outRoot ("F3A-forward-selftest-$stamp")
$fail = 0

# Audit round 3, R3-L2: a console transcript so a later reviewer can see exactly what ran
# (F3-B established the .bak + transcript convention; F3-A lacked both, which is why the
# 144051 evidence was not auditable). The output directory must exist before the transcript
# can be opened, hence the New-Item here.
New-Item -ItemType Directory -Force -Path $out | Out-Null
$transcript = Join-Path $out 'selftest-console.txt'
Start-Transcript -Path $transcript -Force | Out-Null

function Check([string]$name, $ok, [string]$detail) {
    if ($ok) {
        Write-Host "[PASS] $name"
    } else {
        Write-Host "[FAIL] $name -> $detail"
        $script:fail++
    }
}

if (-not (Test-Path $agentExe)) {
    Write-Host "[!] missing $agentExe (run cargo build --release first)"
    exit 2
}
$busy = Get-NetUDPEndpoint -LocalPort 34718 -ErrorAction SilentlyContinue
if ($busy) {
    Write-Host "[!] 127.0.0.1:34718 is already in use by pid=$($busy.OwningProcess) - stop it first"
    exit 2
}
$peerPort = 21346
if (Get-NetUDPEndpoint -LocalPort $peerPort -ErrorAction SilentlyContinue) {
    Write-Host "[!] 127.0.0.1:$peerPort is already in use - stop it first"
    exit 2
}

New-Item -ItemType Directory -Force -Path $out | Out-Null
$stopFile = Join-Path $out 'stop'
function New-Cvlh2Frame([int]$seq, [string]$srcIp, [int]$srcPort, [string]$dstIp, [int]$dstPort, [byte[]]$payload, [byte]$flags = 0x00) {
    # 42-byte CVLH2 header, same encoding the F2 driver uses (cvlh2.h).
    $h = [byte[]]::new(42)
    $h[0] = 0x43; $h[1] = 0x56; $h[2] = 0x4C; $h[3] = 0x48
    $h[4] = 2; $h[5] = 0
    [BitConverter]::GetBytes([uint32]$seq).CopyTo($h, 6)
    [BitConverter]::GetBytes([uint64]1).CopyTo($h, 10)
    [BitConverter]::GetBytes([uint32]1).CopyTo($h, 18)
    [BitConverter]::GetBytes([uint32]1).CopyTo($h, 22)
    $h[26] = 2
    $s = [System.Net.IPAddress]::Parse($srcIp).GetAddressBytes()
    $d = [System.Net.IPAddress]::Parse($dstIp).GetAddressBytes()
    $s.CopyTo($h, 27); $d.CopyTo($h, 33)
    $sp = [BitConverter]::GetBytes([uint16]$srcPort); [Array]::Reverse($sp); $sp.CopyTo($h, 31)
    $dp = [BitConverter]::GetBytes([uint16]$dstPort); [Array]::Reverse($dp); $dp.CopyTo($h, 37)
    $h[39] = $flags
    [BitConverter]::GetBytes([uint16]$payload.Length).CopyTo($h, 40)
    $buf = [byte[]]::new(42 + $payload.Length)
    $h.CopyTo($buf, 0); $payload.CopyTo($buf, 42)
    return ,$buf
}

function Send-Frame([byte[]]$frame) {
    $sender = [System.Net.Sockets.UdpClient]::new()
    try {
        $ep = [System.Net.IPEndPoint]::new([System.Net.IPAddress]::Parse('127.0.0.1'), 34718)
        [void]$sender.Send($frame, $frame.Length, $ep)
    } finally {
        $sender.Close()
    }
}

# ---------------------------------------------------------------------------------------
# Negative cases first: every entry point that could point the Agent at the game's
# data-plane port must fail closed with a usage error (exit 1) and must not bind anything.
# ---------------------------------------------------------------------------------------
$negCases = @(
    @{ name = '--port 62056'; args = @('--port', '62056'); want = 'port must not be 62056' },
    @{ name = '--forward-listen 62056'; args = @('--forward-listen', '62056'); want = 'forward-listen must not be 62056' },
    @{ name = '--forward-to 127.0.0.1:62056'; args = @('--forward-to', '127.0.0.1:62056'); want = 'forward-to must not target port 62056' }
)
$negLog = @()
foreach ($case in $negCases) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $agentExe
    $psi.Arguments = ($case.args -join ' ')
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    $psi.WorkingDirectory = $here
    $np = New-Object System.Diagnostics.Process
    $np.StartInfo = $psi
    [void]$np.Start()
    $npOut = $np.StandardOutput.ReadToEnd()
    $npErr = $np.StandardError.ReadToEnd()
    [void]$np.WaitForExit(10000)
    # Audit round 3, L8: capture $code BEFORE Kill() - after a Kill() the exit code is
    # unreliable/undefined in .NET on Windows.
    $code = if ($np.HasExited) { $np.ExitCode } else { $null }
    if (-not $np.HasExited) { $np.Kill() }
    $negLog += ("{0} -> exit={1} stderr={2}" -f $case.name, $code, $npErr.Trim())
    Check ("negative case {0} fails closed (exit 1)" -f $case.name) ($code -eq 1) "exit=$code"
    # Audit round 3, L8: each case now matches its own refusal text instead of a shared
    # -match '62056', so a refusal that names the wrong port cannot pass.
    Check ("negative case {0} names the refusal" -f $case.name) ($npErr -match [regex]::Escape($case.want)) "stderr=$($npErr.Trim())"
}
$negLog | Out-File -FilePath (Join-Path $out 'negative-cases.txt') -Encoding utf8

Write-Host "[*] starting agent: --forward-to 127.0.0.1:$peerPort --forward-listen $peerPort (30 s window)"
$argsLine = @(
    '--listen-seconds', '30',
    '--out-dir', $out,
    '--stop-file', $stopFile,
    '--forward-to', "127.0.0.1:$peerPort",
    '--forward-listen', "$peerPort",
    '--simulate-datapath', '--bind-ip', '127.0.0.1', '--loopback-selftest',
    '--quiet'
)
# Windows PowerShell 5.1 leaves Process.ExitCode unset when Start-Process is used together
# with -RedirectStandardOutput/-RedirectStandardError, so drive the process through the
# .NET API instead: this keeps ExitCode readable (verified: 'cmd /c exit 3' -> 3).
$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = $agentExe
$psi.Arguments = ($argsLine | ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } }) -join ' '
$psi.UseShellExecute = $false
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
$psi.CreateNoWindow = $true
$psi.WorkingDirectory = $here
$proc = New-Object System.Diagnostics.Process
$proc.StartInfo = $psi
[void]$proc.Start()
$stdoutTask = $proc.StandardOutput.ReadToEndAsync()
$stderrTask = $proc.StandardError.ReadToEndAsync()

$bound = $false
for ($i = 0; $i -lt 50; $i++) {
    Start-Sleep -Milliseconds 100
    if (Get-NetUDPEndpoint -LocalPort 34718 -ErrorAction SilentlyContinue) { $bound = $true; break }
}
if (-not $bound) {
    Write-Host "[!] agent never bound 127.0.0.1:34718"
    if (-not $proc.HasExited) { $proc.Kill() }
    exit 2
}

# The Agent must not own UDP :62056 (codex D2 section 2.2). Record the live check.
$onDatapath = Get-NetUDPEndpoint -LocalPort 62056 -ErrorAction SilentlyContinue
$agentOn62056 = @($onDatapath | Where-Object { $_.OwningProcess -eq $proc.Id })
"agent pid=$($proc.Id) udp:62056 owned by agent: $($agentOn62056.Count)" |
    Out-File -FilePath (Join-Path $out 'bind-check.txt') -Encoding utf8
Check 'agent does not bind UDP :62056' ($agentOn62056.Count -eq 0) "owned endpoints=$($agentOn62056.Count)"

# Payload shapes taken from the S5 real-client evidence (8 B, prefix 17 32 00 00 FF FF).
$p1 = [byte[]](0x17, 0x32, 0x00, 0x00, 0xFF, 0xFF, 0x4F, 0xAC)
$p2 = [byte[]](0x17, 0x32, 0x00, 0x00, 0xFF, 0xFF, 0x35, 0xBA)
$p3 = [byte[]]::new(120)
for ($i = 0; $i -lt 120; $i++) { $p3[$i] = [byte]($i + 1) }
$discovery = [byte[]](0x8D, 0xE8, 0xFC, 0x70)
$other = [byte[]](0xDE, 0xAD, 0xBE, 0xEF)

# Expected digests of the three forwarded payloads, computed here from the same arrays
# (SHA-256 via .NET) so the log can be checked end to end instead of by prefix only.
function Get-Sha256Hex([byte[]]$bytes) {
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString($sha.ComputeHash($bytes)) -replace '-', '').ToLowerInvariant()
    } finally { $sha.Dispose() }
}
$expectDigest = @{
    '8'   = @((Get-Sha256Hex $p1), (Get-Sha256Hex $p2), (Get-Sha256Hex $discovery))
    '120' = @((Get-Sha256Hex $p3))
}

# Frames 1-5 are the F3-A baseline. Frames 6-7 exist because audit round 2 (finding M1) showed
# that the first revision treated "FLAG_DISCOVERY set OR port in the discovery window" as a
# discovery request, while design v0.3 §3.2 rule 3 requires BOTH. Under the old OR rule:
#   - frame 6 (a real 62056 frame that merely carries the discovery flag) was dropped by the
#     forward path and landed in NO counter at all - silent loss;
#   - frame 7 (a 62905 frame whose payload is not the magic) was dropped as "discovery" even
#     though nothing about it was a discovery request.
# With the AND rule frame 6 is forwarded and frame 7 is counted as skip_not_datapath.
Send-Frame (New-Cvlh2Frame 1 '127.0.0.1' 21345 '127.0.0.1' 62056 $p1 0x21)
Send-Frame (New-Cvlh2Frame 2 '127.0.0.1' 21345 '127.0.0.1' 62056 $p2 0x21)
Send-Frame (New-Cvlh2Frame 3 '127.0.0.1' 21345 '127.0.0.1' 62905 $discovery 0x06)
Send-Frame (New-Cvlh2Frame 4 '127.0.0.1' 21345 '127.0.0.1' 50999 $other 0x20)
Send-Frame (New-Cvlh2Frame 5 '127.0.0.1' 21345 '127.0.0.1' 62056 $p3 0x21)
Send-Frame (New-Cvlh2Frame 6 '127.0.0.1' 21345 '127.0.0.1' 62056 $discovery 0x04)
Send-Frame (New-Cvlh2Frame 7 '127.0.0.1' 21345 '127.0.0.1' 62905 $other 0x04)

Start-Sleep -Milliseconds 1500
New-Item -ItemType File -Force -Path $stopFile | Out-Null
$exited = $false
for ($i = 0; $i -lt 200; $i++) {
    if ($proc.HasExited) { $exited = $true; break }
    Start-Sleep -Milliseconds 100
}
if (-not $exited) {
    Write-Host "[!] agent did not exit after the stop file"
    $proc.Kill()
    exit 1
}
# WaitForExit() without a timeout is what makes Process.ExitCode readable in Windows
# PowerShell; WaitForExit(ms) alone can leave it unset.
$proc.WaitForExit()
if ($stdoutTask) { $stdoutTask.Result | Out-File -FilePath (Join-Path $out 'agent-console.txt') -Encoding utf8 }
if ($stderrTask) { $stderrTask.Result | Out-File -FilePath (Join-Path $out 'agent-stderr.txt') -Encoding utf8 }
$exitCode = $proc.ExitCode
"agent exit=$exitCode" | Out-File -FilePath (Join-Path $out 'exit.txt') -Encoding utf8
Check 'agent exit code 0' ($exitCode -eq 0) "exit=$exitCode"

$summaryPath = Join-Path $out 'summary.txt'
if (-not (Test-Path $summaryPath)) {
    Write-Host "[!] no summary.txt"
    exit 1
}
$summary = [IO.File]::ReadAllText($summaryPath, [Text.Encoding]::UTF8)

function Grab([string]$text, [string]$pattern) {
    $m = [regex]::Match($text, $pattern)
    if ($m.Success) { return $m.Groups[1].Value }
    return ''
}

$seen = Grab $summary 'frames seen\s+:\s+(\d+) \(accepted frames that reached the forward stage'
$fwd = Grab $summary 'forwarded\s+:\s+(\d+) \(payload bytes'
$fbytes = Grab $summary 'forward bytes\s+:\s+(\d+)'
$ffail = Grab $summary 'forward fail\s+:\s+(\d+)'
$skipNotDp = Grab $summary 'skip not datapath:\s+(\d+)'
$skipDisco = Grab $summary 'skip discovery\s*:\s+(\d+)'
$skipKey = Grab $summary 'skip key table\s+:\s+(\d+)'
$skipRej = Grab $summary 'skip rejected\s+:\s+(\d+)'
$maps = Grab $summary 'mappings created:\s+(\d+)'
$peerRecv = Grab $summary 'payloads recv\s+:\s+(\d+)'
$peerBytes = Grab $summary 'payload bytes\s+:\s+(\d+)'
$listenPort = Grab $summary 'listen port\s+:\s+(\d+)'
$target = Grab $summary 'target\s+:\s+(\S+) \(peer Agent port'
$fwSock = Grab $summary 'forward sock\s+:\s+(\S+) \(sender identity'
$firstSender = Grab $summary 'first sender\s+:\s+(\S+)'

Write-Host "[*] summary: seen=$seen forwarded=$fwd bytes=$fbytes fail=$ffail skipNotDp=$skipNotDp skipDisco=$skipDisco peer=$peerRecv/$peerBytes listen=$listenPort"

# Frame accounting under the AND rule (7 frames sent):
#   1,2,5   62056 payloads                        -> forwarded
#   6       62056 payload carrying FLAG_DISCOVERY -> forwarded (the flag alone is not a
#                                                   discovery request; under the old OR rule this
#                                                   frame vanished without landing in any counter)
#   3       62905 + 4-byte magic + discovery flag -> skip_discovery
#   4       50999                                 -> skip_not_datapath
#   7       62905 + non-magic payload + flag      -> skip_not_datapath (port in the window but
#                                                   the payload is not the magic, so it is not a
#                                                   discovery request)
Check 'frames seen == 7 (all accepted frames reach the forward stage)' ($seen -eq '7') "seen=$seen"
Check 'forwarded == 4 (frames 1,2,5,6)' ($fwd -eq '4') "forwarded=$fwd"
Check 'forward bytes == 8+8+120+4' ($fbytes -eq '140') "bytes=$fbytes"
Check 'forward fail == 0' ($ffail -eq '0') "fail=$ffail"
Check 'skip not datapath == 2 (50999 and the 62905 non-magic frame)' ($skipNotDp -eq '2') "skip=$skipNotDp"
Check 'skip discovery == 1 (62905 + magic: the one true discovery frame)' ($skipDisco -eq '1') "skipDisco=$skipDisco"
Check 'skip rejected == 0 (no Hook-rejected frames in this fixture)' ($skipRej -eq '0') "skipRej=$skipRej"
# Audit round 3, finding M5: the "skip key table == 0" assertion was a self-consistency tautology
# (the fixture deliberately never exercises the 64-key cap; the branch is covered by the unit
# test `forward_key_table_full_refuses_to_forward`, and summary still reports it for the
# accounting identity). The check is removed here - the counter stays in the identity sum.
$acct = [int]$fwd + [int]$skipNotDp + [int]$skipDisco + [int]$skipKey + [int]$skipRej + [int]$ffail
Check 'every accepted frame is accounted for (forwarded+notDp+disco+keyTable+rejected+fail == seen)' (
    $acct -eq [int]$seen
) "sum=$acct seen=$seen"
Check 'mappings created == 1 (one key for all 62056 frames)' ($maps -eq '1') "maps=$maps"
Check 'peer payloads recv == 4 (one per forwarded frame, no retransmit)' ($peerRecv -eq '4') "peer=$peerRecv"
Check 'peer payload bytes == 140 (verbatim, no rewrite)' ($peerBytes -eq '140') "peerBytes=$peerBytes"
Check "peer listen port == $peerPort (never 62056)" ($listenPort -eq "$peerPort") "listen=$listenPort"
Check "target == 127.0.0.1:$peerPort" ($target -eq "127.0.0.1:$peerPort") "target=$target"
Check 'summary declares the prototype boundary' ($summary -match 'LOOPBACK PROTOTYPE') 'no boundary note'

# Identity binding: the peer's first sender must be the forwarder socket recorded in the
# summary (same address, same port). Without this the peer payloads could come from
# anywhere on loopback and would say nothing about the forward path.
$fwSockPort = ''
if ($fwSock -match ':(\d+)$') { $fwSockPort = $Matches[1] }
$seenPort = ''
if ($firstSender -match ':(\d+)$') { $seenPort = $Matches[1] }
Check 'peer first sender is the forwarder socket (port match)' (
    $fwSockPort -ne '' -and $seenPort -ne '' -and $fwSockPort -eq $seenPort
) "forward sock=$fwSock first sender=$firstSender"

# Every forwarded target address in the log must be the peer Agent port, never 62056.
$flog = Join-Path $out 'forward-log.txt'
$logged = @()
if (Test-Path $flog) { $logged = [IO.File]::ReadAllLines($flog, [Text.Encoding]::UTF8) }
$fwdLines = @($logged | Where-Object { $_ -match ' forward seq=' })
$peerLines = @($logged | Where-Object { $_ -match ' peer-recv n=' })
$skipLines = @($logged | Where-Object { $_ -match ' forward skip ' })
Check 'forward-log has 4 forward lines' ($fwdLines.Count -eq 4) "lines=$($fwdLines.Count)"
Check 'forward-log has 4 peer-recv lines' ($peerLines.Count -eq 4) "lines=$($peerLines.Count)"
Check 'forward-log has 2 skip lines (50999-like non-datapath + non-magic window frame)' ($skipLines.Count -eq 2) "lines=$($skipLines.Count)"
# Audit round 3, finding M6: previously this asserted only that a 629xx+magic frame was never
# *forwarded*. The stronger, whole-file form is: the discovery frame (seq=3) must never appear
# ANYWHERE in the forward log - not forwarded, not even as a skip line - because the discovery
# path bypasses the forward stage entirely (counted only as `skip discovery` in the summary).
# seq=3 is unique in this fixture, so its absence across ALL lines is the honest check.
Check 'discovery frame seq=3 absent from every forward-log line (not forwarded, not skipped there)' (
    -not ($logged -match '\bseq=3\b')
) 'seq=3 appeared in the forward log'

# Audit round 3, finding M7 (cross-file identity): before, the peer "first sender" was compared
# only against the summary's own `forward sock` line - same file, so a driver that printed a
# wrong port in BOTH lines would still pass. Now the peer-recv `from=` addresses IN THE LOG are
# compared against the summary's `forward sock` (port AND address), and each from-port must not
# be 62056. On loopback the forwarder's 0.0.0.0-bound socket is seen as 127.0.0.1 by the peer,
# so the IP comparison accepts 127.0.0.1 for a 0.0.0.0 forward sock.
$fwSockIp = ''
$fwSockPort = ''
if ($fwSock -match '^([\d.]+):(\d+)$') { $fwSockIp = $Matches[1]; $fwSockPort = $Matches[2] }
$peerFromOk = $true
$peerFromDetail = @()
foreach ($line in $peerLines) {
    $mf = [regex]::Match($line, 'from=([\d.]+):(\d+)')
    if (-not $mf.Success) { $peerFromOk = $false; $peerFromDetail += 'unparsable'; continue }
    $fromIp = $mf.Groups[1].Value
    $fromPort = $mf.Groups[2].Value
    if ($fromPort -ne $fwSockPort) { $peerFromOk = $false; $peerFromDetail += "from=${fromIp}:${fromPort} != fw sock port $fwSockPort" }
    if ($fromPort -eq '62056') { $peerFromOk = $false; $peerFromDetail += "from port 62056" }
    if ($fromIp -ne '127.0.0.1' -and -not ($fwSockIp -eq $fromIp)) {
        $peerFromOk = $false; $peerFromDetail += "from ip $fromIp not loopback for fw sock $fwSock"
    }
}
Check 'peer-recv from= matches the forwarder socket across files (port, ip, not 62056)' (
    $peerFromOk -and $peerLines.Count -eq 4
) ($peerFromDetail -join '; ')
Check 'forward-log never targets :62056' (-not ($fwdLines -match '-> [\d.]+:62056')) 'forwarded to 62056'

# Payload identity end to end: the sha256 on each forward line must equal the sha256 on the
# matching peer-recv line, and both must equal the digest of the bytes we sent. This covers
# the whole 120 B payload, not just its first 8 bytes.
$fwdDigests = @()
foreach ($line in $fwdLines) {
    $m = [regex]::Match($line, 'sha256=([0-9a-f]{64})')
    if ($m.Success) { $fwdDigests += $m.Groups[1].Value }
}
$peerDigests = @()
foreach ($line in $peerLines) {
    $m = [regex]::Match($line, 'sha256=([0-9a-f]{64})')
    if ($m.Success) { $peerDigests += $m.Groups[1].Value }
}
Check 'forward-log carries a sha256 on every forward line' ($fwdDigests.Count -eq 4) "digests=$($fwdDigests.Count)"
Check 'peer-recv carries a sha256 on every line' ($peerDigests.Count -eq 4) "digests=$($peerDigests.Count)"
Check 'forward and peer sha256 sets are identical (verbatim delivery)' (
    (($fwdDigests | Sort-Object) -join ',') -eq (($peerDigests | Sort-Object) -join ',')
) "fwd=$($fwdDigests -join ',') peer=$($peerDigests -join ',')"
$wantDigests = @($expectDigest['8']) + @($expectDigest['120'])
Check 'delivered digests equal the digests of the sent payloads (incl. all 120 B)' (
    (($peerDigests | Sort-Object) -join ',') -eq (($wantDigests | Sort-Object) -join ',')
) "peer=$($peerDigests -join ',') want=$($wantDigests -join ',')"
# Pairing, not just set equality: with two distinct 8 B payloads and one 120 B payload a set
# comparison alone would accept swapped payloads. Each forward line's seq and digest must
# correspond to the frame the driver sent under that seq. A mismatch here is what a "payloads
# arrived but got crossed" regression looks like.
$wantBySeqLen = @{
    '1' = @((Get-Sha256Hex $p1), '8')
    '2' = @((Get-Sha256Hex $p2), '8')
    '5' = @((Get-Sha256Hex $p3), '120')
    '6' = @((Get-Sha256Hex $discovery), '4')
}
$pairsOk = $true
$pairDetail = @()
foreach ($line in $fwdLines) {
    $ms = [regex]::Match($line, 'forward seq=(\d+) .*len=(\d+) sha256=([0-9a-f]{64})')
    if (-not $ms.Success) { $pairsOk = $false; $pairDetail += 'unparsable'; continue }
    $sq = $ms.Groups[1].Value
    $ln = $ms.Groups[2].Value
    $dg = $ms.Groups[3].Value
    if (-not $wantBySeqLen.ContainsKey($sq)) { $pairsOk = $false; $pairDetail += "seq$sq unexpected"; continue }
    $want = $wantBySeqLen[$sq]
    if ($want[0] -ne $dg -or $want[1] -ne $ln) {
        $pairsOk = $false
        $pairDetail += "seq$sq len=$ln digest=$dg want len=$($want[1]) digest=$($want[0])"
    }
}
Check 'each forward line matches the payload sent under that seq (pairing, not just set equality)' `
    ($pairsOk -and $fwdLines.Count -eq 4) ($pairDetail -join '; ')
Check 'peer-recv shows the 8B payload head 17320000 for both short frames' (
    @($peerLines | Where-Object { $_ -match 'len=8\b.*payload=17320000' }).Count -eq 2
) 'payload head mismatch'

Write-Host ''
Stop-Transcript | Out-Null
if ($fail -eq 0) {
    Write-Host "F3A-FORWARD-SELFTEST: PASS (evidence: $out)"
    exit 0
}
Write-Host "F3A-FORWARD-SELFTEST: FAIL ($fail assertion(s), evidence: $out)"
exit 1
