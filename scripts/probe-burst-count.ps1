# probe-burst-count.ps1 - passive, count every datagram on the Civ6 LAN discovery port range.
# Uses Socket.Select over all bound sockets so nothing is missed by serialized polling.
# Read-only: sends nothing, changes nothing.
param(
    [string]$Ports = "62900-62999",
    [int]$Seconds = 150,
    [string]$OutFile = ""
)
$ErrorActionPreference = 'Stop'
if (-not $OutFile) { $OutFile = Join-Path $PSScriptRoot ("..\..\M0A\captures\probe-burstcount-{0}.log" -f (Get-Date -Format 'yyyyMMdd-HHmmss')) }
$OutFile = [IO.Path]::GetFullPath($OutFile)
if ((Split-Path $OutFile -Parent) -and -not (Test-Path (Split-Path $OutFile -Parent))) { New-Item -ItemType Directory -Force -Path (Split-Path $OutFile -Parent) | Out-Null }

$portList = @()
foreach ($part in ($Ports -split ',')) {
    $part = $part.Trim()
    if ($part -match '^(\d+)-(\d+)$') { $portList += ([int]$Matches[1])..([int]$Matches[2]) }
    elseif ($part -match '^\d+$') { $portList += [int]$part }
}
$portList = $portList | Sort-Object -Unique

function Log([string]$s) { [IO.File]::AppendAllText($OutFile, $s + "`r`n", (New-Object System.Text.UTF8Encoding($false))) }

Log ("=== probe-burst-count === start {0} ports={1} count={2} seconds={3}" -f (Get-Date -Format 'HH:mm:ss.fff'), ($portList -join ','), $portList.Count, $Seconds)

$socks = New-Object System.Collections.Generic.List[object]
foreach ($p in $portList) {
    $s = New-Object System.Net.Sockets.Socket([System.Net.Sockets.AddressFamily]::InterNetwork, [System.Net.Sockets.SocketType]::Dgram, [System.Net.Sockets.ProtocolType]::Udp)
    try {
        $s.SetSocketOption([System.Net.Sockets.SocketOptionLevel]::Socket, [System.Net.Sockets.SocketOptionName]::ReuseAddress, [int]1)
        $s.Bind([System.Net.IPEndPoint]::new([System.Net.IPAddress]::Any, $p))
        $s.Blocking = $false
        $socks.Add([pscustomobject]@{ Port = $p; Sock = $s; Count = 0 })
    } catch {
        Log ("bind failed port={0}: {1}" -f $p, $_.Exception.Message)
        try { $s.Dispose() } catch {}
    }
}
Log ("bound ports: {0}/{1}" -f $socks.Count, $portList.Count)

$recvBuf = New-Object byte[] 2048
$flags = [System.Net.Sockets.SocketFlags]::None
$pinfo = New-Object System.Net.Sockets.IPPacketInformation
$total = 0
$perPort = @{}
$perSource = @{}
$sw = [Diagnostics.Stopwatch]::StartNew()
$lastTick = 0

while ($sw.Elapsed.TotalSeconds -lt $Seconds) {
    $readList = New-Object System.Collections.ArrayList
    foreach ($e in $socks) { [void]$readList.Add($e.Sock) }
    try {
        $null = [System.Net.Sockets.Socket]::Select($readList, $null, $null, 200000)
    } catch {
        Log ("select error: {0}" -f $_.Exception.Message)
        continue
    }
    if ($readList.Count -eq 0) { continue }

    foreach ($ready in $readList) {
        $entry = $null
        foreach ($e in $socks) { if ([object]::ReferenceEquals($e.Sock, $ready)) { $entry = $e; break } }
        if (-not $entry) { continue }

        # drain everything queued on this socket
        while ($true) {
            $remoteEp = [System.Net.EndPoint][System.Net.IPEndPoint]::new([System.Net.IPAddress]::Any, 0)
            $f2 = [System.Net.Sockets.SocketFlags]::None
            $p2 = New-Object System.Net.Sockets.IPPacketInformation
            try {
                $n = $entry.Sock.ReceiveMessageFrom($recvBuf, 0, $recvBuf.Length, [ref]$f2, [ref]$remoteEp, [ref]$p2)
            } catch [System.Net.Sockets.SocketException] { break }
            if ($n -lt 1) { break }
            $srcIp = ($remoteEp -as [System.Net.IPEndPoint]).Address.ToString()
            $srcPort = ($remoteEp -as [System.Net.IPEndPoint]).Port
            $payload = New-Object byte[] $n
            [Array]::Copy($recvBuf, 0, $payload, 0, $n)
            $hex = [BitConverter]::ToString($payload)
            $entry.Count++
            $total++
            if (-not $perPort.ContainsKey($entry.Port)) { $perPort[$entry.Port] = 0 }
            $perPort[$entry.Port]++
            $key = "$srcIp`:$srcPort"
            if (-not $perSource.ContainsKey($key)) { $perSource[$key] = 0 }
            $perSource[$key]++
            Log ("[{0}] port={1} len={2} from {3}:{4} iface={5} payload={6}" -f (Get-Date -Format 'HH:mm:ss.fff'), $entry.Port, $n, $srcIp, $srcPort, $p2.Interface, $hex)
        }
    }

    $t = [int]$sw.Elapsed.TotalSeconds
    if ($t - $lastTick -ge 15) { $lastTick = $t; Log ("... t+{0}s total={1}" -f $t, $total) }
}

foreach ($e in $socks) { try { $e.Sock.Dispose() } catch {} }
Log ("=== summary: datagrams={0} portsHit={1} distinctSources={2} window={3:N1}s" -f $total, $perPort.Count, $perSource.Count, $sw.Elapsed.TotalSeconds)
if ($perPort.Count -gt 0) {
    $hits = ($perPort.GetEnumerator() | Sort-Object Name | ForEach-Object { "$($_.Key):$($_.Value)" }) -join ' '
    Log ("per-port: " + $hits)
}
if ($perSource.Count -gt 0) {
    $srcs = ($perSource.GetEnumerator() | Sort-Object Name | ForEach-Object { "$($_.Key):$($_.Value)" }) -join ' '
    Log ("per-source: " + $srcs)
}
Log "=== end ==="
Write-Host "OUT=$OutFile"
