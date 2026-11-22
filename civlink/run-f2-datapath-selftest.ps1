# run-f2-datapath-selftest.ps1 - CivLink F2 datapath observation mechanical self-test driver
#
# Starts the Agent in --simulate-datapath mode (codex F2 review D2/D4 constraints):
#   * agent NEVER binds :62056; its reply socket is an independent ephemeral UDP socket
#   * --bind-ip 127.0.0.1 with --loopback-selftest -> fail-closed, self-test only
#   * at most ONE 20-byte fixed probe per run, only to a confirmed-local non-zero source
#
# The driver owns a listener on 127.0.0.1:<probePort> and crafts real CVLH2 frames over
# UDP to 127.0.0.1:34718 that mimic outbound datapath traffic:
#   A. src=127.0.0.1:<probePort> dst=127.0.0.1:62056 4B  -> local source: agent sends the
#      20B probe to the listener (observable!), reply_sent=1
#   B. same src again                                    -> already_sent=1, no second probe
#   C. src=127.0.0.1:0 dst=62056                         -> no_endpoint=1 (unbound first frame)
#   D. src=192.168.31.59:<probePort> dst=62056           -> not_local=1 (not confirmed local)
#
# Expected deterministic outcome:
#   datapath: frames seen=4, on 62056=4, reply sent=1, skipped no_endpoint=1 not_local=1
#             already_sent=1, send fail=0, mode=LOOPBACK SELF-TEST
#   listener: receives exactly ONE 20B datagram whose first 4 bytes are 'CVLD'
#
# Everything here is mechanical: no Civ6, no network beyond loopback, no claim about the
# game. A PASS means "the agent observed crafted datapath frames via the CVLH2 chain and
# applied the D4 single-probe rule to a confirmed-local source endpoint".
#
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File run-f2-datapath-selftest.ps1
#        [-OutRoot <dir>]
# Exit: 0 all checks passed, 1 a check failed, 2 a tool or precondition is missing.
[CmdletBinding()]
param(
    [string]$OutRoot = ''
)
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$agent = Join-Path $here 'civlink-agent.exe'

$fail = 0
function Check($what, $ok, $detail) {
    if ($ok) { Write-Host ("  PASS {0,-56} {1}" -f $what, $detail) }
    else { Write-Host ("  FAIL {0,-56} {1}" -f $what, $detail); $script:fail++ }
}

Write-Host "CivLink F2 datapath observation self-test"
if (-not (Test-Path $agent)) { Write-Host "[!] missing $agent - build first"; exit 2 }

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
if ($OutRoot -ne '') { $captures = $OutRoot }
else {
    $repoRoot = Split-Path (Split-Path $here -Parent) -Parent
    if (Test-Path (Join-Path $repoRoot 'M0A')) { $captures = Join-Path $repoRoot 'M0A\captures' }
    else { $captures = Join-Path $here 'captures' }
}
if (-not (Test-Path $captures)) { New-Item -ItemType Directory -Force -Path $captures | Out-Null }
$outDir = Join-Path $captures "F2-datapath-selftest-$stamp"
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
Write-Host "[*] evidence dir: $outDir"

# The IPC port must be free; a leftover Agent would silently steal the frames.
$busy = Get-NetUDPEndpoint -LocalPort 34718 -ErrorAction SilentlyContinue
if ($busy) {
    Write-Host "[!] 127.0.0.1:34718 is already in use by pid=$($busy.OwningProcess) - stop it first"
    exit 2
}

# Driver-side probe listener: the agent must send its D4 20B probe here.
$probePort = 21345
$listener = [System.Net.Sockets.UdpClient]::new([System.Net.IPEndPoint]::new([System.Net.IPAddress]::Parse('127.0.0.1'), $probePort))
$listener.Client.ReceiveTimeout = 3000

function New-Cvlh2Frame([int]$seq, [string]$srcIp, [int]$srcPort, [string]$dstIp, [int]$dstPort, [byte[]]$payload, [byte]$flags = 0x00) {
    # 42-byte CVLH2 header (cvlh2.h): magic 'CVLH' ver=2 dir=0, then u32/u64 LE fields,
    # raw sin_addr bytes for IPv4, port as big-endian wire value.
    $h = [byte[]]::new(42)
    $h[0] = 0x43; $h[1] = 0x56; $h[2] = 0x4C; $h[3] = 0x48   # 'CVLH'
    $h[4] = 2; $h[5] = 0                                      # ver, dir=hook->agent
    [BitConverter]::GetBytes([uint32]$seq).CopyTo($h, 6)       # seq u32 LE
    [BitConverter]::GetBytes([uint64]1).CopyTo($h, 10)         # session_id
    [BitConverter]::GetBytes([uint32]1).CopyTo($h, 18)         # logical_socket_id
    [BitConverter]::GetBytes([uint32]1).CopyTo($h, 22)         # socket_generation
    $h[26] = 2                                                 # af = AF_INET
    $s = [System.Net.IPAddress]::Parse($srcIp).GetAddressBytes()  # raw network-order bytes
    $d = [System.Net.IPAddress]::Parse($dstIp).GetAddressBytes()
    $s.CopyTo($h, 27); $d.CopyTo($h, 33)
    $sp = [BitConverter]::GetBytes([uint16]$srcPort); [Array]::Reverse($sp); $sp.CopyTo($h, 31)  # BE
    $dp = [BitConverter]::GetBytes([uint16]$dstPort); [Array]::Reverse($dp); $dp.CopyTo($h, 37)  # BE
    $h[39] = $flags
    [BitConverter]::GetBytes([uint16]$payload.Length).CopyTo($h, 40)  # u16 LE
    $buf = [byte[]]::new(42 + $payload.Length)
    $h.CopyTo($buf, 0); $payload.CopyTo($buf, 42)
    return ,$buf
}

function Send-Frame([byte[]]$frame) {
    $sender = [System.Net.Sockets.UdpClient]::new()
    $ep = [System.Net.IPEndPoint]::new([System.Net.IPAddress]::Parse('127.0.0.1'), 34718)
    [void]$sender.Send($frame, $frame.Length, $ep)
    $sender.Close()
}

Write-Host "[*] starting agent with --simulate-datapath --bind-ip 127.0.0.1 --loopback-selftest (25 s window)"
$log = Join-Path $outDir 'agent-console.txt'
$stopPath = Join-Path $outDir 'stop'
$agentProc = Start-Process -FilePath $agent -ArgumentList @(
    '--listen-seconds', '25', '--out-dir', $outDir,
    '--simulate-datapath', '--bind-ip', '127.0.0.1', '--loopback-selftest', '--quiet',
    '--stop-file', $stopPath
) -PassThru -WindowStyle Hidden -RedirectStandardOutput $log
Start-Sleep -Milliseconds 1200
if ($agentProc.HasExited) {
    Write-Host "[!] agent exited immediately (code $($agentProc.ExitCode)); see $log"
    Get-Content $log -ErrorAction SilentlyContinue | ForEach-Object { Write-Host "    $_" }
    exit 2
}
Write-Host "[*] agent pid=$($agentProc.Id)"

# Frame A: confirmed local source -> the agent must send exactly ONE 20B probe.
$magic4 = [byte[]](0x8D, 0xE8, 0xFC, 0x70)
$frameA = New-Cvlh2Frame 1 '127.0.0.1' $probePort '127.0.0.1' 62056 $magic4 0x00
Send-Frame $frameA
Start-Sleep -Milliseconds 800
$probeBytes = $null
try {
    $remote = New-Object System.Net.IPEndPoint([System.Net.IPAddress]::Any, 0)
    $probeBytes = $listener.Receive([ref]$remote)
} catch { }
$probeOk = ($null -ne $probeBytes) -and ($probeBytes.Length -eq 20) -and
           ($probeBytes[0] -eq 0x43 -and $probeBytes[1] -eq 0x56 -and $probeBytes[2] -eq 0x4C -and $probeBytes[3] -eq 0x44)  # 'CVLD'
Check "one 20-byte 'CVLD' probe reached the listener" $probeOk "len=$($probeBytes.Length)"

# Frame B: same local source again -> already_sent, NO second probe.
Send-Frame (New-Cvlh2Frame 2 '127.0.0.1' $probePort '127.0.0.1' 62056 $magic4 0x00)
Start-Sleep -Milliseconds 800
$secondProbe = $null
try {
    $remote2 = New-Object System.Net.IPEndPoint([System.Net.IPAddress]::Any, 0)
    $secondProbe = $listener.Receive([ref]$remote2)
} catch { }
Check "no second probe after already_sent" ($null -eq $secondProbe) "second=$($secondProbe.Length)"

# Frame C: source port 0 (unbound first frame) -> recorded, never answered.
Send-Frame (New-Cvlh2Frame 3 '127.0.0.1' 0 '127.0.0.1' 62056 $magic4 0x00)
# Frame D: source not the confirmed local bind_ip -> not_local, never answered.
Send-Frame (New-Cvlh2Frame 4 '192.168.31.59' $probePort '127.0.0.1' 62056 $magic4 0x00)
Start-Sleep -Milliseconds 800

# Clean stop via the stop file (natural finalize writes summary.txt).
if (-not $agentProc.HasExited) {
    [IO.File]::WriteAllText($stopPath, 'stop')
    if (-not $agentProc.WaitForExit(15000)) {
        Write-Host "[!] agent did not exit after stop file - stopping it"
        Stop-Process -Id $agentProc.Id -Force
        $fail++
    }
}

$summaryPath = Join-Path $outDir 'summary.txt'
if (-not (Test-Path $summaryPath)) {
    Write-Host "[!] agent wrote no summary.txt"
    Get-Content $log -ErrorAction SilentlyContinue | ForEach-Object { Write-Host "    $_" }
    exit 1
}
$summary = Get-Content $summaryPath
$text = $summary -join "`n"
Write-Host "--- agent summary ---"
$summary | ForEach-Object { Write-Host "    $_" }

function Grab($pattern) {
    $m = [regex]::Match($text, $pattern)
    if ($m.Success) { return [int64]$m.Groups[1].Value }
    return $null
}
$dpFrames = Grab 'frames seen     : (\d+)'
$dpOnPort = Grab 'frames on 62056 : (\d+)'
$dpReply = Grab 'reply sent      : (\d+)'
$dpNoEp = Grab 'no_endpoint=(\d+)'
$dpNotLocal = Grab 'not_local=(\d+)'
$dpAlready = Grab 'already_sent=(\d+)'
$dpSendFail = Grab 'send fail       : (\d+)'
$dpMode = [regex]::Match($text, 'mode\s+: (LOOPBACK SELF-TEST[^\n]*)')

Check "datapath frames seen == 4" ($dpFrames -eq 4) "seen=$dpFrames"
Check "frames on 62056 == 4 (dst port is the F2 question)" ($dpOnPort -eq 4) "on62056=$dpOnPort"
Check "reply sent == 1 (D4: at most one probe)" ($dpReply -eq 1) "reply=$dpReply"
Check "skipped no_endpoint == 1 (src port 0)" ($dpNoEp -eq 1) "no_endpoint=$dpNoEp"
Check "skipped not_local == 1 (192.168.31.59 != bind_ip)" ($dpNotLocal -eq 1) "not_local=$dpNotLocal"
Check "already_sent == 1 (second local frame)" ($dpAlready -eq 1) "already=$dpAlready"
Check "send fail == 0" ($dpSendFail -eq 0) "fail=$dpSendFail"
Check "summary marks LOOPBACK SELF-TEST mode" ($dpMode.Success -and $dpMode.Groups[1].Value.Contains('LOOPBACK SELF-TEST')) "mode=$($dpMode.Groups[1].Value)"

# The datapath log must hold one line per frame (4 lines) plus the reply line.
$dpLog = Join-Path $outDir 'datapath-log.txt'
$dpLogLines = if (Test-Path $dpLog) { (Get-Content $dpLog | Where-Object { $_ -and -not $_.StartsWith('#') }).Count } else { 0 }
Check "datapath-log.txt has 4 frame lines + 1 reply line" ($dpLogLines -eq 5) "lines=$dpLogLines"

Write-Host ""
if ($fail -eq 0) {
    Write-Host "F2-DATAPATH-SELFTEST: PASS (D4 single-probe rule verified mechanically; loopback only)"
    Write-Host "[*] evidence: $outDir"
    exit 0
} else {
    Write-Host "F2-DATAPATH-SELFTEST: FAIL ($fail failed check(s))"
    Write-Host "[*] evidence: $outDir"
    exit 1
}
