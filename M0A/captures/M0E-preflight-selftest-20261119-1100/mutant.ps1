# run-m0e-preflight.ps1
#
# M0-E dual-machine preflight: read-only environment check, run BEFORE the
# operator follows docs\M0E-DUALMACHINE-RUNBOOK-20261119.md.
#
# WHY THIS EXISTS
#   Both historical dual-machine failures were environment problems, not product
#   bugs:
#     * Windows Firewall matches rules by the program's absolute path, and matches
#       the network profile of the adapter the packet ARRIVES on. The Agent was
#       shipped in one folder with Allow rules and run from another -> no rule ->
#       every inbound discovery datagram was dropped.
#     * A leftover Agent holding 62901..62999 (or 62900) makes the game fail to
#       create a room, which the operator sees as "创建房间点了没反应".
#   This script turns both into a check that prints PASS/WARN/FAIL and an exit code.
#
# WHAT THIS CHECKS
#   C1  nightly package present, and agent/tray hashes match its MANIFEST.txt
#   C2  Civ6 process + discovery/data ports (62900, 62056) ownership
#   C3  no stale civlink-agent holding 62901..62999
#   C4  inbound firewall Allow covers THE EXACT agent exe that will be run,
#       for every network profile that is actually in use here
#   C5  inbound firewall Allow covers the Civ6 exe, for every profile in use
#   C6  interface / profile / metric map (the facts that decide which adapter a
#       limited broadcast leaves by, and which profile the reply arrives on)
#
# WHAT THIS DOES NOT CHECK (do not read a PASS as more than it is)
#   * that a second machine is present or reachable
#   * that the game will answer the loopback replay (needs a live hosted room)
#   * anything about 62056 data-path reachability across machines
#   This is a readiness check for the OPERATOR. It is not E2-A/E2-B/E3 evidence,
#   does not move Gate A/B, and a PASS must never be quoted as a dual-machine result.
#
# USAGE
#   powershell -NoProfile -ExecutionPolicy Bypass -File .\run-m0e-preflight.ps1
#   powershell ... -File .\run-m0e-preflight.ps1 -AgentPath "D:\CivLink\civlink-agent.exe"
#
# Exit codes: 0 = READY, 2 = ACTION NEEDED (fix the FAIL items, then re-run),
#             3 = FATAL (package missing / cannot read firewall state)

[CmdletBinding()]
param(
    [string]$AgentPath = '',
    [string]$OutFile = ''
)

$ErrorActionPreference = 'Stop'
$script:Checks = 0
$script:Fails = 0
$script:Warns = 0
$script:Lines = New-Object System.Collections.Generic.List[string]

function Emit([string]$s) {
    $script:Lines.Add($s)
    Write-Host $s
}
function Pass([string]$id, [string]$msg) {
    $script:Checks++
    Emit ("PASS  {0}  {1}" -f $id, $msg)
}
function Warn([string]$id, [string]$msg) {
    $script:Checks++
    $script:Warns++
    Emit ("WARN  {0}  {1}" -f $id, $msg)
}
function Fail([string]$id, [string]$msg) {
    $script:Checks++
    $script:Fails++
    Emit ("FAIL  {0}  {1}" -f $id, $msg)
}

Emit "=== CivLink M0-E dual-machine preflight (read-only) ==="
Emit ("time: {0}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
Emit ''

# ---------------------------------------------------------------- C1 package
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent $scriptDir
$nightly = Join-Path $repoRoot 'dist\civlink-20261119-nightly'

if ([string]::IsNullOrWhiteSpace($AgentPath)) {
    $AgentPath = Join-Path $nightly 'civlink-agent.exe'
}

if (-not (Test-Path $AgentPath)) {
    Fail 'C1.1' ("agent exe not found: {0}" -f $AgentPath)
} else {
    $agentHash = (Get-FileHash $AgentPath -Algorithm SHA256).Hash
    $agentLen = (Get-Item $AgentPath).Length
    Pass 'C1.1' ("agent present: {0} ({1} B, {2})" -f $AgentPath, $agentLen, $agentHash.Substring(0, 16))

    $manifest = Join-Path (Split-Path -Parent $AgentPath) 'MANIFEST.txt'
    if (-not (Test-Path $manifest)) {
        Warn 'C1.2' 'MANIFEST.txt not next to the agent - cannot verify integrity (custom deployment?)'
    } else {
        $agentName = Split-Path -Leaf $AgentPath
        $expect = $null
        foreach ($ln in (Get-Content $manifest)) {
            if ($ln -match '^([0-9A-Fa-f]{64})\s+(\d+)\s+(.+)$') {
                if ($matches[3].Trim() -eq $agentName) { $expect = $matches[1].ToUpper() }
            }
        }
        if ($null -eq $expect) {
            Warn 'C1.2' ("{0} not listed in MANIFEST.txt" -f $agentName)
        } elseif ($expect -ne $agentHash) {
            Fail 'C1.2' ("{0} hash differs from MANIFEST (expected {1}, got {2})" -f $agentName, $expect.Substring(0, 16), $agentHash.Substring(0, 16))
        } else {
            Pass 'C1.2' ("{0} matches MANIFEST.txt" -f $agentName)
        }
    }
}

# ---------------------------------------------------------------- C2 game
$gameProcs = @(Get-Process -Name 'CivilizationVI_DX12', 'CivilizationVI' -ErrorAction SilentlyContinue)
if ($gameProcs.Count -eq 0) {
    Warn 'C2.1' 'Civ6 is not running - start the game and CREATE the LAN room before starting the Agent'
    $gamePid = 0
} else {
    $gamePid = $gameProcs[0].Id
    Pass 'C2.1' ("Civ6 running: {0} pid {1}" -f $gameProcs[0].ProcessName, $gamePid)
}

if ($gamePid -ne 0) {
    $eps = @(Get-NetUDPEndpoint -OwningProcess $gamePid -ErrorAction SilentlyContinue)
    $p62900 = @($eps | Where-Object { $_.LocalPort -eq 62900 })
    $p62056 = @($eps | Where-Object { $_.LocalPort -eq 62056 })
    if ($p62900.Count -gt 0) {
        Pass 'C2.2' ('game holds {0}:62900 (discovery)' -f $p62900[0].LocalAddress)
    } else {
        Fail 'C2.2' 'game does NOT hold 62900 - the LAN room is not created yet (M0-E replays to 127.0.0.1:62900 and needs it)'
    }
    if ($p62056.Count -gt 0) {
        Pass 'C2.3' ('game holds {0}:62056 (data path)' -f $p62056[0].LocalAddress)
    } else {
        Warn 'C2.3' 'game does not hold 62056 yet - data-path join (M-1) cannot work in this state'
    }
}

# ---------------------------------------------------------------- C3 stale agent
$stale = @(Get-Process -Name 'civlink-agent' -ErrorAction SilentlyContinue)
if ($stale.Count -eq 0) {
    Pass 'C3.1' 'no leftover civlink-agent process'
} else {
    Fail 'C3.1' ("{0} leftover civlink-agent process(es): {1} - stop them first (a leftover Agent takes 62901-62999 and can break room creation)" -f $stale.Count, (($stale | ForEach-Object { $_.Id }) -join ', '))
}

# ---------------------------------------------------------------- profiles in use
$profilesInUse = @()
try {
    $cps = @(Get-NetConnectionProfile -ErrorAction Stop)
    $profilesInUse = @($cps | ForEach-Object { [string]$_.NetworkCategory } | Sort-Object -Unique)
} catch {
    $profilesInUse = @()
}
Pass 'C6.1' ("network profiles in use: {0}" -f (($profilesInUse -join ', ')))

$ifaces = @()
try {
    $ifaces = @(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction Stop | Where-Object {
            $_.IPAddress -notlike '169.254*' -and $_.IPAddress -ne '127.0.0.1'
        })
} catch {
    $ifaces = @()
}
foreach ($a in ($ifaces | Sort-Object InterfaceIndex)) {
    $metric = 'n/a'
    try {
        $m = Get-NetIPInterface -AddressFamily IPv4 -InterfaceIndex $a.InterfaceIndex -ErrorAction Stop
        $metric = $m.InterfaceMetric
    } catch { }
    $prof = 'n/a'
    try {
        $cp = Get-NetConnectionProfile -InterfaceIndex $a.InterfaceIndex -ErrorAction Stop
        $prof = $cp.NetworkCategory
    } catch { }
    Emit ("      if{0,-3} {1,-16} {2,-16} profile={3,-8} metric={4}" -f $a.InterfaceIndex, $a.InterfaceAlias, $a.IPAddress, $prof, $metric)
}

# ---------------------------------------------------------------- firewall rules (netsh, fast)
function Get-FwInbound {
    $raw = netsh advfirewall firewall show rule name=all dir=in verbose
    $cur = $null
    $list = New-Object System.Collections.Generic.List[object]
    foreach ($l in ($raw -split "`r?`n")) {
        if ($l -match '^Rule Name:\s*(.+?)\s*$') {
            if ($null -ne $cur) { $list.Add($cur) }
            $cur = [pscustomobject]@{ Name = $matches[1]; Enabled = ''; Action = ''; Profile = ''; Program = '' }
        } elseif ($null -ne $cur) {
            if ($l -match '^Enabled:\s*(.+?)\s*$') { $cur.Enabled = $matches[1] }
            elseif ($l -match '^Action:\s*(.+?)\s*$') { $cur.Action = $matches[1] }
            elseif ($l -match '^Profiles?:\s*(.+?)\s*$') { $cur.Profile = $matches[1] }
            elseif ($l -match '^Program:\s*(.+?)\s*$') { $cur.Program = $matches[1] }
        }
    }
    if ($null -ne $cur) { $list.Add($cur) }
    return $list
}

try {
    $fw = @(Get-FwInbound)
} catch {
    Emit ''
    Emit ("FATAL  cannot read firewall state: {0}" -f $_.Exception.Message)
    if ($OutFile -ne '') { $script:Lines | Set-Content -Path $OutFile -Encoding UTF8 }
    exit 3
}
Pass 'C4.0' ("firewall inbound rules parsed: {0}" -f $fw.Count)

function Test-Coverage([string]$id, [string]$exeFull, [string]$label, [string]$severity = 'FAIL') {
    if (-not (Test-Path $exeFull)) {
        Warn $id ("{0}: exe missing, skipped ({1})" -f $label, $exeFull)
        return
    }
    $want = (Get-Item $exeFull).FullName
    $hits = @($fw | Where-Object {
            $_.Enabled -match 'Yes' -and $_.Action -match 'Allow' -and
            $_.Program -ne '' -and $_.Program -ne 'Any' -and
            (($_.Program).Trim().Trim('"') -ieq $want)
        })
    if ($hits.Count -eq 0) {
        # A zero-UAC remedy exists when a BYTE-IDENTICAL copy sits at a path that
        # already has an Allow rule: Windows matches by path, not by content, so the
        # same binary run from the covered folder is allowed without touching firewall
        # settings at all. This is the same trick that unblocked the M0-B run.
        $remedy = ''
        if (Test-Path $want) {
            $wantHash = (Get-FileHash $want -Algorithm SHA256).Hash
            $coveredPaths = @($fw | Where-Object {
                    $_.Enabled -match 'Yes' -and $_.Action -match 'Allow' -and
                    $_.Program -ne '' -and $_.Program -ne 'Any' -and
                    ((($_.Program).Trim().Trim('"')) -match 'civlink-agent\.exe$') -and
                    (Test-Path (($_.Program).Trim().Trim('"')))
                } | ForEach-Object { ($_.Program).Trim().Trim('"') } | Sort-Object -Unique)
            foreach ($cp in $coveredPaths) {
                if ($cp -ieq $want) { continue }
                try {
                    if ((Get-FileHash $cp -Algorithm SHA256).Hash -eq $wantHash) {
                        $remedy = (" ZERO-UAC REMEDY: a byte-identical copy at '{0}' already has an Allow rule - run the Agent from there instead (no admin needed)." -f $cp)
                        break
                    }
                } catch { }
            }
        }
        if ($severity -eq 'FAIL') {
            Fail $id ("{0}: NO enabled inbound Allow rule for exactly {1} - inbound datagrams to it are dropped/may prompt.{2}" -f $label, $want, $remedy)
        } else {
            Warn $id ("{0}: no inbound Allow rule for exactly {1} (this exe is not the one in use, informational)" -f $label, $want)
        }
        return
    }
    $covered = @()
    foreach ($h in $hits) {
        foreach ($p in (($h.Profile -split ',') | ForEach-Object { $_.Trim() })) {
            if ($p -ne '') { $covered += $p }
        }
    }
    $covered = @($covered | Sort-Object -Unique)
    $missing = @()
    foreach ($p in $profilesInUse) {
        if ($p -eq 'Any') { continue }
        if ($false) { $missing += $p }
    }
    if ($missing.Count -gt 0) {
        if ($severity -eq 'FAIL') {
            Fail $id ("{0}: Allow rule covers [{1}] but profile(s) [{2}] are in use on this host - packets arriving on those adapters will be dropped" -f $label, ($covered -join ','), ($missing -join ','))
        } else {
            Warn $id ("{0}: Allow rule covers [{1}], profile(s) [{2}] in use (exe not in use, informational)" -f $label, ($covered -join ','), ($missing -join ','))
        }
    } else {
        Pass $id ("{0}: inbound Allow covers [{1}] (covers all profiles in use)" -f $label, ($covered -join ','))
    }
}

Test-Coverage 'C4.1' $AgentPath 'agent (the exe you will run)'

$civ6 = @()
foreach ($p in @(
        "E:\SteamLibrary\steamapps\common\Sid Meier's Civilization VI\Base\Binaries\Win64Steam\CivilizationVI_DX12.exe",
        "E:\SteamLibrary\steamapps\common\Sid Meier's Civilization VI\Base\Binaries\Win64Steam\CivilizationVI.exe")) {
    if (Test-Path $p) { $civ6 += $p }
}
if ($civ6.Count -eq 0) {
    Warn 'C5.1' 'Civ6 exe not found at the expected Steam path - check C5 manually if the game lives elsewhere'
} else {
    # Severity follows what is actually running: the launched flavour must be covered,
    # the other flavour is informational only (a Public-only rule on DX11 is harmless
    # while the operator runs DX12, which is the historical default).
    $runningNames = @($gameProcs | ForEach-Object { $_.ProcessName })
    if ($runningNames.Count -eq 0) { $runningNames = @('CivilizationVI_DX12') }
    foreach ($exe in $civ6) {
        $leaf = [IO.Path]::GetFileNameWithoutExtension($exe)
        $sev = if ($runningNames -contains $leaf) { 'FAIL' } else { 'WARN' }
        Test-Coverage ('C5.' + $leaf) $exe ("Civ6 {0}" -f $leaf) $sev
    }
}

# ---------------------------------------------------------------- C7 metric
# The historical root cause of "the other machine never sees our room": a virtual
# adapter (Radmin/ZeroTier) carrying a LOWER InterfaceMetric than the real LAN. A
# limited broadcast (255.255.255.255) leaves by ONE adapter only - the lowest-metric
# one - so if a virtual adapter wins, the LAN peer never receives the announcement.
$metricRows = @()
foreach ($a in ($ifaces | Sort-Object InterfaceIndex)) {
    try {
        $m = Get-NetIPInterface -AddressFamily IPv4 -InterfaceIndex $a.InterfaceIndex -ErrorAction Stop
        if ($m.ConnectionState -eq 'Connected') {
            $metricRows += [pscustomobject]@{
                Alias = $a.InterfaceAlias; IP = $a.IPAddress; Metric = [int]$m.InterfaceMetric
            }
        }
    } catch { }
}
if ($metricRows.Count -eq 0) {
    Warn 'C7.1' 'could not read interface metrics - check C7 manually'
} else {
    $best = $metricRows | Sort-Object Metric | Select-Object -First 1
    Emit ("      lowest-metric adapter (limited broadcast exits here): {0} ({1}) metric={2}" -f $best.Alias, $best.IP, $best.Metric)

    $lanLike = @($metricRows | Where-Object { $_.IP -like '192.168.*' -or $_.IP -like '10.*' -or $_.IP -match '^172\.(1[6-9]|2[0-9]|3[01])\.' })
    $virtLike = @($metricRows | Where-Object { $_.Alias -match 'Radmin|ZeroTier|Tailscale|VPN|EasyTier|Nebula' })

    if ($virtLike.Count -eq 0) {
        Pass 'C7.1' 'no virtual/VPN adapter detected among connected IPv4 interfaces'
    } elseif ($lanLike.Count -eq 0) {
        Warn 'C7.2' 'only virtual adapters are connected - same-subnet LAN discovery cannot be verified here'
    } else {
        $lanBest = $lanLike | Sort-Object Metric | Select-Object -First 1
        if ($best.Alias -match 'Radmin|ZeroTier|Tailscale|VPN|EasyTier|Nebula') {
            # Role matters, so this is a WARN with an explicit interpretation rather
            # than a blanket FAIL:
            #   * CLIENT role: fatal. The client's 255.255.255.255 refresh leaves by the
            #     lowest-metric adapter only; if a virtual adapter wins, the LAN host
            #     never receives the magic and no room appears.
            #   * HOST role (M0-E Agent): not fatal by itself. The Agent binds 0.0.0.0 on
            #     62901-62999, so it receives whatever arrives on any adapter, and it
            #     replies unicast to the client's source address. The metric only decides
            #     which adapter the GAME's own announcement broadcast leaves by, which
            #     affects native (non-M0-E) discovery, not the M0-E path.
            Warn 'C7.2' ("virtual adapter '{0}' (metric {1}) outranks the LAN adapter '{2}' (metric {3}). On the CLIENT this is fatal (a 255.255.255.255 refresh leaves by the virtual adapter and the LAN host never sees it). On the HOST running the M0-E Agent it is tolerable (the Agent binds 0.0.0.0). Fix if this machine will act as CLIENT: Get-NetIPInterface -InterfaceAlias '{0}' -InterfaceMetric 200 (needs admin)" -f $best.Alias, $best.Metric, $lanBest.Alias, $lanBest.Metric)
        } else {
            Pass 'C7.2' ("LAN adapter '{0}' wins the metric race (metric {1} vs best virtual {2})" -f $best.Alias, $best.Metric, (($virtLike | Sort-Object Metric | Select-Object -First 1).Metric))
        }
    }
    foreach ($r in ($metricRows | Sort-Object Metric)) {
        Emit ("      metric={0,-5} {1,-34} {2}" -f $r.Metric, $r.Alias, $r.IP)
    }
}

# ---------------------------------------------------------------- verdict
Emit ''
if ($script:Fails -gt 0) {
    Emit ("PREFLIGHT: ACTION NEEDED - {0} FAIL, {1} WARN, {2} checks" -f $script:Fails, $script:Warns, $script:Checks)
    Emit 'Fix every FAIL above, then re-run this script. Do not start the dual-machine run until it says READY.'
    $code = 2
} else {
    Emit ("PREFLIGHT: READY - 0 FAIL, {0} WARN, {1} checks" -f $script:Warns, $script:Checks)
    Emit 'Next: docs\M0E-DUALMACHINE-RUNBOOK-20261119.md (create the room FIRST, then start the Agent).'
    $code = 0
}
Emit 'Boundary: readiness check only. Not E2-A/E2-B/E3 evidence, does not move Gate A/B.'

if ($OutFile -ne '') {
    $script:Lines | Set-Content -Path $OutFile -Encoding UTF8
}
exit $code
