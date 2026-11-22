param(
    [string]$Ports = "62900-62999",
    [int]$Seconds = 12,
    [int]$SelectUs = 200000,
    [switch]$HoistFlags,
    [switch]$HoistEp,
    [switch]$HoistPinfo,
    [switch]$NoSkip
)
$portList = @()
foreach ($part in ($Ports -split ',')) {
    $part = $part.Trim()
    if ($part -match '^(\d+)-(\d+)$') { $portList += ([int]$Matches[1])..([int]$Matches[2]) }
    elseif ($part -match '^\d+$') { $portList += [int]$part }
}
$portList = $portList | Sort-Object -Unique

$skip = @()
if (-not $NoSkip) {
    $skip = @(Get-NetUDPEndpoint | Where-Object { $_.LocalPort -ge $portList[0] -and $_.LocalPort -le $portList[-1] -and $_.LocalAddress -notmatch ':' } | Select-Object -ExpandProperty LocalPort)
}
$socks = New-Object System.Collections.Generic.List[object]
foreach ($p in $portList) {
    if ($skip -contains $p) { continue }
    $s = New-Object System.Net.Sockets.Socket([System.Net.Sockets.AddressFamily]::InterNetwork, [System.Net.Sockets.SocketType]::Dgram, [System.Net.Sockets.ProtocolType]::Udp)
    try {
        $s.SetSocketOption([System.Net.Sockets.SocketOptionLevel]::Socket, [System.Net.Sockets.SocketOptionName]::ReuseAddress, [int]1)
        $s.Bind([System.Net.IPEndPoint]::new([System.Net.IPAddress]::Any, $p))
        $socks.Add([pscustomobject]@{ Port = $p; Sock = $s })
    } catch { try { $s.Dispose() } catch {} }
}

# hoisted instances (reused across every ReceiveMessageFrom call)
$hFlags = [System.Net.Sockets.SocketFlags]::None
$hEp = [System.Net.EndPoint][System.Net.IPEndPoint]::new([System.Net.IPAddress]::Any, 0)
$hPinfo = [System.Net.Sockets.IPPacketInformation]::new()

"VARIANT hoistFlags=$HoistFlags hoistEp=$HoistEp hoistPinfo=$HoistPinfo"
"bound=$($socks.Count) skipped=$($skip -join ',')"

$recvBuf = New-Object byte[] 2048
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
            if ($HoistFlags) { $f2 = $hFlags } else { $f2 = [System.Net.Sockets.SocketFlags]::None }
            if ($HoistEp) { $ep2 = $hEp } else { $ep2 = [System.Net.EndPoint][System.Net.IPEndPoint]::new([System.Net.IPAddress]::Any, 0) }
            if ($HoistPinfo) { $p2 = $hPinfo } else { $p2 = New-Object System.Net.Sockets.IPPacketInformation }
            try { $n = $entry.Sock.ReceiveMessageFrom($recvBuf, 0, $recvBuf.Length, [ref]$f2, [ref]$ep2, [ref]$p2) } catch { break }
            if ($n -lt 1) { break }
            if (-not $HoistFlags) { $hFlags = $f2 }
            if (-not $HoistEp) { $hEp = $ep2 }
            if (-not $HoistPinfo) { $hPinfo = $p2 }
            if (-not $perPort.ContainsKey($entry.Port)) { $perPort[$entry.Port] = 0 }
            $perPort[$entry.Port]++
            if ($entry.Sock.Available -le 0) { break }
        }
    }
}
$sw.Stop()
$sum = 0; if ($perPort.Count -gt 0) { $sum = ($perPort.Values | Measure-Object -Sum).Sum }
"RESULT datagrams=$sum portsHit=$($perPort.Count) window=$([math]::Round($sw.Elapsed.TotalSeconds,1))s"
"ports: $(($perPort.Keys | Sort-Object) -join ',')"
foreach ($e in $socks) { try { $e.Sock.Dispose() } catch {} }
