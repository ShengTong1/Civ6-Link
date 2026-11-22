# run-m0e-completion-selftest.ps1
#
# M0-E discovery completion self-test (docs/M0E-DISCOVERY-COMPLETION-20261118.md).
#
# WHAT THIS PROVES (mechanical, loopback, no game process):
#   1. a client magic on an Agent-owned discovery port (62902) is relayed to the
#      configured replay target as ONE 4-byte datagram (not 100, not re-broadcast);
#   2. the pages the target answers are forwarded back to the client verbatim and
#      from the very port the client probed (so the client cannot tell them apart
#      from a real host's reply);
#   3. when the target stays silent the client receives NOTHING (fail-closed) --
#      the Agent never invents an advertisement;
#   4. the cross-flag rules hold: completion requires --sim-lan-listen, rejects
#      --simulate and --sim-real-capture, implies --reserve-62900, and refuses a
#      non-loopback replay target.
#
# WHAT THIS DOES NOT PROVE:
#   * that real Civilization VI answers the replay (measured separately on a live
#     hosted room: M0A\captures\C3-loopback-replay-20261118-2235 and
#     M0A\captures\C3-fullchain-20261118-2240);
#   * cross-machine behaviour of any kind;
#   * that a real client accepts the forwarded pages (that needs two real hosts).
#   Simulated/mechanical evidence only. NOT a two-real-hosts result, NOT E2-B/E3.
#
# The "game" here is a plain UDP socket on 127.0.0.1:62900 answering 22 pages of
# 1104 B with the CVLH2 page magic 59 60 69 9B. It is a fixture, not a game.
#
# Exit codes: 0 = all checks passed, 1 = a check failed, 2 = setup problem.

[CmdletBinding()]
param(
    [string]$OutRoot = '',
    [int]$ReplayPort = 62900,
    [int]$ProbePort = 62902,
    [int]$ListenSeconds = 12,
    [int]$TimeoutMs = 1500
)

$ErrorActionPreference = 'Stop'
$script:Checks = 0
$script:Failures = @()
$script:ExpectChecks = 45

function Check([string]$name, [bool]$cond) {
    $script:Checks++
    if ($cond) {
        Write-Host ("  PASS  {0}" -f $name)
    } else {
        Write-Host ("  FAIL  {0}" -f $name) -ForegroundColor Red
        $script:Failures += $name
    }
}

function Get-Sha256Hex([string]$path) {
    if (-not (Test-Path $path)) { return '(missing)' }
    (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
}

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$agent = Join-Path $here 'civlink-agent.exe'
if (-not (Test-Path $agent)) { Write-Host "[!] civlink-agent.exe not found next to this script"; exit 2 }

if ([string]::IsNullOrWhiteSpace($OutRoot)) {
    $stamp = (Get-Date).ToString('yyyyMMdd-HHmmss')
    $OutRoot = Join-Path (Join-Path (Split-Path -Parent $here) 'M0A\captures') "M0E-completion-$stamp"
}
New-Item -ItemType Directory -Force -Path $OutRoot | Out-Null

$pageSize = 1104
$pageCount = 22
$magic = [byte[]](0x8D, 0xE8, 0xFC, 0x70)
$pageMagic = [byte[]](0x59, 0x60, 0x69, 0x9B)

# Build 22 deterministic pages with the page magic and a name at offset 24..45.
function New-TestPages([string]$room) {
    $nameBytes = [Text.Encoding]::UTF8.GetBytes($room)
    $pages = New-Object 'System.Collections.Generic.List[byte[]]'
    for ($i = 0; $i -lt $pageCount; $i++) {
        $p = New-Object byte[] $pageSize
        [Array]::Copy($pageMagic, 0, $p, 0, 4)
        $p[4] = [byte]($i + 1)                     # page index, unique per page
        $n = [Math]::Min($nameBytes.Length, 22)
        [Array]::Copy($nameBytes, 0, $p, 24, $n)
        $pages.Add($p)
    }
    return $pages
}

# PowerShell 5.1 has no ProcessStartInfo.ArgumentList, so the command line is built
# explicitly. Every value this script passes is a plain path/port with no spaces, and
# each is quoted defensively anyway.
function Join-Args([string[]]$argv) {
    ($argv | ForEach-Object {
        if ($_ -match '[\s"]') { '"' + ($_ -replace '"', '\"') + '"' } else { $_ }
    }) -join ' '
}

function Start-AgentProcess([string[]]$agentArgs, [string]$tag) {
    $psi = New-Object Diagnostics.ProcessStartInfo
    $psi.FileName = $agent
    $psi.Arguments = Join-Args $agentArgs
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    $p = [Diagnostics.Process]::Start($psi)
    $outTask = $p.StandardOutput.ReadToEndAsync()
    $errTask = $p.StandardError.ReadToEndAsync()
    return [pscustomobject]@{ Proc = $p; OutTask = $outTask; ErrTask = $errTask; Tag = $tag }
}

Write-Host ""
Write-Host "=== M0-E discovery completion self-test ==="
Write-Host "  agent   : $agent"
Write-Host "  evidence: $OutRoot"
Write-Host "  replay  : 127.0.0.1:$ReplayPort (fake game socket)"
Write-Host "  probe   : 127.0.0.1:$ProbePort (Agent-owned discovery port)"
Write-Host ""

# Make sure nothing is squatting on the two ports we need.
foreach ($port in @($ReplayPort, $ProbePort)) {
    $busy = $null
    try { $busy = Get-NetUDPEndpoint -LocalPort $port -ErrorAction Stop } catch { }
    if ($busy) {
        Write-Host ("[!] UDP port {0} is already in use by pid {1}" -f $port, ($busy | Select-Object -First 1).OwningProcess)
        exit 2
    }
}
Get-Process civlink-agent -ErrorAction SilentlyContinue | ForEach-Object {
    Write-Host ("[!] a civlink-agent is already running (pid {0}); stopping it" -f $_.Id)
    $_.Kill(); $_.WaitForExit(3000) | Out-Null
}

$capturedPages = $null
$clientBound = $false
$forwardedOk = $false
$agentOut = ''
$agentErr = ''
$agentExit = -1

try {
    # ---------------------------------------------------------------- scenario 1: live target
    Write-Host "[1/5] replay target answers 22 pages"
    $room = 'CivLink-M0E-Selftest-Room'
    $gamePages = New-TestPages -room $room

    $game = New-Object Net.Sockets.UdpClient([int]$ReplayPort)
    $game.Client.ReceiveTimeout = 4000
    $client = New-Object Net.Sockets.UdpClient(0)
    $client.Client.ReceiveTimeout = 6000

    $agentDir = Join-Path $OutRoot 'run1'
    New-Item -ItemType Directory -Force -Path $agentDir | Out-Null
    $args1 = @(
        '--sim-lan-listen', '127.0.0.1'
        '--discovery-completion'
        '--reserve-62900'
        '--game-discovery-addr', "127.0.0.1:$ReplayPort"
        '--completion-timeout-ms', "$TimeoutMs"
        '--listen-seconds', "$ListenSeconds"
        '--out-dir', $agentDir
        '--quiet'
    )
    $run1 = Start-AgentProcess -agentArgs $args1 -tag 'run1'
    Start-Sleep -Milliseconds 1200

    $clientAddr = $client.Client.LocalEndPoint
    $bytesSent = $client.Send($magic, $magic.Length, (New-Object Net.IPEndPoint([Net.IPAddress]::Loopback, $ProbePort)))
    Check 'client sent one 4-byte magic' ($bytesSent -eq 4)

    # Service the fake game: it must receive exactly one datagram (the replayed magic).
    $gameEp = New-Object Net.IPEndPoint([Net.IPAddress]::Any, 0)
    $replay = $null
    try { $replay = $game.Receive([ref]$gameEp) } catch { $replay = $null }
    Check 'fake game received the replay' ($null -ne $replay)
    Check 'replay payload is the 4-byte magic' ($null -ne $replay -and $replay.Length -eq 4 -and $replay[0] -eq $magic[0] -and $replay[1] -eq $magic[1] -and $replay[2] -eq $magic[2] -and $replay[3] -eq $magic[3])
    Check 'replay arrived over loopback only' ($null -ne $replay -and $gameEp.Address.Equals([Net.IPAddress]::Loopback))

    # Exactly one replay per client magic: no amplification. If the Agent replayed twice the
    # game would answer twice and the client would receive 44 pages.
    $game.Client.ReceiveTimeout = 400
    $duplicate = $false
    try { [void]$game.Receive([ref]$gameEp); $duplicate = $true } catch { $duplicate = $false }
    Check 'target received exactly one replay (no amplification)' (-not $duplicate)
    $game.Client.ReceiveTimeout = 4000

    # Answer with the 22 pages.
    foreach ($pg in $gamePages) { [void]$game.Send($pg, $pg.Length, $gameEp) }

    # The client must receive all 22 pages, byte-identical, from the probed port.
    $received = New-Object 'System.Collections.Generic.List[byte[]]'
    $sources = New-Object 'System.Collections.Generic.List[string]'
    $srcEp = New-Object Net.IPEndPoint([Net.IPAddress]::Any, 0)
    for ($i = 0; $i -lt $pageCount; $i++) {
        try {
            $d = $client.Receive([ref]$srcEp)
            $received.Add($d)
            $sources.Add($srcEp.ToString())
        } catch { break }
    }
    $capturedPages = $received
    $clientBound = $true
    Check ("client received {0} pages (expected {1})" -f $received.Count, $pageCount) ($received.Count -eq $pageCount)
    Check 'every forwarded page is 1104 B' (($received | Where-Object { $_.Length -ne $pageSize }).Count -eq 0)

    $identical = $true
    if ($received.Count -eq $pageCount) {
        for ($i = 0; $i -lt $pageCount; $i++) {
            if (-not [Linq.Enumerable]::SequenceEqual($received[$i], $gamePages[$i])) { $identical = $false; break }
        }
    }
    Check 'forwarded pages are byte-identical to the target reply' $identical
    $forwardedOk = $identical

    $fromProbePort = @($sources | Where-Object { $_ -like "*:$ProbePort" }).Count -eq $pageCount
    Check ("every page came from the probed port :$ProbePort") $fromProbePort

    # Shut the Agent down through its stop-file-free path: SIGKILL is not available, so
    # let --listen-seconds expire.
    [void]$run1.Proc.WaitForExit(($ListenSeconds + 20) * 1000)
    $agentOut = $run1.OutTask.Result
    $agentErr = $run1.ErrTask.Result
    if (-not $run1.Proc.HasExited) { $run1.Proc.Kill(); $run1.Proc.WaitForExit(5000) | Out-Null }
    $agentExit = $run1.Proc.ExitCode

    $summary1 = Join-Path $agentDir 'summary.txt'
    if (Test-Path $summary1) { Copy-Item $summary1 (Join-Path $OutRoot 'summary-run1.txt') -Force }
    $sum1 = if (Test-Path $summary1) { [IO.File]::ReadAllText($summary1, [Text.Encoding]::UTF8) } else { '' }

    Check 'agent exited 0' ($agentExit -eq 0)
    Check 'summary has a discovery completion block' ($sum1 -match 'discovery completion \(M0-E')
    Check 'summary shows the loopback replay target' ($sum1 -match 'replay target\s+:\s+127\.0\.0\.1:' + $ReplayPort)
    Check 'requests seen == 1' ($sum1 -match 'requests seen\s+:\s+1\b')
    Check 'replays sent == 1' ($sum1 -match 'replays sent\s+:\s+1\b')
    Check 'replays failed == 0' ($sum1 -match 'replays failed\s+:\s+0\b')
    Check ("pages collected == {0}" -f $pageCount) ($sum1 -match ('pages collected\s+:\s+' + $pageCount + '\b'))
    Check ("pages forwarded == {0}" -f $pageCount) ($sum1 -match ('pages forwarded\s+:\s+' + $pageCount + '\b'))
    Check 'timeouts == 0' ($sum1 -match 'timeouts\s+:\s+0\b')
    Check 'port 62900 is reserved, not bound by the Agent' ($sum1 -match 'port 62900\s+:\s+reserved, not bound')
    # B-1: the egress plumbing must be live even when it cannot pin. On loopback the probed
    # address is 127.0.0.1, and a page whose source is 127.0.0.1 cannot leave the host, so the
    # Agent must report the address as unknown and fall back to the routing table instead of
    # silently claiming success.
    Check 'egress api (WSARecvMsg/WSASendMsg) is available' ($sum1 -match 'egress api\s+:\s+available')
    Check 'IP_PKTINFO is enabled on the discovery sockets' ($sum1 -match 'pktinfo\s+:\s+enabled')
    Check 'loopback probe address is reported unknown (127.0.0.1 cannot be pinned)' ($sum1 -match 'probed address\s+:\s+0 round\(s\) known, 1 unknown')
    Check 'all 22 pages fell back to the routing table on loopback' ($sum1 -match 'egress unpinned\s+:\s+22 page')
    Check 'no page claimed an egress pin on loopback' ($sum1 -match 'egress pinned\s+:\s+0 page')

    $game.Close(); $client.Close()
    $game = $null; $client = $null

    # ---------------------------------------------------------------- scenario 2: silent target
    Write-Host "[2/5] silent target -> fail-closed (client must receive nothing)"
    $silentPort = $ReplayPort + 1
    $sink = New-Object Net.Sockets.UdpClient([int]$silentPort)
    $sink.Client.ReceiveTimeout = 4000
    $client2 = New-Object Net.Sockets.UdpClient(0)
    $client2.Client.ReceiveTimeout = 2500

    $agentDir2 = Join-Path $OutRoot 'run2'
    New-Item -ItemType Directory -Force -Path $agentDir2 | Out-Null
    $args2 = @(
        '--sim-lan-listen', '127.0.0.1'
        '--discovery-completion'
        '--reserve-62900'
        '--game-discovery-addr', "127.0.0.1:$silentPort"
        '--completion-timeout-ms', '600'
        '--listen-seconds', '8'
        '--out-dir', $agentDir2
        '--quiet'
    )
    $run2 = Start-AgentProcess -agentArgs $args2 -tag 'run2'
    Start-Sleep -Milliseconds 1200

    [void]$client2.Send($magic, $magic.Length, (New-Object Net.IPEndPoint([Net.IPAddress]::Loopback, $ProbePort)))
    # Drain the replayed magic so the Agent sees a target that accepted but never answers.
    $sinkEp = New-Object Net.IPEndPoint([Net.IPAddress]::Any, 0)
    try { [void]$sink.Receive([ref]$sinkEp) } catch { }

    $gotNothing = $false
    try {
        $unexpected = $client2.Receive([ref]$sinkEp)
        $gotNothing = $false
        Write-Host ("    (unexpected {0}-byte reply from {1})" -f $unexpected.Length, $sinkEp.ToString())
    } catch {
        $gotNothing = $true
    }
    Check 'silent target -> client received nothing (fail-closed)' $gotNothing

    [void]$run2.Proc.WaitForExit(($ListenSeconds + 20) * 1000)
    if (-not $run2.Proc.HasExited) { $run2.Proc.Kill(); $run2.Proc.WaitForExit(5000) | Out-Null }
    $agent2Exit = $run2.Proc.ExitCode
    $summary2 = Join-Path $agentDir2 'summary.txt'
    if (Test-Path $summary2) { Copy-Item $summary2 (Join-Path $OutRoot 'summary-run2.txt') -Force }
    $sum2 = if (Test-Path $summary2) { [IO.File]::ReadAllText($summary2, [Text.Encoding]::UTF8) } else { '' }
    Check 'silent run exited 0' ($agent2Exit -eq 0)
    Check 'silent run counted a timeout' ($sum2 -match 'timeouts\s+:\s+[1-9]')
    Check 'silent run forwarded no pages' ($sum2 -match 'pages forwarded\s+:\s+0\b')

    $sink.Close(); $client2.Close()
    $sink = $null; $client2 = $null

    # ------------------------------------------------ scenario 3: duplicate suppression
    # A real refresh fires 100 magics in ~40 ms, one per discovery port. Without a
    # cooldown every one of them would replay to the game and forward a full advert, so the
    # single forward socket (~64 KB) would drop most pages. A real client never needs more
    # than one advert per refresh, so duplicates inside the cooldown must be counted and
    # dropped, and the game must see exactly one replay.
    Write-Host "[3/5] duplicate magics inside the cooldown -> one replay, one advert"
    $dupPort = $ReplayPort + 2
    $dupGame = New-Object Net.Sockets.UdpClient([int]$dupPort)
    $dupGame.Client.ReceiveTimeout = 5000
    $dupClient = New-Object Net.Sockets.UdpClient(0)
    $dupClient.Client.ReceiveTimeout = 6000

    $agentDir3 = Join-Path $OutRoot 'run3'
    New-Item -ItemType Directory -Force -Path $agentDir3 | Out-Null
    $args3 = @(
        '--sim-lan-listen', '127.0.0.1'
        '--discovery-completion'
        '--reserve-62900'
        '--game-discovery-addr', "127.0.0.1:$dupPort"
        '--completion-timeout-ms', "$TimeoutMs"
        '--completion-cooldown-ms', '5000'
        '--listen-seconds', '8'
        '--out-dir', $agentDir3
        '--quiet'
    )
    $run3 = Start-AgentProcess -agentArgs $args3 -tag 'run3'
    Start-Sleep -Milliseconds 1200

    $dupTarget = New-Object Net.IPEndPoint([Net.IPAddress]::Loopback, $ProbePort)
    for ($i = 0; $i -lt 3; $i++) {
        [void]$dupClient.Send($magic, $magic.Length, $dupTarget)
        Start-Sleep -Milliseconds 40
    }

    $dupEp = New-Object Net.IPEndPoint([Net.IPAddress]::Any, 0)
    $dupReplays = 0
    $dupPayload = $null
    try {
        $dupPayload = $dupGame.Receive([ref]$dupEp)
        $dupReplays = 1
        foreach ($pg in $gamePages) { [void]$dupGame.Send($pg, $pg.Length, $dupEp) }
        # A second replay would arrive before the pages are consumed.
        $dupGame.Client.ReceiveTimeout = 400
        try {
            $extra = $dupGame.Receive([ref]$dupEp)
            if ($null -ne $extra) { $dupReplays++ }
        } catch { }
    } catch { }
    Check 'duplicate run: the game saw exactly one replay' ($dupReplays -eq 1)
    Check 'duplicate run: the replay carried the magic' ($null -ne $dupPayload -and $dupPayload.Length -eq 4)

    $dupRecv = 0
    $dupSrc = New-Object Net.IPEndPoint([Net.IPAddress]::Any, 0)
    for ($i = 0; $i -lt $pageCount; $i++) {
        try { [void]$dupClient.Receive([ref]$dupSrc); $dupRecv++ } catch { break }
    }
    Check ("duplicate run: client received {0} pages (expected {1})" -f $dupRecv, $pageCount) ($dupRecv -eq $pageCount)

    [void]$run3.Proc.WaitForExit(($ListenSeconds + 20) * 1000)
    if (-not $run3.Proc.HasExited) { $run3.Proc.Kill(); $run3.Proc.WaitForExit(5000) | Out-Null }
    $summary3 = Join-Path $agentDir3 'summary.txt'
    if (Test-Path $summary3) { Copy-Item $summary3 (Join-Path $OutRoot 'summary-run3.txt') -Force }
    $sum3 = if (Test-Path $summary3) { [IO.File]::ReadAllText($summary3, [Text.Encoding]::UTF8) } else { '' }
    Check 'duplicate run: requests seen == 3' ($sum3 -match 'requests seen\s+:\s+3\b')
    Check 'duplicate run: replays sent == 1' ($sum3 -match 'replays sent\s+:\s+1\b')
    Check 'duplicate run: duplicate magic == 2' ($sum3 -match 'duplicate magic\s+:\s+2\b')

    $dupGame.Close(); $dupClient.Close()
    $dupGame = $null; $dupClient = $null

    # ------------------------------------- scenario 4: egress pin on a non-loopback address
    # The loopback rounds above CANNOT exercise B-1: a page whose source address is
    # 127.0.0.1 cannot leave the host, so the Agent correctly refuses to pin. To prove the
    # pin code path really runs, the client must probe a real local IPv4 address instead of
    # 127.0.0.1. The replay target stays loopback so no game is needed. Without the
    # IP_PKTINFO/WSASendMsg plumbing the source would fall back to whatever the routing
    # table picks, and summary would report egress pinned = 0.
    $localIp = $null
    try {
        $localIp = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction Stop |
            Where-Object {
                $_.IPAddress -ne '127.0.0.1' -and
                -not $_.IPAddress.StartsWith('169.254.') -and
                $_.PrefixOrigin -ne 'WellKnown'
            } | Select-Object -First 1 -ExpandProperty IPAddress
    } catch { }
    if ([string]::IsNullOrWhiteSpace($localIp)) {
        Write-Host "[!] no non-loopback IPv4 address - cannot run the egress pin scenario"
        exit 2
    }
    Write-Host ("[4/5] egress pin: client probes {0}, pages must come back from {0}" -f $localIp)

    $pinPort = $ProbePort + 1
    $pinReplayPort = $ReplayPort + 3
    $pinGame = New-Object Net.Sockets.UdpClient([int]$pinReplayPort)
    $pinGame.Client.ReceiveTimeout = 4000
    $pinClient = New-Object Net.Sockets.UdpClient(0)
    $pinClient.Client.ReceiveTimeout = 6000

    $agentDir4 = Join-Path $OutRoot 'run4'
    New-Item -ItemType Directory -Force -Path $agentDir4 | Out-Null
    $args4 = @(
        '--sim-lan-listen', '0.0.0.0'
        '--discovery-completion'
        '--reserve-62900'
        '--game-discovery-addr', "127.0.0.1:$pinReplayPort"
        '--completion-timeout-ms', "$TimeoutMs"
        '--listen-seconds', '8'
        '--out-dir', $agentDir4
        '--quiet'
    )
    $run4 = Start-AgentProcess -agentArgs $args4 -tag 'run4'
    Start-Sleep -Milliseconds 1500

    [void]$pinClient.Send($magic, $magic.Length, (New-Object Net.IPEndPoint([Net.IPAddress]::Parse($localIp), $pinPort)))
    $pinEp = New-Object Net.IPEndPoint([Net.IPAddress]::Any, 0)
    $pinReplay = $null
    try { $pinReplay = $pinGame.Receive([ref]$pinEp) } catch { }
    Check 'egress pin: fake game received the replay' ($null -ne $pinReplay)
    if ($null -ne $pinReplay) {
        foreach ($pg in $gamePages) { [void]$pinGame.Send($pg, $pg.Length, $pinEp) }
    }

    $pinPages = 0
    $pinSources = New-Object 'System.Collections.Generic.List[string]'
    $pinSrc = New-Object Net.IPEndPoint([Net.IPAddress]::Any, 0)
    for ($i = 0; $i -lt $pageCount; $i++) {
        try { [void]$pinClient.Receive([ref]$pinSrc); $pinPages++; $pinSources.Add($pinSrc.Address.ToString()) } catch { break }
    }
    Check ("egress pin: client received {0} pages (expected {1})" -f $pinPages, $pageCount) ($pinPages -eq $pageCount)
    $pinAllFromLocal = ($pinSources.Count -eq $pageCount) -and (@($pinSources | Where-Object { $_ -ne $localIp }).Count -eq 0)
    Check ("egress pin: every page was sourced from {0}" -f $localIp) $pinAllFromLocal

    [void]$run4.Proc.WaitForExit(($ListenSeconds + 20) * 1000)
    if (-not $run4.Proc.HasExited) { $run4.Proc.Kill(); $run4.Proc.WaitForExit(5000) | Out-Null }
    $summary4 = Join-Path $agentDir4 'summary.txt'
    if (Test-Path $summary4) { Copy-Item $summary4 (Join-Path $OutRoot 'summary-run4.txt') -Force }
    $sum4 = if (Test-Path $summary4) { [IO.File]::ReadAllText($summary4, [Text.Encoding]::UTF8) } else { '' }
    Check 'egress pin: summary reports the probed address as known' ($sum4 -match 'probed address\s+:\s+1 round\(s\) known, 0 unknown')
    Check 'egress pin: summary reports 22 pinned pages' ($sum4 -match 'egress pinned\s+:\s+22 page')
    Check 'egress pin: summary reports 0 unpinned pages' ($sum4 -match 'egress unpinned\s+:\s+0 page')

    $pinGame.Close(); $pinClient.Close()
    $pinGame = $null; $pinClient = $null

    # ---------------------------------------------------------------- scenario 5: flag rules
    Write-Host "[5/5] cross-flag rules"
    function Test-AgentRejects([string[]]$argv, [string]$needle) {
        $psi = New-Object Diagnostics.ProcessStartInfo
        $psi.FileName = $agent
        $psi.Arguments = Join-Args $argv
        $psi.UseShellExecute = $false
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.CreateNoWindow = $true
        $p = [Diagnostics.Process]::Start($psi)
        $o = $p.StandardOutput.ReadToEndAsync()
        $e = $p.StandardError.ReadToEndAsync()
        [void]$p.WaitForExit(8000)
        $text = ($o.Result + $e.Result)
        return [pscustomobject]@{ Exit = $p.ExitCode; Text = $text; Matched = ($text -match [regex]::Escape($needle)) }
    }

    $r1 = Test-AgentRejects @('--discovery-completion') 'requires --sim-lan-listen'
    Check 'completion without --sim-lan-listen is rejected' ($r1.Exit -ne 0 -and $r1.Matched)

    $r2 = Test-AgentRejects @('--sim-lan-listen', '127.0.0.1', '--discovery-completion', '--reserve-62900', '--simulate', 'x') 'does not take --simulate'
    Check 'completion with --simulate is rejected' ($r2.Exit -ne 0 -and $r2.Matched)

    $r3 = Test-AgentRejects @('--sim-lan-listen', '127.0.0.1', '--discovery-completion', '--reserve-62900', '--sim-real-capture') 'mutually exclusive'
    Check 'completion with --sim-real-capture is rejected' ($r3.Exit -ne 0 -and $r3.Matched)

    $r4 = Test-AgentRejects @('--sim-lan-listen', '127.0.0.1', '--discovery-completion') 'implies --reserve-62900'
    Check 'completion without --reserve-62900 is rejected' ($r4.Exit -ne 0 -and $r4.Matched)

    $r5 = Test-AgentRejects @('--sim-lan-listen', '127.0.0.1', '--discovery-completion', '--reserve-62900', '--game-discovery-addr', '192.168.31.60:62900') 'must be a loopback address'
    Check 'non-loopback replay target is rejected' ($r5.Exit -ne 0 -and $r5.Matched)

} catch {
    Write-Host ("[!] unexpected error: {0}" -f $_) -ForegroundColor Red
    $script:Failures += 'unexpected error'
} finally {
    foreach ($p in @('game', 'client', 'sink', 'client2', 'dupGame', 'dupClient', 'pinGame', 'pinClient')) {
        $v = Get-Variable -Name $p -ValueOnly -ErrorAction SilentlyContinue
        if ($v) { try { $v.Close() } catch { } }
    }
    Get-Process civlink-agent -ErrorAction SilentlyContinue | ForEach-Object { $_.Kill() }
}

# ---------------------------------------------------------------------------- artifacts
if ($capturedPages) {
    for ($i = 0; $i -lt $capturedPages.Count; $i++) {
        [IO.File]::WriteAllBytes((Join-Path $OutRoot ("client-recv-{0:d2}.bin" -f ($i + 1))), $capturedPages[$i])
    }
}
[IO.File]::WriteAllText((Join-Path $OutRoot 'agent-run1-stdout.txt'), $agentOut, (New-Object Text.UTF8Encoding($false)))
[IO.File]::WriteAllText((Join-Path $OutRoot 'agent-run1-stderr.txt'), $agentErr, (New-Object Text.UTF8Encoding($false)))

$manifest = @()
$manifest += "# M0-E discovery completion self-test"
$manifest += "# out: $OutRoot"
$manifest += "# agent: $agent"
$manifest += "# agent sha256: $(Get-Sha256Hex $agent)"
$manifest += ""
Get-ChildItem -LiteralPath $OutRoot -File | Sort-Object Name | ForEach-Object {
    $manifest += ("{0}  {1}  {2}" -f (Get-Sha256Hex $_.FullName), $_.Length, $_.Name)
}
[IO.File]::WriteAllText((Join-Path $OutRoot 'manifest.txt'), ($manifest -join "`r`n") + "`r`n", (New-Object Text.UTF8Encoding($false)))

$verdict = @(
    "M0-E COMPLETION SELFTEST",
    ("checks          : {0}/{1}" -f ($script:Checks - $script:Failures.Count), $script:ExpectChecks)
    ("failed          : {0}" -f $script:Failures.Count)
    ("replay forwarded: {0}" -f $forwardedOk)
    ("evidence        : {0}" -f $OutRoot)
    ""
    "PROVES (mechanical, loopback): one magic in -> one loopback replay -> 22 pages forwarded from the probed port; silent target yields nothing."
    "DOES NOT PROVE: that real Civilization VI answers the replay, that a real client accepts the pages, any cross-machine behaviour."
    "Simulated evidence only - NOT a two-real-hosts result, NOT E2-B/E3."
)
[IO.File]::WriteAllText((Join-Path $OutRoot 'verdict.txt'), ($verdict -join "`r`n") + "`r`n", (New-Object Text.UTF8Encoding($false)))

Write-Host ""
if ($script:Failures.Count -eq 0 -and $script:Checks -eq $script:ExpectChecks) {
    Write-Host ("M0E-COMPLETION-SELFTEST: PASS ({0}/{1})" -f $script:Checks, $script:ExpectChecks) -ForegroundColor Green
    exit 0
}
if ($script:Failures.Count -eq 0) {
    Write-Host ("M0E-COMPLETION-SELFTEST: FAIL (clean but {0} of {1} checks ran)" -f $script:Checks, $script:ExpectChecks) -ForegroundColor Red
    exit 1
}
Write-Host ("M0E-COMPLETION-SELFTEST: FAIL ({0} failed of {1} run)" -f $script:Failures.Count, $script:Checks) -ForegroundColor Red
$script:Failures | ForEach-Object { Write-Host ("   - {0}" -f $_) }
exit 1
