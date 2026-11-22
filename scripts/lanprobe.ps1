# CivLink M0-A - LAN discovery listener (v2, no admin required)
#
# Binds UDP 62900..62999 on ALL IPv4 interfaces and records every datagram:
#   time, arrival interface (ifIndex), local destination address, src, dst port, len, hex payload
#
# v2 change: uses ReceiveMessageFrom + IP_PKTINFO so each datagram is tagged with the
# interface it actually arrived on. This is required because both test machines carry
# many virtual adapters (VMware / Hyper-V / WSL / Radmin VPN / ZeroTier / ToDesk / Sunlogin);
# without ifIndex we cannot tell WHICH path a discovery packet travelled.
#
# ASCII-only on purpose: PowerShell 5.1 decodes BOM-less .ps1 as the ANSI codepage,
# so non-ASCII comments break parsing. Keep this file ASCII.
#
# Usage:
#   powershell -NoProfile -ExecutionPolicy Bypass -File lanprobe.ps1 -OutFile probe.log -Seconds 120

param(
    [string]$OutFile = (Join-Path $PSScriptRoot '..\..\M0A\captures\lanprobe.log'),
    [int]$PortLow = 62900,
    [int]$PortHigh = 62999,
    [int]$Seconds = 120
)

$ErrorActionPreference = 'Stop'
$OutFile = [IO.Path]::GetFullPath($OutFile)
$dir = Split-Path -Parent $OutFile
if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }

# ifIndex -> friendly name, for readable output
$adapterNames = @{}
try {
    Get-NetAdapter -ErrorAction Stop | ForEach-Object { $adapterNames[[int]$_.ifIndex] = $_.Name }
} catch { }

function Get-AdapterLabel([int]$ifIndex) {
    if ($adapterNames.ContainsKey($ifIndex)) { return $adapterNames[$ifIndex] }
    return "if$ifIndex"
}

$sockets = @()
$ports = $PortLow..$PortHigh
foreach ($p in $ports) {
    try {
        $s = New-Object System.Net.Sockets.Socket(
            [System.Net.Sockets.AddressFamily]::InterNetwork,
            [System.Net.Sockets.SocketType]::Dgram,
            [System.Net.Sockets.ProtocolType]::Udp)
        $s.SetSocketOption([System.Net.Sockets.SocketOptionLevel]::Socket,
                           [System.Net.Sockets.SocketOptionName]::ReuseAddress, $true)
        # ask the stack to report the arrival interface for every datagram
        $s.SetSocketOption([System.Net.Sockets.SocketOptionLevel]::IP,
                           [System.Net.Sockets.SocketOptionName]::PacketInformation, $true)
        $s.Bind((New-Object System.Net.IPEndPoint([System.Net.IPAddress]::Any, $p)))
        $sockets += [pscustomobject]@{ Port = $p; Socket = $s }
    } catch {
        Write-Warning ("bind {0} failed: {1}" -f $p, $_.Exception.Message)
    }
}

$sw = [Diagnostics.Stopwatch]::StartNew()
$header = "# lanprobe v2 started {0:yyyy-MM-dd HH:mm:ss.fff} ports={1}-{2} bound={3}" -f (Get-Date), $PortLow, $PortHigh, $sockets.Count
Add-Content -Path $OutFile -Value $header -Encoding UTF8
Write-Host $header
if ($sockets.Count -lt ($PortHigh - $PortLow + 1)) {
    $msg = "# WARNING: only {0}/{1} ports bound - another process may hold some of them" -f $sockets.Count, ($PortHigh - $PortLow + 1)
    Add-Content -Path $OutFile -Value $msg -Encoding UTF8
    Write-Host $msg
}

$deadline = $sw.Elapsed.TotalSeconds + $Seconds
$received = 0
$buf = New-Object byte[] 4096
$ifHits = @{}

while ($sw.Elapsed.TotalSeconds -lt $deadline) {
    foreach ($c in $sockets) {
        try {
            while ($c.Socket.Available -gt 0) {
                $ep = New-Object System.Net.IPEndPoint([System.Net.IPAddress]::Any, 0)
                $flags = [System.Net.Sockets.SocketFlags]::None
                $pktInfo = New-Object System.Net.Sockets.IPPacketInformation
                $n = $c.Socket.ReceiveMessageFrom($buf, 0, $buf.Length, [ref]$flags, [ref]$ep, [ref]$pktInfo)
                if ($n -le 0) { break }
                $received++
                $ifIdx = [int]$pktInfo.Interface
                if ($ifHits.ContainsKey($ifIdx)) { $ifHits[$ifIdx]++ } else { $ifHits[$ifIdx] = 1 }
                $hex = ($buf[0..($n - 1)] | ForEach-Object { $_.ToString('x2') }) -join ' '
                $line = "{0:HH:mm:ss.fff} if={1}({2}) localDst={3} dstport={4} len={5} src={6}:{7} data={8}" -f `
                        (Get-Date), $ifIdx, (Get-AdapterLabel $ifIdx), $pktInfo.Address, $c.Port, $n, $ep.Address, $ep.Port, $hex
                Add-Content -Path $OutFile -Value $line -Encoding UTF8
                Write-Host $line
            }
        } catch {
            # socket closed or transient; keep going
        }
    }
    Start-Sleep -Milliseconds 20
}

foreach ($c in $sockets) { try { $c.Socket.Close() } catch {} }

$tail = "# lanprobe stopped {0:yyyy-MM-dd HH:mm:ss.fff} received={1} elapsed={2:N1}s" -f (Get-Date), $received, $sw.Elapsed.TotalSeconds
Add-Content -Path $OutFile -Value $tail -Encoding UTF8
Write-Host $tail

if ($ifHits.Count -gt 0) {
    $summary = "# arrival interfaces: " + (($ifHits.GetEnumerator() | Sort-Object -Property Value -Descending | ForEach-Object {
        "{0}({1})={2}" -f $_.Key, (Get-AdapterLabel $_.Key), $_.Value
    }) -join ' ; ')
    Add-Content -Path $OutFile -Value $summary -Encoding UTF8
    Write-Host $summary
}
