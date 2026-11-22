# probe-lan-burst.ps1 - passive listener on a set of discovery ports (NOT 62900,
# which the responder holds) to verify whether the Civ6 CLIENT actually emits a
# discovery burst when the LAN lobby is refreshed. Read-only observation: it
# binds one port, logs every datagram for -Seconds, writes a log file, and exits.
# It sends nothing.
param(
    # comma/space separated list, e.g. "62901,62902,62903" (string so -File passes it through)
    [string]$Ports = '62950',
    [int]$Seconds = 75,
    [string]$OutFile = ''
)
$ErrorActionPreference = 'Stop'
# normalise: accept "62901,62902" or "62901 62902" or a single port
$portList = @()
foreach ($tok in ($Ports -split '[,;\s]+')) {
    if ($tok -match '^\d+$') { $portList += [int]$tok }
}
if ($portList.Count -eq 0) { throw "no valid ports parsed from '$Ports'" }
# NOTE: never assign the array back into $Ports - the parameter is typed [string],
# so PowerShell would re-join it to "62901 62902 ..." and every Bind() would fail.
if ($OutFile -eq '') { $OutFile = Join-Path $env:TEMP ('lan-burst-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.log') }
$lines = New-Object System.Collections.Generic.List[string]
function W($s) {
    $lines.Add($s)
    Write-Host $s
    # append immediately so a concurrent reader can see progress while the probe runs
    try { [IO.File]::AppendAllText($OutFile, ($s + "`r`n"), [Text.Encoding]::UTF8) } catch { }
}

W ("=== probe-lan-burst === start {0} ports={1} seconds={2}" -f (Get-Date -Format 'HH:mm:ss.fff'), ($portList -join ','), $Seconds)

$socks = @()
foreach ($p in $portList) {
    $s = [System.Net.Sockets.Socket]::new(
        [System.Net.Sockets.AddressFamily]::InterNetwork,
        [System.Net.Sockets.SocketType]::Dgram,
        [System.Net.Sockets.ProtocolType]::Udp)
    $s.SetSocketOption([Net.Sockets.SocketOptionLevel]::Socket, [Net.Sockets.SocketOptionName]::ReuseAddress, [int]1)
    try {
        $s.Bind([System.Net.IPEndPoint]::new([System.Net.IPAddress]::Any, $p))
        $s.ReceiveTimeout = 500
        W ("bound 0.0.0.0:{0} (SO_REUSEADDR=1)" -f $p)
        $socks += [pscustomobject]@{ Sock = $s; Port = $p }
    } catch {
        W ("BIND FAILED port {0}: {1}" -f $p, $_.Exception.Message)
        $s.Dispose()
    }
}
if ($socks.Count -eq 0) { W 'no socket bound - aborting'; [IO.File]::WriteAllLines($OutFile, $lines, [Text.Encoding]::UTF8); exit 2 }

$buf = [byte[]]::new(65536)
$remoteEp = [System.Net.EndPoint][System.Net.IPEndPoint]::new([System.Net.IPAddress]::Any, 0)
$flags = [System.Net.Sockets.SocketFlags]::None
$pinfo = [System.Net.Sockets.IPPacketInformation]::new()
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$count = 0
$bySrc = @{}

while ($sw.Elapsed.TotalSeconds -lt $Seconds) {
    foreach ($e in $socks) {
        try {
            $n = $e.Sock.ReceiveMessageFrom($buf, 0, $buf.Length, [ref]$flags, [ref]$remoteEp, [ref]$pinfo)
        } catch [System.Net.Sockets.SocketException] { continue }
        if ($n -lt 1) { continue }
        $ep = $remoteEp -as [System.Net.IPEndPoint]
        $payload = New-Object byte[] $n
        [Array]::Copy($buf, 0, $payload, 0, $n)
        $hex = [BitConverter]::ToString($payload)
        $count++
        $key = "$($ep.Address):$($ep.Port)"
        if (-not $bySrc.ContainsKey($key)) { $bySrc[$key] = 0 }
        $bySrc[$key]++
        W (("[{0}] port={1} len={2} from {3}:{4} iface={5} payload={6}" -f (Get-Date -Format 'HH:mm:ss.fff'), $e.Port, $n, $ep.Address, $ep.Port, $pinfo.Interface, $hex))
    }
}
foreach ($e in $socks) { $e.Sock.Dispose() }
W ''
W ("=== summary: datagrams={0} distinctSources={1} window={2:N1}s" -f $count, $bySrc.Count, $sw.Elapsed.TotalSeconds)
foreach ($k in $bySrc.Keys) { W ("  from {0}: {1}" -f $k, $bySrc[$k]) }
[IO.File]::WriteAllLines($OutFile, $lines, [Text.Encoding]::UTF8)
Write-Host ("log written: {0}" -f $OutFile)

