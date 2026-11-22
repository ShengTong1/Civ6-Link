# CivLink M0-A - network path snapshot (read-only, no admin required)
#
# Purpose: both test machines carry many virtual adapters (VMware / Hyper-V / WSL /
# Radmin VPN / ZeroTier / ToDesk / Sunlogin). Before E2 we must know WHICH interface
# a 255.255.255.255 broadcast would leave from, and whether the peer is reachable
# on that same interface. Civ6 sends ONLY 255.255.255.255 (limited broadcast), so the
# binding of that route decides the whole experiment.
#
# ASCII-only on purpose (PowerShell 5.1 reads BOM-less .ps1 as ANSI).
#
# Usage:
#   powershell -NoProfile -ExecutionPolicy Bypass -File netpath.ps1 -PeerIp 26.x.x.x -OutDir .\netpath

param(
    [string]$PeerIp = '',
    [string]$OutDir = (Join-Path $PSScriptRoot '..\..\M0A\captures\netpath')
)

$ErrorActionPreference = 'Continue'
$OutDir = [IO.Path]::GetFullPath($OutDir)
if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory -Force -Path $OutDir | Out-Null }
$out = Join-Path $OutDir 'netpath.txt'
Remove-Item $out -ErrorAction SilentlyContinue

function W([string]$s) {
    Add-Content -Path $out -Value $s -Encoding UTF8
    Write-Host $s
}

W "# netpath snapshot $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
W "# host=$env:COMPUTERNAME user=$env:USERNAME peer=$(if($PeerIp){$PeerIp}else{'(none)'})"
W ""

W "=== [1] adapters (ifIndex / status / speed / mac / name) ==="
try {
    Get-NetAdapter -ErrorAction Stop | Sort-Object ifIndex | ForEach-Object {
        $spd = $_.LinkSpeed
        if (-not $spd) { $spd = '-' }
        W ("  if={0,-3} {1,-12} speed={2,-12} mac={3,-18} {4}" -f `
            $_.ifIndex, $_.Status, $spd, $_.MacAddress, $_.Name)
    }
} catch { W "  (Get-NetAdapter failed: $($_.Exception.Message))" }
W ""
W "  (metrics are in section [3]; adapter-level metric is not reported by Get-NetAdapter)"
W ""

W "=== [2] IPv4 addresses ==="
Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
    Where-Object { $_.IPAddress -ne '127.0.0.1' } | Sort-Object InterfaceIndex | ForEach-Object {
        W ("  if={0,-3} {1}/{2}  {3}" -f $_.InterfaceIndex, $_.IPAddress, $_.PrefixLength, $_.InterfaceAlias)
    }
W ""

W "=== [3] interface metrics (lower wins) ==="
Get-NetIPInterface -AddressFamily IPv4 -ErrorAction SilentlyContinue |
    Sort-Object InterfaceMetric | ForEach-Object {
        W ("  if={0,-3} metric={1,-6} auto={2,-9} state={3,-12} {4}" -f `
            $_.InterfaceIndex, $_.InterfaceMetric, $_.AutomaticMetric, $_.ConnectionState, $_.InterfaceAlias)
    }
W ""

W "=== [4] route resolution for 255.255.255.255 (Civ6 discovery target) ==="
$bcastIf = $null
try {
    $r = Find-NetRoute -RemoteIPAddress '255.255.255.255' -ErrorAction Stop
    $r | ForEach-Object {
        if ($_.PSObject.Properties.Name -contains 'InterfaceIndex') {
            W ("  if={0,-3} {1,-16} srcIp={2,-16} prefix={3,-22} routeMetric={4,-6} ifMetric={5}" -f `
                $_.InterfaceIndex, $_.InterfaceAlias, $_.IPAddress, $_.DestinationPrefix, $_.RouteMetric, $_.InterfaceMetric)
        }
    }
    $first = $r | Where-Object { $_.PSObject.Properties.Name -contains 'InterfaceIndex' } | Select-Object -First 1
    if ($first) {
        $bcastIf = [int]$first.InterfaceIndex
        W ""
        W "  >> BROADCAST WILL LEAVE FROM: if=$bcastIf ($($first.InterfaceAlias)) srcIp=$($first.IPAddress)"
        W "  >> This is the interface Civ6 traffic is expected to use. If the peer is NOT"
        W "     reachable on this interface, E2 discovery will not work as-is."
    }
} catch { W "  (Find-NetRoute failed: $($_.Exception.Message))" }
W ""

W "=== [5] default routes (order matters) ==="
Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue |
    Sort-Object { [int]$_.RouteMetric + [int]$_.InterfaceMetric } | ForEach-Object {
        $alias = (Get-NetAdapter -InterfaceIndex $_.ifIndex -ErrorAction SilentlyContinue).Name
        W ("  if={0,-3} {1,-34} nextHop={2,-16} routeMetric={3,-6} ifMetric={4,-6} total={5}" -f `
            $_.ifIndex, $alias, $_.NextHop, $_.RouteMetric, $_.InterfaceMetric, ([int]$_.RouteMetric + [int]$_.InterfaceMetric))
    }
W ""

if ($PeerIp) {
    W "=== [6] peer reachability per interface (ping -S <localIp> $PeerIp) ==="
    $addrs = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object { $_.IPAddress -ne '127.0.0.1' -and $_.IPAddress -notlike '169.254.*' } | Sort-Object InterfaceIndex
    foreach ($a in $addrs) {
        $res = 'no-reply'
        $rt = ''
        try {
            # native ping with explicit source address (-S); .NET Ping.Send has no
            # local-source overload, so we shell out instead.
            $txt = & ping.exe -n 2 -w 1000 -S $a.IPAddress $PeerIp 2>&1 | Out-String
            if ($txt -match 'TTL=(\d+)') {
                $res = 'SUCCESS'
                $m = [regex]::Match($txt, 'time[=<]\s*(\d+)ms')
                if ($m.Success) { $rt = "$($m.Groups[1].Value)ms" }
            } elseif ($txt -match 'Destination host unreachable') {
                $res = 'UNREACHABLE'
            } elseif ($txt -match '100% loss|100% \D') {
                $res = 'TIMEOUT'
            } elseif ($txt -match 'general failure|General failure') {
                $res = 'GENERAL-FAILURE'
            } else {
                $res = 'no-reply'
            }
        } catch { $res = "error:$($_.Exception.Message)" }
        W ("  from {0,-16} (if={1,-3}) -> {2,-16} {3,-16} {4}" -f $a.IPAddress, $a.InterfaceIndex, $PeerIp, $res, $rt)
    }
    W ""

    W "=== [7] route to peer ==="
    try {
        Find-NetRoute -RemoteIPAddress $PeerIp -ErrorAction Stop | ForEach-Object {
            if ($_.PSObject.Properties.Name -contains 'InterfaceIndex') {
                W ("  if={0,-3} {1,-16} srcIp={2,-16} nextHop={3,-16}" -f $_.InterfaceIndex, $_.InterfaceAlias, $_.IPAddress, $_.NextHop)
            }
        }
    } catch { W "  (Find-NetRoute failed for peer)" }
    W ""
}

W "=== [8] virtual adapter software detected ==="
$patterns = 'Radmin', 'ZeroTier', 'VMware', 'VirtualBox', 'Hyper-V', 'WSL', 'ToDesk', 'Sunlogin', 'Oray', 'Tailscale', 'Hamachi', 'WireGuard', 'OpenVPN'
$found = @()
foreach ($pat in $patterns) {
    try {
        $svc = Get-Service -ErrorAction SilentlyContinue | Where-Object { $_.Name -match $pat -or $_.DisplayName -match $pat }
        if ($svc) { $found += ("  {0}: services = {1}" -f $pat, (($svc | ForEach-Object { "$($_.Name)=$($_.Status)" }) -join ', ')) }
    } catch { }
}
if ($found.Count -eq 0) { W "  (none matched)" } else { $found | ForEach-Object { W $_ } }
W ""

W "=== END ==="
Write-Host ""
Write-Host "written to: $out"
