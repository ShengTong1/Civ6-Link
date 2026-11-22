param(
    [string]$Ports = "62900-62999",
    [int]$Seconds = 12,
    [int]$SelectUs = 200000,
    [switch]$NoSkip,
    [switch]$RcvBuf,
    [switch]$NonBlocking,
    [switch]$NoDrain,
    [switch]$EapStop
)
$ErrorActionPreference = if ($EapStop) { 'Stop' } else { 'Continue' }

$portList = @()
foreach ($part in ($Ports -split ',')) {
    $part = $part.Trim()
    if ($part -match '^(\d+)-(\d+)$') { $portList += ([int]$Matches[1])..([int]$Matches[2]) }
    elseif ($part -match '^\d+$') { $portList += [int]$part }
}
$portList = $portList | Sort-Object -Unique

$skip = @()
if (-not $NoSkip) {
    $skip = @(Get-NetUDPEndpoint |
        Where-Object { $_.LocalPort -ge $portList[0] -and $_.LocalPort -le $portList[-1] -and $_.LocalAddress -notmatch ':' } |
        Select-Object -ExpandProperty LocalPort)
}

$socks = New-Object System.Collections.Generic.List[object]
foreach ($p in $portList) {
    if ($skip -contains $p) { continue }
    $s = New-Object System.Net.Sockets.Socket([System.Net.Sockets.AddressFamily]::InterNetwork, [System.Net.Sockets.SocketType]::Dgram, [System.Net.Sockets.ProtocolType]::Udp)
    try {
        $s.SetSocketOption([System.Net.Sockets.SocketOptionLevel]::Socket, [System.Net.Sockets.SocketOptionName]::ReuseAddress, [int]1)
        $s.Bind([System.Net.IPEndPoint]::new([System.Net.IPAddress]::Any, $p))
        if ($NonBlocking) { $s.Blocking = $false }
        if ($RcvBuf) { $s.ReceiveBufferSize = 65536 }
        $socks.Add([pscustomobject]@{ Port = $p; Sock = $s })
    } catch { try { $s.Dispose() } catch {} }
}

"VARIANT skip=$(-not $NoSkip) rcvbuf=$RcvBuf nonblock=$NonBlocking drain=$(-not $NoDrain) selectUs=$SelectUs eap=$EapStop"
"bound=$($socks.Count) skipped=$($skip -join ',')"

$bufLen = if ($RcvBuf) { 65536 } else { 2048 }
$recvBuf = New-Object byte[] $bufLen
$f2hoist=[System.Net.Sockets.SocketFlags]::None
$rehoist=[System.Net.EndPoint][System.Net.IPEndPoint]::new([System.Net.IPAddress]::Any,0)
$pihoist=[System.Net.Sockets.IPPacketInformation]::new()
$sw = [Diagnostics.Stopwatch]::StartNew()
$perPort = @{}
while ($sw.Elapsed.TotalSeconds -lt $Seconds) {
    $rl = New-Object System.Collections.ArrayList
    foreach ($e in $socks) { [void]$rl.Add($e.Sock) }
    try { $null = [System.Net.Sockets.Socket]::Select($rl, $null, $null, $SelectUs) } catch { continue }
    if ($rl.Count -eq 0) { continue }
    foreach ($rs in $rl) {
        $entry = $null
        foreach ($e in $socks) { if ([object]::ReferenceEquals($e.Sock, $rs)) { $entry = $e; break } }
        if (-not $entry) { continue }
        while ($true) {
            try { $n = $entry.Sock.ReceiveMessageFrom($recvBuf, 0, $recvBuf.Length, [ref]$f2hoist, [ref]$rehoist, [ref]$pihoist) } catch { break }
            if ($n -lt 1) { break }
            if (-not $perPort.ContainsKey($entry.Port)) { $perPort[$entry.Port] = 0 }
            $perPort[$entry.Port]++
            if ($entry.Sock.Available -le 0) { break }
        }
    }
}
$sw.Stop()
"RESULT datagrams=$((($perPort.Values | Measure-Object -Sum).Sum)) portsHit=$($perPort.Count) window=$([math]::Round($sw.Elapsed.TotalSeconds,1))s"
"ports: $(($perPort.Keys | Sort-Object) -join ',')"
foreach ($e in $socks) { try { $e.Sock.Dispose() } catch {} }
