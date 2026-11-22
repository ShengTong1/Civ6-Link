param(
    [string]$Ports = "62900-62999",
    [int]$Seconds = 10,
    [switch]$Hoist,
    [string]$Out = "diag-e.out"
)
$portList = @()
foreach ($part in ($Ports -split ',')) {
    $part = $part.Trim()
    if ($part -match '^(\d+)-(\d+)$') { $portList += ([int]$Matches[1])..([int]$Matches[2]) }
    elseif ($part -match '^\d+$') { $portList += [int]$part }
}

function W([string]$s) { [IO.File]::AppendAllText($Out, $s + "`r`n", (New-Object System.Text.UTF8Encoding($false))) }
Remove-Item $Out -ErrorAction SilentlyContinue

$socks = New-Object System.Collections.Generic.List[object]
foreach ($p in $portList) {
    $s = New-Object System.Net.Sockets.Socket([System.Net.Sockets.AddressFamily]::InterNetwork, [System.Net.Sockets.SocketType]::Dgram, [System.Net.Sockets.ProtocolType]::Udp)
    try {
        $s.SetSocketOption([System.Net.Sockets.SocketOptionLevel]::Socket, [System.Net.Sockets.SocketOptionName]::ReuseAddress, [int]1)
        $s.Bind([System.Net.IPEndPoint]::new([System.Net.IPAddress]::Any, $p))
        $socks.Add([pscustomobject]@{ Port = $p; Sock = $s })
    } catch { try { $s.Dispose() } catch {} }
}
W ("bound={0} hoist={1}" -f $socks.Count, $Hoist)

# script-scope holders used when -Hoist (this reproduces the responder pattern)
$hFlags = [System.Net.Sockets.SocketFlags]::None
$hEp = [System.Net.EndPoint][System.Net.IPEndPoint]::new([System.Net.IPAddress]::Any, 0)
$hPinfo = [System.Net.Sockets.IPPacketInformation]::new()

$recvBuf = New-Object byte[] 2048
$sw = [Diagnostics.Stopwatch]::StartNew()
$calls = 0
$ok = 0
while ($sw.Elapsed.TotalSeconds -lt $Seconds) {
    $rl = New-Object System.Collections.ArrayList
    foreach ($e in $socks) { [void]$rl.Add($e.Sock) }
    try { $null = [System.Net.Sockets.Socket]::Select($rl, $null, $null, 200000) } catch { W ("selecterr: " + $_.Exception.Message); continue }
    if ($rl.Count -eq 0) { continue }
    W ("select returned {0} ready" -f $rl.Count)
    foreach ($rs in $rl) {
        $entry = $null
        foreach ($e in $socks) { if ([object]::ReferenceEquals($e.Sock, $rs)) { $entry = $e; break } }
        if (-not $entry) { continue }
        while ($true) {
            $calls++
            if ($Hoist) {
                try {
                    $n = $entry.Sock.ReceiveMessageFrom($recvBuf, 0, $recvBuf.Length, [ref]$hFlags, [ref]$hEp, [ref]$hPinfo)
                    $ok++
                    W ("hoist ok port={0} n={1} avail={2} ep={3}" -f $entry.Port, $n, $entry.Sock.Available, ($hEp -as [System.Net.IPEndPoint]).ToString())
                } catch {
                    W ("hoist ERR port={0} type={1} msg={2}" -f $entry.Port, $_.Exception.GetType().Name, $_.Exception.Message)
                    break
                }
            } else {
                $f2 = [System.Net.Sockets.SocketFlags]::None
                $ep2 = [System.Net.EndPoint][System.Net.IPEndPoint]::new([System.Net.IPAddress]::Any, 0)
                $p2 = New-Object System.Net.Sockets.IPPacketInformation
                try {
                    $n = $entry.Sock.ReceiveMessageFrom($recvBuf, 0, $recvBuf.Length, [ref]$f2, [ref]$ep2, [ref]$p2)
                    $ok++
                    W ("local ok port={0} n={1} avail={2} ep={3}" -f $entry.Port, $n, $entry.Sock.Available, ($ep2 -as [System.Net.IPEndPoint]).ToString())
                } catch {
                    W ("local ERR port={0} type={1} msg={2}" -f $entry.Port, $_.Exception.GetType().Name, $_.Exception.Message)
                    break
                }
            }
            if ($entry.Sock.Available -le 0) { break }
        }
    }
}
W ("RESULT calls={0} ok={1} window={2:N1}s" -f $calls, $ok, $sw.Elapsed.TotalSeconds)
foreach ($e in $socks) { try { $e.Sock.Dispose() } catch {} }
