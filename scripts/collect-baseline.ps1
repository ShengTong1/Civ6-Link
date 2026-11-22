<#
collect-baseline.ps1 -- E0 build + environment baseline collector (CivLink M0-A)

Creates an independent output folder per run (never appends to an old one).

Usage:
  powershell -NoProfile -ExecutionPolicy Bypass -File scripts\collect-baseline.ps1 `
      -GameDir "<SteamLibrary>\steamapps\common\Sid Meier's Civilization VI" [-Tag E0] [-AppId 289070]

Outputs (one folder <Tag>-<yyyyMMdd_HHmmss> under M0A\baseline):
  <label>-sha256.csv         every exe/dll under Base\Binaries\Win64*
  <label>-version.txt        VersionInfo of every exe
  environment.txt            OS / UBR / machine / store / adapters / IPs
  interfaces.txt             NIC index, alias, MAC, MTU, up/down, IPs, prefixes, gateways  (E2 required)
  routes.txt                 active IPv4 routes with interface index and metric            (E2 required)
  firewall.txt               per-profile state + relevant rules summary                     (E2 diff)
  dlc.txt                    DLC folders / appmanifest dlc entries                          (E2 diff)
  steam-buildid.txt          buildid placeholder (fill manually from appmanifest)
  lan-reachability.txt       (only with -PeerIp) ping + route to the peer                    (E2 required)
  summary.md                 human-readable roll-up of everything above

Why interfaces/routes/firewall are captured: the E1 pcapng showed 299/300 discovery
datagrams leaving via the Radmin adapter and 1 via the Hyper-V vSwitch, with the WLAN
address absent. That difference was NOT adjudicated (no route table / interface binding
evidence existed). E2 must capture the same fields on BOTH machines so the interface
question can be answered from data instead of inference.

This script never claims causality and never writes conclusions — it only records facts.
#>

param(
    [Parameter(Mandatory = $true)][string]$GameDir,
    [string]$Tag = "E0",
    [string]$AppId = "289070",
    [string]$OutRoot = "",
    [string]$PeerIp = "",
    [string]$Label = ""
)

$ErrorActionPreference = "Stop"

# $PSScriptRoot is not reliably populated inside param() defaults under PS 5.1,
# so the default output root is resolved here instead.
if ([string]::IsNullOrEmpty($OutRoot)) {
    $scriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
    $OutRoot = Join-Path (Join-Path (Join-Path $scriptDir "..") "..") "M0A\baseline"
}

function Write-Section {
    param([string]$File, [string]$Title, [scriptblock]$Body)
    $lines = @()
    $lines += "# $Title"
    $lines += "# collected = $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') (local)"
    $lines += "# machine   = $env:COMPUTERNAME"
    $lines += ""
    $lines += (& $Body)
    $lines | Set-Content -Path $File -Encoding UTF8
}

if (-not (Test-Path $GameDir)) { Write-Error "GameDir not found: $GameDir" }

$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
if ([string]::IsNullOrEmpty($Label)) { $Label = $Tag }
$outDir = Join-Path $OutRoot ("{0}-{1}" -f $Tag, $stamp)
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

# ---------------------------------------------------------------- binaries
$targets = @(
    "Base\Binaries\Win64Steam",
    "Base\Binaries\Win64EOS"
) | Where-Object { Test-Path (Join-Path $GameDir $_) }

if (-not $targets) { Write-Error "No Base\Binaries\Win64* found under $GameDir" }

foreach ($t in $targets) {
    $bin = Join-Path $GameDir $t
    $sub = ($t -replace '\\', '_')

    $hashFile = Join-Path $outDir ("{0}-sha256.csv" -f $sub)
    "file,sha256" | Set-Content -Path $hashFile -Encoding UTF8
    Get-ChildItem $bin -Include *.exe, *.dll -Recurse | ForEach-Object {
        "{0},{1}" -f $_.Name, (Get-FileHash $_.FullName -Algorithm SHA256).Hash
    } | Add-Content -Path $hashFile -Encoding UTF8

    $verFile = Join-Path $outDir ("{0}-version.txt" -f $sub)
    Get-ChildItem $bin -Filter *.exe | ForEach-Object {
        $v = $_.VersionInfo
        "file=$($_.Name) FileVersion=$($v.FileVersion) ProductVersion=$($v.ProductVersion)"
    } | Set-Content -Path $verFile -Encoding UTF8
}

# ---------------------------------------------------------------- environment
$osInfo = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
$envFile = Join-Path $outDir "environment.txt"
@(
    "collected  = $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') (local)",
    "gameDir    = $GameDir",
    "os         = $([System.Environment]::OSVersion.VersionString)",
    "productName= $($osInfo.ProductName)",
    "buildUbr   = $($osInfo.UBR)",
    "displayVer = $($osInfo.DisplayVersion)",
    "buildLab   = $($osInfo.BuildLabEx)",
    "machine    = $env:COMPUTERNAME",
    "user       = $env:USERNAME",
    "admin      = $((([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)))",
    "store      = $(if (Test-Path (Join-Path $GameDir 'Base\Binaries\Win64EOS')) { 'Steam+EOS' } else { 'Steam' })",
    "timezone   = $((Get-TimeZone).Id)",
    "culture    = $((Get-Culture).Name)",
    ""
    "netAdapters:",
    (Get-NetAdapter | ForEach-Object {
        "  index=$($_.ifIndex) name='$($_.Name)' status=$($_.Status) desc='$($_.InterfaceDescription)' speed=$($_.LinkSpeed) mac=$($_.MacAddress)"
    }),
    "ipConfig:",
    (Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | ForEach-Object {
        "  ifIndex=$($_.InterfaceIndex) alias='$($_.InterfaceAlias)' ip=$($_.IPAddress)/$($_.PrefixLength)"
    }),
    "dnsServers:",
    (Get-DnsClientServerAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | ForEach-Object {
        "  ifIndex=$($_.InterfaceIndex) servers=$($_.ServerAddresses -join ',')"
    })
) | Set-Content -Path $envFile -Encoding UTF8

# ---------------------------------------------------------------- interfaces (E2 required)
Write-Section -File (Join-Path $outDir "interfaces.txt") -Title "Network interfaces (index / alias / MAC / MTU / status / IPs / gateways)" -Body {
    $out = @()
    $ips = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue
    $gws = Get-NetRoute -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue
    foreach ($a in (Get-NetAdapter -IncludeHidden -ErrorAction SilentlyContinue | Sort-Object ifIndex)) {
        $myIps = @($ips | Where-Object { $_.InterfaceIndex -eq $a.ifIndex })
        $ipStr = if ($myIps.Count) { ($myIps | ForEach-Object { "$($_.IPAddress)/$($_.PrefixLength)" }) -join " " } else { "-" }
        $gwStr = (($gws | Where-Object { $_.InterfaceIndex -eq $a.ifIndex } | ForEach-Object { "$($_.NextHop)(metric=$($_.RouteMetric))" }) -join ",")
        if (-not $gwStr) { $gwStr = "-" }
        $out += ("ifIndex={0,-4} status={1,-12} alias='{2}' mac={3} mtu={4} speed={5} ip=[{6}] gateway=[{7}] desc='{8}'" -f `
            $a.ifIndex, $a.Status, $a.Name, $a.MacAddress, $a.MtuSize, $a.LinkSpeed, $ipStr, $gwStr, $a.InterfaceDescription)
    }
    $out
}

# ---------------------------------------------------------------- routes (E2 required)
Write-Section -File (Join-Path $outDir "routes.txt") -Title "Active IPv4 routes (destination / ifIndex / next hop / metric)" -Body {
    $out = @()
    $out += "--- default routes (0.0.0.0/0), in the order Windows would prefer ---"
    $def = Get-NetRoute -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue |
        Sort-Object RouteMetric, ifIndex
    foreach ($r in $def) {
        $alias = (Get-NetAdapter -IncludeHidden -ErrorAction SilentlyContinue |
            Where-Object ifIndex -eq $r.ifIndex | Select-Object -First 1).Name
        $out += ("  ifIndex={0,-4} ifMetric={1,-6} routeMetric={2,-6} nextHop={3,-16} alias='{4}'" -f `
            $r.ifIndex, $r.InterfaceMetric, $r.RouteMetric, $r.NextHop, $alias)
    }
    $out += ""
    $out += "--- all IPv4 routes that touch a private/broadcast-relevant destination ---"
    foreach ($x in (Get-NetRoute -AddressFamily IPv4 -ErrorAction SilentlyContinue |
            Sort-Object ifIndex, DestinationPrefix)) {
        $out += ("  ifIndex={0,-4} dest={1,-22} nextHop={2,-16} metric={3,-6} proto={4}" -f `
            $x.ifIndex, $x.DestinationPrefix, $x.NextHop, $x.RouteMetric, $x.Protocol)
    }
    $out
}

# ---------------------------------------------------------------- firewall (E2 diff)
Write-Section -File (Join-Path $outDir "firewall.txt") -Title "Windows Firewall state and rules that could affect UDP discovery / game traffic" -Body {
    $out = @()
    try {
        $prof = Get-NetFirewallProfile -ErrorAction Stop
        foreach ($p in $prof) {
            $out += ("profile={0,-10} enabled={1} defaultInbound={2} defaultOutbound={3} notifyOnBlock={4}" -f `
                $p.Name, $p.Enabled, $p.DefaultInboundAction, $p.DefaultOutboundAction, $p.NotifyOnListen)
        }
    } catch {
        $out += "Get-NetFirewallProfile failed: $($_.Exception.Message)"
    }
    $out += ""
    $out += "--- rules mentioning Civilization / Civ / 2K / Steam (name or program), plus enabled inbound Block rules ---"
    try {
        $rules = Get-NetFirewallRule -ErrorAction Stop | Where-Object {
            $_.DisplayName -match 'Civilization|Civ\s?6|2K|Steam|Epic' -or
            ($_.Direction -eq 'Inbound' -and $_.Enabled -eq 'True' -and $_.Action -eq 'Block')
        } | Select-Object -First 120
        foreach ($r in $rules) {
            $app = ""
            try { $app = ($r | Get-NetFirewallApplicationFilter -ErrorAction SilentlyContinue).Program } catch { }
            $out += ("  name='{0}' dir={1} action={2} enabled={3} profile={4} proto={5} app='{6}'" -f `
                $r.DisplayName, $r.Direction, $r.Action, $r.Enabled, $r.Profile, $r.Protocol, $app)
        }
        if (-not $rules) { $out += "  (no matching rules)" }
    } catch {
        $out += "Get-NetFirewallRule failed: $($_.Exception.Message)"
    }
    $out
}

# ---------------------------------------------------------------- DLC (E2 diff)
Write-Section -File (Join-Path $outDir "dlc.txt") -Title "DLC / expansion folders and appmanifest dlc entries" -Body {
    $out = @()
    $dlcDir = Join-Path $GameDir "DLC"
    if (Test-Path $dlcDir) {
        $out += "--- DLC folders (name | has .modinfo) ---"
        foreach ($dir in (Get-ChildItem $dlcDir -Directory | Sort-Object Name)) {
            $hasMod = @(Get-ChildItem (Join-Path $dir.FullName "*.modinfo") -ErrorAction SilentlyContinue).Count -gt 0
            $out += ("  {0}  modinfo={1}" -f $dir.Name, $hasMod)
        }
    } else {
        $out += "no DLC folder under $GameDir"
    }
    $out += ""
    $out += "--- appmanifest_$AppId.acf (installdir / buildid / StateFlags / LastUpdated) ---"
    # GameDir = <library>\steamapps\common\<game>  ->  library = three levels up
    $libRoot = Split-Path (Split-Path (Split-Path $GameDir -Parent) -Parent) -Parent
    $acf = Join-Path $libRoot "steamapps\appmanifest_$AppId.acf"
    $out += "  derived acf path = $acf   (exists=$(Test-Path $acf))"
    if (-not (Test-Path $acf)) {
        $candidates = @()
        $steamRoot = ""
        try { $steamRoot = (Get-ItemProperty 'HKCU:\Software\Valve\Steam' -ErrorAction Stop).SteamPath } catch { }
        if ($steamRoot) {
            $vdf = Join-Path $steamRoot "steamapps\libraryfolders.vdf"
            if (Test-Path $vdf) {
                $vtxt = Get-Content $vdf -Raw
                foreach ($m in [regex]::Matches($vtxt, '"path"\s+"([^"]+)"')) {
                    $pp = $m.Groups[1].Value -replace '\\\\', '\'
                    $candidates += (Join-Path $pp "steamapps\appmanifest_$AppId.acf")
                }
            }
        }
        $candidates += "D:\SteamLibrary\steamapps\appmanifest_$AppId.acf"
        $candidates += "E:\SteamLibrary\steamapps\appmanifest_$AppId.acf"
        $candidates += "C:\Program Files (x86)\Steam\steamapps\appmanifest_$AppId.acf"
        $found = $candidates | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
        if ($found) { $acf = $found; $out += "  fallback acf path = $acf" }
        else { $out += "  libraryfolders candidates tried: $($candidates -join ' ; ')" }
    }
    if (Test-Path $acf) {
        $txt = Get-Content $acf -Raw
        foreach ($m in [regex]::Matches($txt, '"(buildid|installdir|StateFlags|LastUpdated)"\s+"([^"]*)"')) {
            $out += ("  {0} = {1}" -f $m.Groups[1].Value, $m.Groups[2].Value)
        }
        $dlcs = [regex]::Matches($txt, '"(?<id>\d{4,7})"\s*\{[^}]*?"Installed"\s+"(?<inst>\d)"', 'Singleline')
        foreach ($d in $dlcs) { $out += ("  dlc {0} installed={1}" -f $d.Groups['id'].Value, $d.Groups['inst'].Value) }
        if (-not $dlcs) { $out += "  (no per-dlc Installed entries parsed)" }
    } else {
        $out += "  appmanifest NOT FOUND"
    }
    $out
}

# ---------------------------------------------------------------- LAN reachability (E2 required)
if ($PeerIp) {
    Write-Section -File (Join-Path $outDir "lan-reachability.txt") -Title "Reachability to peer $PeerIp (same-LAN precondition for E2)" -Body {
        $out = @()
        $out += "--- Test-Connection (4 attempts, no DNS) ---"
        try {
            $r = Test-Connection -ComputerName $PeerIp -Count 4 -ErrorAction Stop
            foreach ($x in $r) { $out += ("  reply from {0} time={1}ms" -f $x.Address, $x.ResponseTime) }
        } catch {
            $out += "  Test-Connection FAILED: $($_.Exception.Message)"
        }
        $out += ""
        $out += "--- route Windows would use to reach $PeerIp ---"
        try {
            foreach ($fr in (Find-NetRoute -RemoteIPAddress $PeerIp -ErrorAction Stop)) {
                $out += ("  ifIndex={0} localIP={1} dest={2} nextHop={3}" -f `
                    $fr.InterfaceIndex, $fr.IPAddress, $fr.DestinationPrefix, $fr.NextHop)
            }
        } catch {
            $out += "  Find-NetRoute FAILED: $($_.Exception.Message)"
        }
        $out += ""
        $out += "--- tracert (max 5 hops, no DNS) ---"
        try {
            foreach ($ln in (& tracert.exe -d -h 5 -w 800 $PeerIp 2>&1)) { $out += ("  " + $ln) }
        } catch {
            $out += "  tracert FAILED: $($_.Exception.Message)"
        }
        $out
    }
}

# ---------------------------------------------------------------- steam buildid
$buildFile = Join-Path $outDir "steam-buildid.txt"
@"
# Fill in from the Steam library page -> game properties, or from appmanifest_$AppId.acf (buildid field).
# appmanifest location: <SteamLibrary>\steamapps\appmanifest_$AppId.acf
# Do NOT substitute the exe FileVersion for the Steam buildid.
buildid =
collected = $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
machine   = $env:COMPUTERNAME
"@ | Set-Content -Path $buildFile -Encoding UTF8

# ---------------------------------------------------------------- summary.md
$summaryFile = Join-Path $outDir "summary.md"
$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine("# E0 baseline summary - $Tag on $env:COMPUTERNAME")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("- collected: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') (local)")
[void]$sb.AppendLine("- machine: $env:COMPUTERNAME")
[void]$sb.AppendLine("- gameDir: ``$GameDir``")
[void]$sb.AppendLine("- store: $(if (Test-Path (Join-Path $GameDir 'Base\Binaries\Win64EOS')) { 'Steam+EOS' } else { 'Steam (no Win64EOS)' })")
[void]$sb.AppendLine("- OS: $($osInfo.ProductName) build $($osInfo.CurrentBuild).$($osInfo.UBR) ($($osInfo.DisplayVersion))")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("## Key binary hashes")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("| file | sha256 |")
[void]$sb.AppendLine("|------|--------|")
foreach ($h in (Get-ChildItem $outDir -Filter "*-sha256.csv")) {
    Import-Csv $h.FullName | Where-Object { $_.file -match 'CivilizationVI(_DX12)?\.exe|steam_api64\.dll|EOSSDK.*\.dll' } |
        ForEach-Object { [void]$sb.AppendLine("| ``$($_.file)`` | ``$($_.sha256)`` |") }
}
[void]$sb.AppendLine("")
[void]$sb.AppendLine("## Interfaces (from interfaces.txt)")
[void]$sb.AppendLine("")
[void]$sb.AppendLine('```')
Get-Content (Join-Path $outDir "interfaces.txt") | Where-Object { $_ -match '^ifIndex=' } |
    ForEach-Object { [void]$sb.AppendLine($_) }
[void]$sb.AppendLine('```')
[void]$sb.AppendLine("")
[void]$sb.AppendLine("## Default routes (from routes.txt)")
[void]$sb.AppendLine("")
[void]$sb.AppendLine('```')
$inDef = $false
Get-Content (Join-Path $outDir "routes.txt") | ForEach-Object {
    if ($_ -match 'default routes') { $inDef = $true; return }
    if ($inDef -and $_ -match '^\s+ifIndex=') { [void]$sb.AppendLine($_) }
    elseif ($inDef -and $_ -match '^---' -and $_ -notmatch 'default') { $inDef = $false }
}
[void]$sb.AppendLine('```')
[void]$sb.AppendLine("")
[void]$sb.AppendLine("## Firewall profiles (from firewall.txt)")
[void]$sb.AppendLine("")
[void]$sb.AppendLine('```')
Get-Content (Join-Path $outDir "firewall.txt") | Where-Object { $_ -match '^profile=' } |
    ForEach-Object { [void]$sb.AppendLine($_) }
[void]$sb.AppendLine('```')
if ($PeerIp) {
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("## Peer reachability ($PeerIp)")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine('```')
    Get-Content (Join-Path $outDir "lan-reachability.txt") | ForEach-Object { [void]$sb.AppendLine($_) }
    [void]$sb.AppendLine('```')
}
[void]$sb.AppendLine("")
[void]$sb.AppendLine("> This file records measurements only. It makes no claim about which adapter")
[void]$sb.AppendLine("> the game's broadcast actually leaves from - that must be shown by E2's")
[void]$sb.AppendLine("> simultaneous pcapng on both ends, not inferred here.")
[IO.File]::WriteAllText($summaryFile, $sb.ToString(), (New-Object System.Text.UTF8Encoding($false)))

Write-Host ""
Write-Host "[+] baseline written to: $outDir"
Write-Host "[!] ACTION REQUIRED: fill steam-buildid.txt (buildid field) manually"
$outNames = @("environment.txt", "interfaces.txt", "routes.txt", "firewall.txt", "dlc.txt", "summary.md", "steam-buildid.txt")
if ($PeerIp) { $outNames += "lan-reachability.txt" }
Get-ChildItem $outDir -File | Where-Object { $outNames -contains $_.Name } |
    Format-Table Name, Length -AutoSize
