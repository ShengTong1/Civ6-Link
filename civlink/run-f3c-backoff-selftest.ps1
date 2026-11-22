# run-f3c-backoff-selftest.ps1 - F3-C backoff semantics through the forward chain.
#
# Design v0.3 section 5.2: with the peer NEVER replying, the game's 10 retry frames
# (real S5 schedule: 0.5, 1, 2, 4, 8, 16, 32, 64, 128 s) must all reach the peer
# Agent: seq continuous, no duplicates, no reordering, no application-level retransmit.
#
# The schedule and payload shapes are copied from the S5 real-client frame-log
# (M0A\captures\F2-S5-join-20261114\frame-log.txt, seq 101..110), so this driver
# reproduces the observed client behaviour rather than inventing a new one.
#
# This is a LOOPBACK prototype test: nothing enters a game process (Design I/II is M0-B),
# no reply is produced by the peer, and it is NOT a multiplayer result.
#
# Exit codes: 0 PASS, 1 assertion failed, 2 precondition failed.

param(
    [double]$TimeScale = 1.0
)

$ErrorActionPreference = 'Continue'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$agentExe = Join-Path $here 'civlink-agent.exe'
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$outRoot = 'C:\Users\dd\Desktop\injciv6-v0.3.3\M0A\captures'
$out = Join-Path $outRoot ("F3C-backoff-selftest-$stamp")
$fail = 0

function Check([string]$name, $ok, [string]$detail) {
    # The second parameter used to be typed [bool], which silently casts any non-empty
    # string - including "False" - to $true. An assertion that can only ever pass is worse
    # than no assertion, so a string here is now a hard failure instead of a quiet PASS.
    if ($ok -is [string]) {
        Write-Host "[FAIL] $name -> non-boolean assertion argument '$ok'"
        $script:fail++
        return
    }
    if ($ok -eq $true) {
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
$peerPort = 21347
if (Get-NetUDPEndpoint -LocalPort $peerPort -ErrorAction SilentlyContinue) {
    Write-Host "[!] 127.0.0.1:$peerPort is already in use - stop it first"
    exit 2
}

New-Item -ItemType Directory -Force -Path $out | Out-Null
$stopFile = Join-Path $out 'stop'

# S5 observed retry schedule (seconds between consecutive frames, first frame at t=0).
$schedule = @(0.0, 0.5, 1.0, 2.0, 4.0, 8.0, 16.0, 32.0, 64.0, 128.0)
# S5 observed payloads: 6 fixed bytes 17 32 00 00 FF FF + 2 changing bytes per frame.
$suffixes = @('4FAC', '51A1', '558A', '5D5A', '6CFA', '8C3A', 'CABA', '47BA', '41BA', '35BA')
$totalSeconds = 0.0
for ($i = 0; $i -lt $schedule.Count; $i++) { $totalSeconds += $schedule[$i] }
$totalSeconds = $totalSeconds * $TimeScale
$windowSeconds = [int][Math]::Ceiling($totalSeconds / $TimeScale) + 45

Write-Host ("[*] schedule total {0:N1} s (time scale {1}), agent window {2} s" -f $totalSeconds, $TimeScale, $windowSeconds)

function New-Cvlh2Frame([int]$seq, [string]$srcIp, [int]$srcPort, [string]$dstIp, [int]$dstPort, [byte[]]$payload, [byte]$flags) {
    $h = [byte[]]::new(42)
    $h[0] = 0x43; $h[1] = 0x56; $h[2] = 0x4C; $h[3] = 0x48
    $h[4] = 2; $h[5] = 0
    [BitConverter]::GetBytes([uint32]$seq).CopyTo($h, 6)
    [BitConverter]::GetBytes([uint64]1).CopyTo($h, 10)
    [BitConverter]::GetBytes([uint32]2).CopyTo($h, 18)
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

function HexToBytes([string]$hex) {
    $b = [byte[]]::new($hex.Length / 2)
    for ($i = 0; $i -lt $b.Length; $i++) { $b[$i] = [Convert]::ToByte($hex.Substring($i * 2, 2), 16) }
    return ,$b
}

$argsLine = @(
    '--listen-seconds', "$windowSeconds",
    '--out-dir', $out,
    '--stop-file', $stopFile,
    '--forward-to', "127.0.0.1:$peerPort",
    '--forward-listen', "$peerPort",
    '--simulate-datapath', '--bind-ip', '127.0.0.1', '--loopback-selftest',
    '--quiet'
)
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
$onDatapath = Get-NetUDPEndpoint -LocalPort 62056 -ErrorAction SilentlyContinue
$agentOn62056 = @($onDatapath | Where-Object { $_.OwningProcess -eq $proc.Id })
"agent pid=$($proc.Id) udp:62056 owned by agent: $($agentOn62056.Count)" |
    Out-File -FilePath (Join-Path $out 'bind-check.txt') -Encoding utf8
Check 'agent does not bind UDP :62056' ($agentOn62056.Count -eq 0) "owned endpoints=$($agentOn62056.Count)"

# Send the 10 retry frames on the S5 observed schedule. The peer never replies.
$sender = [System.Net.Sockets.UdpClient]::new()
$sendLog = New-Object System.Collections.Generic.List[string]
$senderLog = Join-Path $out 'send-schedule.txt'
try {
    $ep = [System.Net.IPEndPoint]::new([System.Net.IPAddress]::Parse('127.0.0.1'), 34718)
    for ($i = 0; $i -lt $schedule.Count; $i++) {
        $wait = $schedule[$i] * $TimeScale
        if ($wait -gt 0) { Start-Sleep -Milliseconds ([int]($wait * 1000)) }
        $payload = HexToBytes ('17320000FFFF' + $suffixes[$i])
        $frame = New-Cvlh2Frame ($i + 1) '127.0.0.1' 21345 '127.0.0.1' 62056 $payload 0x21
        [void]$sender.Send($frame, $frame.Length, $ep)
        $sendLog.Add(("{0} seq={1} gap={2:N3}s payload={3}" -f (Get-Date -Format 'HH:mm:ss.fff'), ($i + 1), $schedule[$i], $suffixes[$i]))
        Write-Host ("[*] sent seq={0} after gap {1:N1} s" -f ($i + 1), $schedule[$i])
    }
} finally {
    $sender.Close()
}
$sendLog | Out-File -FilePath $senderLog -Encoding utf8

# ---------------------------------------------------------------------------------------
# Negative controls (F3-C audit items F3C-R-05 / F3C-R-06).
#
# The main sequence above only ever produces "0" for duplicates / gaps / reordering, and
# "1" for mappings-created. A run that reports 0 proves nothing on its own: the counter
# could be broken, or never reached. These three frames are deliberately WRONG and must
# come back as non-zero counts. They run after the scheduled sequence so the backoff
# timing assertions and the seq 1..10 assertions are unaffected, and they use the same
# socket and the same key as the main sequence so that key-table behaviour is observable.
#
#   F11  seq=10 again          -> duplicates must become 1
#   F12  seq=12 (skips 11)     -> seq gaps must become 1, missing_frames 1
#   F13  same 4-tuple as seq=1 -> mappings created must STAY 1 (key reuse, not a new key)
# ---------------------------------------------------------------------------------------
$negStart = @()
$sender2 = [System.Net.Sockets.UdpClient]::new()
try {
    $ep2 = $nec = $null
    $ep2 = [System.Net.IPEndPoint]::new([System.Net.IPAddress]::Parse('127.0.0.1'), 34718)
    $negative = @(
        @{ name = 'F11 duplicate seq=10'; seq = 10; payload = '17320000FFFF35BA' },
        @{ name = 'F12 gap seq=12'; seq = 12; payload = '17320000FFFF7E42' },
        # A distinct payload on purpose: reusing seq=1's exact bytes would make two
        # peer-recv lines share a sha256 and break the "one unique match per payload"
        # assertion for the scheduled sequence. The 4-tuple is what F13 is testing.
        @{ name = 'F13 same key as seq=1'; seq = 13; payload = '17320000FFFF9F37' }
    )
    foreach ($n in $negative) {
        $payload = HexToBytes $n.payload
        # F13 keeps the ORIGINAL frame's dst/src 4-tuple: same session, same logical
        # socket, same generation, same dst port, so ensure_mapping must find the
        # existing key rather than allocate a second one.
        $frame = New-Cvlh2Frame $n.seq '127.0.0.1' 21345 '127.0.0.1' 62056 $payload 0x21
        [void]$sender2.Send($frame, $frame.Length, $ep2)
        $negStart += ("{0} {1}" -f (Get-Date -Format 'HH:mm:ss.fff'), $n.name)
        Write-Host ("[*] negative control: {0}" -f $n.name)
        Start-Sleep -Milliseconds 120
    }
} finally {
    $sender2.Close()
}
$negStart | Out-File -FilePath (Join-Path $out 'negative-controls.txt') -Encoding utf8

Start-Sleep -Milliseconds 1500
New-Item -ItemType File -Force -Path $stopFile | Out-Null
$exited = $false
for ($i = 0; $i -lt 300; $i++) {
    if ($proc.HasExited) { $exited = $true; break }
    Start-Sleep -Milliseconds 100
}
if (-not $exited) {
    Write-Host "[!] agent did not exit after the stop file"
    $proc.Kill()
    exit 1
}
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
# F3-A revision 2 split the old "no mapping" counter into two explicit reasons, so both are
# asserted: neither may fire for a datapath frame with a valid key.
$skipNotDp = Grab $summary 'skip not datapath:\s+(\d+)'
$skipTable = Grab $summary 'skip key table\s+:\s+(\d+)'
$maps = Grab $summary 'mappings created:\s+(\d+)'
$peerRecv = Grab $summary 'payloads recv\s+:\s+(\d+)'
$peerBytes = Grab $summary 'payload bytes\s+:\s+(\d+)'
$listenPort = Grab $summary 'listen port\s+:\s+(\d+)'
$fwSock = Grab $summary 'forward sock\s+:\s+(\S+) \(sender identity'
$firstSender = Grab $summary 'first sender\s+:\s+(\S+)'
$gaps = Grab $summary 'seq gaps=(\d+)'
$dups = Grab $summary 'duplicates=(\d+)'
$ooo = Grab $summary 'out_of_order=(\d+)'

Write-Host "[*] summary: seen=$seen forwarded=$fwd bytes=$fbytes fail=$ffail skip(dp=$skipNotDp table=$skipTable) peer=$peerRecv/$peerBytes"

# Totals cover 10 scheduled frames + 3 negative controls (F11/F12/F13).
Check 'all 13 frames reached the Agent (10 scheduled + 3 negative controls)' ($seen -eq '13') "seen=$seen"
Check 'forwarded == 13 (one per frame, peer never replies)' ($fwd -eq '13') "forwarded=$fwd"
Check 'forward bytes == 13 x 8' ($fbytes -eq '104') "bytes=$fbytes"
Check 'forward fail == 0' ($ffail -eq '0') "fail=$ffail"
Check 'skip not datapath == 0 (every frame was a 62056 datapath frame)' ($skipNotDp -eq '0') "skip=$skipNotDp"
Check 'skip key table == 0 (one key held, table never filled)' ($skipTable -eq '0') "skip=$skipTable"
# F13 re-sends with the exact 4-tuple of seq=1 on purpose: if this became 2, the key would
# be built from the frame counter instead of the (session, socket, generation, dst) tuple.
Check 'mappings created == 1 (F13 reuses the seq=1 key, no second key)' ($maps -eq '1') "maps=$maps"
Check 'peer received 13 payloads' ($peerRecv -eq '13') "peer=$peerRecv"
Check 'peer bytes == 104' ($peerBytes -eq '104') "peerBytes=$peerBytes"
Check "peer listen port == $peerPort (never 62056)" ($listenPort -eq "$peerPort") "listen=$listenPort"

# Sender identity binding (F3-A audit item): what the peer saw must BE this Agent's forward
# socket, not some other process that happened to send to the listener port.
$sockIp = if ($fwSock -match '^([\d.]+):(\d+)$') { $Matches[1] } else { '' }
$sockPort = if ($fwSock -match '^([\d.]+):(\d+)$') { $Matches[2] } else { '' }
$senderIp = if ($firstSender -match '^([\d.]+):(\d+)$') { $Matches[1] } else { '' }
$senderPort = if ($firstSender -match '^([\d.]+):(\d+)$') { $Matches[2] } else { '' }
# Loopback renders the wildcard bind (0.0.0.0) as 127.0.0.1 on the wire; treat them equal (F3A-REVIEW-3 M7 pattern).
$ipOk = ($sockIp -ne '' -and ($sockIp -eq $senderIp -or ($sockIp -eq '0.0.0.0' -and $senderIp -eq '127.0.0.1')))
Check 'peer first sender == agent forward socket (IP + port match, never 62056)' `
    ($ipOk -and $sockPort -ne '' -and $sockPort -eq $senderPort -and $sockPort -ne '62056') "sock=$fwSock sender=$firstSender"
#
# Without them this suite could only ever say "0 duplicates, 0 gaps", which is also what a
# broken or unreached counter says. F11/F12 are deliberately wrong frames; requiring the
# counters to move is what turns "we saw no problem" into "we can see this problem".
# ---------------------------------------------------------------------------------------
Check 'duplicates == 1 (F11 duplicate was detected, not silently merged)' ($dups -eq '1') "dups=$dups"
Check 'seq gaps == 1 (F12 gap was detected)' ($gaps -eq '1') "gaps=$gaps"
$missing = Grab $summary 'missing_frames=(\d+)'
Check 'missing_frames == 1 (one frame never arrived, counted exactly)' ($missing -eq '1') "missing=$missing"
Check 'out_of_order == 0 (all out-of-order traffic was a duplicate, not a reorder)' ($ooo -eq '0') "ooo=$ooo"

# D4's "at most ONE 20B probe per run" is a hard design constraint (codex D4) and it was
# previously unguarded: it could have degraded to 10 probes and the suite would stay green.
$replySent = Grab $summary 'reply sent\s+:\s+(\d+)'
$alreadySent = Grab $summary 'already_sent=(\d+)'
Check 'D4 holds: exactly 1 datapath reply in the whole run' ($replySent -eq '1') "reply=$replySent"
Check 'D4 holds: the other 12 frames were declined with already_sent' ($alreadySent -eq '12') "already=$alreadySent"
Check 'no retransmit: forwarded == peer received' ($fwd -eq $peerRecv) "fwd=$fwd peer=$peerRecv"
Check 'summary declares the loopback prototype boundary' ($summary -match 'LOOPBACK PROTOTYPE') 'no boundary note'

$flog = Join-Path $out 'forward-log.txt'
$logged = @()
if (Test-Path $flog) { $logged = [IO.File]::ReadAllLines($flog, [Text.Encoding]::UTF8) }
$fwdLines = @($logged | Where-Object { $_ -match ' forward seq=' })
$peerLines = @($logged | Where-Object { $_ -match ' peer-recv n=' })
Check 'forward-log has 13 forward lines (10 scheduled + 3 negative)' ($fwdLines.Count -eq 13) "lines=$($fwdLines.Count)"
Check 'forward-log has 13 peer-recv lines' ($peerLines.Count -eq 13) "lines=$($peerLines.Count)"

# The first ten forward lines must be the scheduled sequence, in order. The negative
# controls are sent strictly afterwards, so splitting by position is well defined; matching
# by seq alone is not, because F11 deliberately repeats seq=10.
$schedLines = @($fwdLines | Select-Object -First 10)
$schedPeer = @($peerLines | Select-Object -First 10)
$negLines = @($fwdLines | Select-Object -Skip 10)

# seq must appear as 1..10 in that order, exactly once each.
$seqs = @()
foreach ($line in $schedLines) {
    $m = [regex]::Match($line, 'forward seq=(\d+)')
    if ($m.Success) { $seqs += [int]$m.Groups[1].Value }
}
$expected = @(1, 2, 3, 4, 5, 6, 7, 8, 9, 10)
$seqOk = ($seqs.Count -eq $expected.Count)
if ($seqOk) {
    for ($i = 0; $i -lt $expected.Count; $i++) {
        if ($seqs[$i] -ne $expected[$i]) { $seqOk = $false; break }
    }
}
Check 'scheduled forward-log seq order is exactly 1..10 (continuous, no dup, no reorder)' $seqOk ("seqs=" + ($seqs -join ','))

# Each payload must be preserved verbatim, proven three ways: the sender's own bytes (sha256
# computed here), the forward-log line, and the peer side. F3-A revision 2 added sha256 to both
# log lines, so a head-of-buffer comparison is no longer the only option - it was one of the
# audit's weak assertions.
function Get-Sha256Hex([byte[]]$bytes) {
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($bytes)) -replace '-', '').ToLowerInvariant() }
    finally { $sha.Dispose() }
}

$headOk = $true
$headDetail = ''
for ($i = 0; $i -lt $suffixes.Count; $i++) {
    $payload = HexToBytes ('17320000FFFF' + $suffixes[$i])
    $want = Get-Sha256Hex $payload
    $head = ([BitConverter]::ToString($payload) -replace '-', '').ToLowerInvariant()
    $seq = $i + 1
    # Restrict to the scheduled slice: F11 deliberately repeats seq=10, so a whole-log
    # match on "seq=10" would find two lines and fail for the wrong reason.
    $fwdLine = @($schedLines | Where-Object { $_ -match ("forward seq=$seq\s") })
    $peerLine = @($schedPeer | Where-Object { $_ -match ("sha256=$want\b") })
    $fwdShaOk = ($fwdLine.Count -eq 1 -and $fwdLine[0] -match "sha256=$want\b")
    $payloadOk = ($fwdLine.Count -eq 1 -and $fwdLine[0] -match "payload=$head\b")
    if (-not ($fwdShaOk -and $payloadOk -and $peerLine.Count -eq 1)) {
        $headOk = $false
        $headDetail += ("seq{0}[fwd={1} sha={2} payload={3} peer={4}] " -f $seq, $fwdLine.Count, [int]$fwdShaOk, [int]$payloadOk, $peerLine.Count)
    }
}
Check 'every scheduled payload reached the peer byte-identical (10 payloads, sha256 + bytes three-way)' $headOk $headDetail

# The gaps recorded in forward-log must follow the S5 schedule (tolerance scaled).
$stamps = @()
foreach ($line in $schedLines) {
    $m = [regex]::Match($line, '^(\d\d):(\d\d):(\d\d)\.(\d\d\d)')
    if ($m.Success) {
        $ms = ([int]$m.Groups[1].Value * 3600 + [int]$m.Groups[2].Value * 60 + [int]$m.Groups[3].Value) * 1000 + [int]$m.Groups[4].Value
        $stamps += $ms
    }
}
$gapOk = ($stamps.Count -eq 10)
$gapDetail = ''
if ($gapOk) {
    $tol = 250 * $TimeScale   # F3C-REVIEW-2 R2-L4: 650ms tolerance could not tell 0.5s from 1s; 250ms can
    for ($i = 1; $i -lt $stamps.Count; $i++) {
        $observed = $stamps[$i] - $stamps[$i - 1]
        $want = $schedule[$i] * 1000 * $TimeScale
        if ([Math]::Abs($observed - $want) -gt $tol) {
            $gapOk = $false
            $gapDetail += ("gap{0}: observed {1}ms want {2}ms; " -f $i, $observed, [int]$want)
        }
    }
} else {
    $gapDetail = "parsed $($stamps.Count) of 10 timestamps"
}
Check 'recorded gaps follow the S5 backoff schedule within tolerance' $gapOk $gapDetail

Write-Host ''
if ($fail -eq 0) {
    Write-Host "F3C-BACKOFF-SELFTEST: PASS (evidence: $out)"
    exit 0
}
Write-Host "F3C-BACKOFF-SELFTEST: FAIL ($fail assertion(s), evidence: $out)"
exit 1
