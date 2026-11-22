# run-b1-realcap-selftest.ps1 - B1 real advertisement capture mechanical evidence
#
# Tests the B1 agent capability (docs/B1-REAL-ADVERTISEMENT-CAPTURE-20261117.md):
#   C1 = P2 loopback capture: broadcast the 22 real fixture pages (they ARE real pages -
#        1104 B with magic 59 60 69 9B) to 255.255.255.255:62900 while the agent runs with
#        --sim-lan-listen 0.0.0.0 --sim-real-capture; assert the agent captures them
#        byte-for-byte (real-page-01..22.bin == reply-01..22.bin sent).
#   C2 = P1 hook-chain capture: hand-encode a CVLH2 frame carrying a full page payload and
#        send it to the agent IPC port; assert it is captured as a real page.
#   C3 = reply upgrade: after a full 22-page capture, send 100 magic datagrams (simulating a
#        B-machine refresh); assert the replies equal the captured pages (not the fixture,
#        whose room name is anonymized).
#   C4 = negative: send noise (wrong size / wrong magic) and assert it is rejected (not
#        captured) and the rejected counter grows.
#
# Run elevated once (UAC). Exit codes: 0 = PASS all, 1 = FAIL, 2 = setup error.
# Evidence lands in <out>\ (default docs\reports\b1\run-<timestamp>\).
param(
    [string]$Out = ''
)
$ErrorActionPreference = 'Stop'
$script:Checks = 0
$script:Failures = @()
$script:TopLevelException = $null

# Wrap the entire body so a crash anywhere leaves a diagnostic file instead of a
# silent powershell.exe termination with an unexplained exit code.
try {

function Check([string]$Name, [string]$Detail, [bool]$Ok) {
    $script:Checks++
    if ($Ok) {
        Write-Host "  PASS $Name" -ForegroundColor Green
    } else {
        $script:Failures += $Name
        Write-Host "  FAIL $Name - $Detail" -ForegroundColor Red
    }
}

function Get-Sha256Hex([string]$Path) {
    $h = Get-FileHash -Path $Path -Algorithm SHA256
    $h.Hash.ToLower()
}

$root = 'C:\Users\dd\Desktop\injciv6-v0.3.3\CivLink-M0A-audit'
$agentExe = "$root\civlink\agent\target\debug\civlink-agent.exe"
$fixture = "$root\civlink\fixture-reply-set"
$relayDir = "$root\civlink\relay"

if (-not (Test-Path $agentExe)) { Write-Error "agent binary missing: $agentExe"; exit 2 }
if (-not (Test-Path "$fixture\reply-01.bin")) { Write-Error "fixture missing: $fixture"; exit 2 }

if ($Out -eq '') {
    $Out = Join-Path $root "docs\reports\b1\run-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
} elseif (-not [IO.Path]::IsPathRooted($Out)) {
    # A relative -Out would land in the caller's cwd (e.g. civlink\) - force it under
    # the project root so evidence always lands in CivLink-M0A-audit\docs\reports\b1\.
    $Out = Join-Path $root $Out
}
New-Item -ItemType Directory -Path $Out -Force | Out-Null

# Fixture pages: the source of truth for the "real pages" in this test. The fixture pages
# themselves ARE Civ6 advertisement pages (1104 B, magic 59 60 69 9B) - the only thing the
# fixture differs from a live host by is the anonymized room name, which is why C3 compares
# against the captured bytes (not the fixture), and C1 compares captured == sent.
$pages = @()
for ($i = 1; $i -le 22; $i++) {
    $p = Join-Path $fixture ("reply-{0:00}.bin" -f $i)
    $pages += ,[IO.File]::ReadAllBytes($p)
}

# ------------------------------------------------------------------ start the agent
# Kill any leftover civlink-agent from an earlier (failed) run: a stale agent holds all
# 100 discovery ports, which makes this run's agent fail to bind and exit with no output.
Get-Process civlink-agent -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Milliseconds 500

$agentOut = Join-Path $Out 'agent'
New-Item -ItemType Directory -Path $agentOut -Force | Out-Null
$stopFile = Join-Path $Out 'stop'
Remove-Item $stopFile -ErrorAction SilentlyContinue

# Async stdout/stderr collection via .NET Task (ReadToEndAsync): the agent writes
# ~22 eprintln lines during capture. BeginOutputReadLine event handlers run on a
# PS 5.1 background thread where $script:agentLog scope resolution can throw an
# uncaught thread exception that CRASHES powershell.exe (observed: script died at
# 'C4: negative controls' with exit 2 and no catch firing). Tasks avoid that.
$script:agentLog = [System.Collections.Generic.List[string]]::new()
$psi = [System.Diagnostics.ProcessStartInfo]::new()
$psi.FileName = $agentExe
$psi.Arguments = "--listen-seconds 45 --out-dir `"$agentOut`" --sim-lan-listen 0.0.0.0 " +
    "--simulate `"$fixture`" --sim-real-capture --sim-room-name CivLink-Test-Room-2222 " +
    "--stop-file `"$stopFile`" --quiet"
$psi.UseShellExecute = $false
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
$p = [System.Diagnostics.Process]::new()
$p.StartInfo = $psi
$null = $p.Start()
$stdoutTask = $p.StandardOutput.ReadToEndAsync()
$stderrTask = $p.StandardError.ReadToEndAsync()
$agentPid = $p.Id
Write-Host "agent started pid=$agentPid (45s window)"

Start-Sleep -Milliseconds 1200

# ------------------------------------------------------------------ C1: P2 loopback capture
Write-Host "C1: P2 loopback capture (broadcast 22 real pages to 255.255.255.255:62900)"
$c1Sock = [System.Net.Sockets.UdpClient]::new()
$c1Sock.EnableBroadcast = $true
$c1Target = [System.Net.IPEndPoint]::new([System.Net.IPAddress]::Broadcast, 62900)
$c1Sent = @()
for ($i = 0; $i -lt 22; $i++) {
    $null = $c1Sock.Send($pages[$i], $pages[$i].Length, $c1Target)
    $c1Sent += ,$pages[$i]
    Start-Sleep -Milliseconds 120
}
$c1Sock.Close()

# ------------------------------------------------------------------ C2: P1 hook-chain capture
# Hand-encode a CVLH2 v2 frame (FRAME_HDR = 42 B) carrying page 1's payload, per
# civlink/common/cvlh2.h:
#   magic "CVLH" @0 | ver=2 @4 | dir=0 @5 | seq u32le @6 | session u64le @10 |
#   logical_socket u32le @18 | gen u32le @22 | af=2 @26 | src ip @27 (network order) |
#   src port @31 (sin_port raw BIG endian) | dst ip @33 (network order) |
#   dst port @37 (BIG endian) | flags @39 | payload_len u16le @40 | payload @42
Write-Host "C2: P1 hook-chain capture (hand-encoded CVLH2 frame via agent IPC)"
function To-BigEndian16([uint16]$HostPort) {
    # sin_port holds the port in BIG-endian bytes; stored into the frame as-is. The LE
    # writer then writes those two bytes little-endian, so the u16 we pass is byte-swapped.
    return [uint16](($HostPort -band 0xFF) -shl 8) -bor ($HostPort -shr 8)
}
function Encode-Cvlh2([byte[]]$Payload, [uint32]$Seq, [uint64]$Session, [uint32]$SockId, [uint32]$Gen) {
    $frame = New-Object byte[] (42 + $Payload.Length)
    [Text.Encoding]::ASCII.GetBytes('CVLH').CopyTo($frame, 0)
    $frame[4] = 2      # ver
    $frame[5] = 0      # dir HOOK_TO_AGENT
    [BitConverter]::GetBytes($Seq).CopyTo($frame, 6)          # u32 le
    [BitConverter]::GetBytes($Session).CopyTo($frame, 10)     # u64 le
    [BitConverter]::GetBytes($SockId).CopyTo($frame, 18)      # u32 le
    [BitConverter]::GetBytes($Gen).CopyTo($frame, 22)         # u32 le
    $frame[26] = 2      # af INET
    # src ip 127.0.0.1: network-order bytes 7f 00 00 01 -> u32 LE value 0x0100007f
    [BitConverter]::GetBytes([uint32]0x0100007f).CopyTo($frame, 27)
    [BitConverter]::GetBytes((To-BigEndian16 62000)).CopyTo($frame, 31)  # src port (big-endian raw)
    # dst ip 255.255.255.255 -> u32 LE 0xffffffff (PowerShell: use MaxValue, not 0xffffffff)
    [BitConverter]::GetBytes([uint32]::MaxValue).CopyTo($frame, 33)
    [BitConverter]::GetBytes((To-BigEndian16 62900)).CopyTo($frame, 37)  # dst port (big-endian raw)
    $frame[39] = 0x04  # flags DISCOVERY
    [BitConverter]::GetBytes([uint16]$Payload.Length).CopyTo($frame, 40) # payload_len u16 le
    $Payload.CopyTo($frame, 42)
    return $frame
}

$c2Payload = $pages[0]
$c2Frame = Encode-Cvlh2 -Payload $c2Payload -Seq 1 -Session 1 -SockId 1 -Gen 1
$c2Sock = [System.Net.Sockets.UdpClient]::new()
$c2Sock.Connect([System.Net.IPAddress]::Loopback, 34718)
$null = $c2Sock.Send($c2Frame, $c2Frame.Length)
$c2Sock.Close()

# ------------------------------------------------------------------ C4a: noise (wrong size)
Write-Host "C4: negative controls"
try {
    $noiseSock = [System.Net.Sockets.UdpClient]::new()
    $noiseSock.EnableBroadcast = $true
    $noiseTarget = [System.Net.IPEndPoint]::new([System.Net.IPAddress]::Broadcast, 62900)
    $noise1 = New-Object byte[] 64   # wrong size (not 1104)
    $noise2 = New-Object byte[] 1104 # right size, wrong magic (zeros)
    Write-Host "  [step] C4 send noise1..."
    $null = $noiseSock.Send($noise1, 64, $noiseTarget)
    Write-Host "  [step] C4 send noise2..."
    $null = $noiseSock.Send($noise2, 1104, $noiseTarget)
    Write-Host "  [step] C4 close..."
    $noiseSock.Close()
    Write-Host "  [step] C4 done"
} catch {
    Write-Host "C4 EXCEPTION: $($_.Exception.GetType().FullName): $($_.Exception.Message)" -ForegroundColor Red
    $dump = "C4 EXCEPTION: $($_.Exception.GetType().FullName): $($_.Exception.Message)`n$($_.ScriptStackTrace)"
    Set-Content (Join-Path $Out 'c4-exception.txt') -Value $dump -Encoding UTF8
}

# ------------------------------------------------------------------ wait for capture + C3 magic burst
try {
    Write-Host "  [step] C3: pre-sleep..."
    Start-Sleep -Seconds 2
    Write-Host "C3: reply upgrade (100 magic burst after capture)"
    $magic = [byte[]](0x8D, 0xE8, 0xFC, 0x70)
    Write-Host "  [step] C3: new UdpClient..."
    $mSock = [System.Net.Sockets.UdpClient]::new()
    $mSock.EnableBroadcast = $true
    Write-Host "  [step] C3: bind 54322..."
    $mSock.Client.Bind([System.Net.IPEndPoint]::new([System.Net.IPAddress]::Any, 54322))
    $mTarget = [System.Net.IPEndPoint]::new([System.Net.IPAddress]::Broadcast, 62900)
    Write-Host "  [step] C3: send 100 magic..."
    for ($i = 0; $i -lt 100; $i++) {
        $null = $mSock.Send($magic, 4, $mTarget)
    }
    Write-Host "  [step] C3: receive loop..."
    # receive the reply pages
    $c3Recv = @()
    $mSock.Client.ReceiveTimeout = 3000
    $deadline = [DateTime]::UtcNow.AddSeconds(8)
    while ([DateTime]::UtcNow -lt $deadline) {
        try {
            $ep = New-Object System.Net.IPEndPoint([System.Net.IPAddress]::Any, 0)
            $data = $mSock.Receive([ref]$ep)
            $c3Recv += ,$data
            if ($c3Recv.Count -ge 22) { break }
        } catch { break }
    }
    Write-Host "  [step] C3: recv done, count=$($c3Recv.Count)"
    $mSock.Close()
    Write-Host "  [step] C3 done"
} catch {
    Write-Host "C3 EXCEPTION: $($_.Exception.GetType().FullName): $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "  stack: $($_.ScriptStackTrace)" -ForegroundColor Red
    $dump = "C3 EXCEPTION: $($_.Exception.GetType().FullName): $($_.Exception.Message)`n$($_.ScriptStackTrace)"
    Set-Content (Join-Path $Out 'c3-exception.txt') -Value $dump -Encoding UTF8
}

# ------------------------------------------------------------------ stop the agent cleanly
[IO.File]::WriteAllText($stopFile, 'stop')
Start-Sleep -Seconds 1
if (-not $p.HasExited) { $null = $p.WaitForExit(15000) }
if (-not $p.HasExited) { $p.Kill() }
# collect async output (Task.Result blocks until the pipe drains; safe after exit/kill)
try { $stdoutText = $stdoutTask.Result } catch { $stdoutText = '' }
try { $stderrText = $stderrTask.Result } catch { $stderrText = '' }
if ($stdoutText) { foreach ($line in ($stdoutText -split "`r?`n")) { if ($line) { $script:agentLog.Add("[out] $line") } } }
if ($stderrText) { foreach ($line in ($stderrText -split "`r?`n")) { if ($line) { $script:agentLog.Add("[err] $line") } } }

# ------------------------------------------------------------------ assertions
Write-Host "`nAssertions:"
# A0: agent produced output (did not die at startup on bind failure)
$logText = $script:agentLog -join "`n"
$hasCapture = $logText -match 'real advertisement page 1/22 captured'
Check 'A0 agent capture log seen' "lines=$($script:agentLog.Count)" ($hasCapture)
# A1: agent exited (window may expire naturally before stop file is seen; accept either)
Check 'A1 agent exited' "exit code $($p.ExitCode)" ($p.HasExited)

# A2: C1 captured 22 real pages (C2's frame carries page 1's bytes again - a duplicate
# that must NOT inflate the set; the dedup keeps exactly 22 files)
$captured = Get-ChildItem (Join-Path $agentOut 'real-page-*.bin') -ErrorAction SilentlyContinue
Check 'A2 22 pages captured' "got $($captured.Count)" ($captured.Count -eq 22)

# A3: C1 captured pages == sent pages byte-for-byte
$matchAll = $true
for ($i = 0; $i -lt 22; $i++) {
    $cp = Join-Path $agentOut ("real-page-{0:00}.bin" -f ($i + 1))
    if (-not (Test-Path $cp)) { $matchAll = $false; break }
    $cb = [IO.File]::ReadAllBytes($cp)
    if ($cb.Length -ne $pages[$i].Length) { $matchAll = $false; break }
    for ($j = 0; $j -lt $cb.Length; $j++) {
        if ($cb[$j] -ne $pages[$i][$j]) { $matchAll = $false; break }
    }
    if (-not $matchAll) { break }
}
Check 'A3 captured == sent (byte-exact)' '' $matchAll

# A4: manifest exists and lists 22 pages with sha256
$manifest = Join-Path $agentOut 'real-ad-manifest.txt'
$mText = if (Test-Path $manifest) { [IO.File]::ReadAllText($manifest, [Text.Encoding]::UTF8) } else { '' }
$mLines = ($mText -split "`n" | Where-Object { $_ -match '^page \d{2}: sha256=' }).Count
Check 'A4 manifest lists 22 pages' "lines=$mLines" ($mLines -eq 22)

# A5: summary has the B1 block with captured >= 22
$summary = Join-Path $agentOut 'summary.txt'
$sText = if (Test-Path $summary) { [IO.File]::ReadAllText($summary, [Text.Encoding]::UTF8) } else { '' }
$sCap = [regex]::Match($sText, 'captured\s+: (\d+)').Groups[1].Value
Check 'A5 summary captured >= 22' "captured=$sCap" ([int]$sCap -ge 22)

# A6 (audit S-2): C3 replies == captured pages (not anonymized fixture), ALL 22 pages compared
# byte-for-byte against the captured real-page-*.bin files.
$replyOk = $false
if ($c3Recv.Count -ge 22) {
    $replyOk = $true
    for ($pg = 1; $pg -le 22; $pg++) {
        $refPage = [IO.File]::ReadAllBytes((Join-Path $agentOut ("real-page-{0:D2}.bin" -f $pg)))
        if ($c3Recv[$pg - 1].Length -ne $refPage.Length) { $replyOk = $false; break }
        for ($j = 0; $j -lt $refPage.Length; $j++) {
            if ($c3Recv[$pg - 1][$j] -ne $refPage[$j]) { $replyOk = $false; break }
        }
        if (-not $replyOk) { break }
    }
}
Check 'A6 reply == captured pages (22/22 byte-exact)' "recv=$($c3Recv.Count) pages" ($c3Recv.Count -ge 22 -and $replyOk)

# A7 (audit R-2): rejected now counts ONLY a new distinct page beyond a full 22-page set.
# C4's two noise datagrams (wrong size / wrong magic) are NotAPage -> noise, NOT rejected.
# This run has no 23rd distinct page, so rejected must be exactly 0.
$sRej = [regex]::Match($sText, 'rejected\s+: (\d+)').Groups[1].Value
Check 'A7 rejected == 0 (C4 noise is noise, not rejection)' "rejected=$sRej" ([int]$sRej -eq 0)

# A8 (audit R-2): summary noise-on-discovery-port == 2 (exactly the two C4 noise datagrams).
$sNoise = [regex]::Match($sText, 'noise on disc\s+: (\d+)').Groups[1].Value
Check 'A8 noise counted == 2 (C4 only)' "noise=$sNoise" ([int]$sNoise -eq 2)

# A9 (audit S-1): identity - captured pages count == 22 == summary captured, plus the
# reconciliation identity: non-magic datagrams (22 C1 pages + 1 C2 dup + 2 C4 noise = 25)
# == captured + rejected + duplicates + noise.
Check 'A9 captured identity' "files=$($captured.Count) sum=$sCap" ($captured.Count -eq 22 -and [int]$sCap -eq 22)
$sDup = [regex]::Match($sText, 'duplicates\s+: (\d+)').Groups[1].Value
$sumNonMagic = [int]$sCap + [int]$sRej + [int]$sDup + [int]$sNoise
Check 'A13 identity non-magic == captured+rejected+duplicates+noise (25)' "sum=$sumNonMagic" ($sumNonMagic -eq 25)

# A10: manifest sha256 of page 01 == sha256 of real-page-01.bin
$mPage1 = [regex]::Match($mText, 'page 01: sha256=([0-9a-f]+)').Groups[1].Value
$hPage1 = Get-Sha256Hex (Join-Path $agentOut 'real-page-01.bin')
Check 'A10 manifest sha256 matches file' "$mPage1 == $hPage1" ($mPage1 -eq $hPage1)

# A11: agent window accounting - at least one reply socket answered (C3 magic burst)
$sRep = [regex]::Match($sText, 'replied sockets\s+: (\d+)').Groups[1].Value
Check 'A11 replied sockets >= 1' "replied=$sRep" ([int]$sRep -ge 1)

# A12: C2's frame carried page 1's bytes again; the dedup must count it as a duplicate
# (not as a 23rd captured page). duplicates >= 1 proves the P1+P2 double-delivery path.
$sDup = [regex]::Match($sText, 'duplicates\s+: (\d+)').Groups[1].Value
Check 'A12 duplicates >= 1 (P1/P2 dedup)' "duplicates=$sDup" ([int]$sDup -ge 1)

# A14 (audit R-3): the 100 C3 magic datagrams come from ONE source socket (54322); the first
# one is answered with the real pages (active set), the other 99 are dedup skips. So:
#   replies real == 1, replies fixture == 0, replies skipped == 99, and
#   replies real + fixture + skipped == requests seen (100).
$sReq = [regex]::Match($sText, 'requests seen\s+: (\d+)').Groups[1].Value
$sReal = [regex]::Match($sText, 'replies real\s+: (\d+)').Groups[1].Value
$sFix = [regex]::Match($sText, 'replies fixture\s+: (\d+)').Groups[1].Value
$sSkip = [regex]::Match($sText, 'replies skipped\s+: (\d+)').Groups[1].Value
$sumReplies = [int]$sReal + [int]$sFix + [int]$sSkip
Check 'A14 replies real+fixture+skipped == requests seen (100)' "sum=$sumReplies req=$sReq" ($sumReplies -eq [int]$sReq -and [int]$sReq -eq 100)
Check 'A14b replies real == 1 (answered with captured set)' "real=$sReal" ([int]$sReal -eq 1)
Check 'A14c replies fixture == 0 (no anonymized fallback was used)' "fixture=$sFix" ([int]$sFix -eq 0)

# ------------------------------------------------------------------ result
# On failure, dump the agent's own log to the console and into the evidence dir so the
# failing step is diagnosable (e.g. a bind failure leaves an empty agent dir).
if ($script:Failures.Count -gt 0) {
    Write-Host "Agent log (dumped for diagnosis):" -ForegroundColor Yellow
    $script:agentLog | ForEach-Object { Write-Host "  $_" }
}
$result = "B1-REALCAP-SELFTEST: $(if ($script:Failures.Count -eq 0) { 'PASS' } else { 'FAIL' }) ($script:Checks checks, $($script:Failures.Count) failures)"
Write-Host "`n$result"
if ($script:Failures.Count -gt 0) {
    Write-Host "Failures: $($script:Failures -join ', ')" -ForegroundColor Red
    $script:agentLog | Set-Content (Join-Path $Out 'agent-console.txt') -Encoding UTF8
}
$result | Set-Content (Join-Path $Out 'result.txt') -Encoding UTF8
# evidence manifest
$ev = Get-ChildItem $agentOut | ForEach-Object { "{0}`t{1}`t{2}" -f $_.Name, $_.Length, (Get-Sha256Hex $_.FullName) }
$ev += "result.txt`t$((Get-Item (Join-Path $Out 'result.txt')).Length)`t$(Get-Sha256Hex (Join-Path $Out 'result.txt'))"
$ev | Set-Content (Join-Path $Out 'evidence-sha256.txt') -Encoding UTF8
Write-Host "Evidence: $Out"
if ($script:Failures.Count -eq 0) { exit 0 } else { exit 1 }

} catch {
    # Top-level trap: whatever went wrong, write it down so the run is diagnosable.
    $script:TopLevelException = $_ 
    Write-Host "TOP-LEVEL EXCEPTION: $($_.Exception.GetType().FullName): $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "  at: $($_.InvocationInfo.ScriptName):$($_.InvocationInfo.ScriptLineNumber)" -ForegroundColor Red
    Write-Host "  stack: $($_.ScriptStackTrace)" -ForegroundColor Red
    $errText = "TOP-LEVEL EXCEPTION: $($_.Exception.GetType().FullName): $($_.Exception.Message)`n" +
        "at: $($_.InvocationInfo.ScriptName):$($_.InvocationInfo.ScriptLineNumber)`n$($_.ScriptStackTrace)"
    try { Set-Content (Join-Path $Out 'toplevel-exception.txt') -Value $errText -Encoding UTF8 } catch {}
    if ($p -and -not $p.HasExited) { try { $p.Kill() } catch {} }
    exit 3
}
