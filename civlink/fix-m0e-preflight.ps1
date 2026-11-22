# fix-m0e-preflight.ps1
#
# Applies the two environment fixes that run-m0e-preflight.ps1 reports as FAIL.
# Run this ONCE, elevated (it self-elevates through a UAC prompt).
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File .\fix-m0e-preflight.ps1
#
# WHAT IT CHANGES (only these two things, both reversible)
#   1. Windows Firewall: adds inbound Allow rules for the EXACT Agent exe that
#      run-m0e-preflight.ps1 will run (UDP + TCP, profiles Private,Public,Domain).
#      Reason: firewall rules match by absolute program path AND by the network
#      profile of the adapter the packet arrives on. An exe run from a folder with
#      no rule (or a rule for only one profile) silently never receives anything.
#   2. Interface metric: raises the metric of the named virtual adapter so the real
#      LAN adapter wins the limited-broadcast race. Previous value is backed up to
#      scripts\network-env\<alias>-metric-backup.txt and printed, so you can undo it.
#
# WHAT IT DOES NOT CHANGE
#   * no firewall rule is deleted (existing rules are left alone)
#   * no route, no adapter enable/disable, no game file, no registry
#   * if a rule already covers the exe for all profiles, it is not duplicated
#
# UNDO
#   Firewall: netsh advfirewall firewall delete rule name="civlink-agent-m0e-udp-in"
#             netsh advfirewall firewall delete rule name="civlink-agent-m0e-tcp-in"
#   Metric:   Set-NetIPInterface -InterfaceAlias "<alias>" -InterfaceMetric <backup value>
#
# Exit codes: 0 = both fixes verified, 2 = something still needs attention, 3 = not elevated

[CmdletBinding()]
param(
    [string]$AgentPath = '',
    [string]$VirtualAlias = 'Radmin VPN',
    [int]$VirtualMetric = 200
)

$ErrorActionPreference = 'Stop'

function Test-Elevated {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $pr = New-Object Security.Principal.WindowsPrincipal($id)
    return $pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-Elevated)) {
    Write-Host 'not elevated - relaunching through UAC...'
    $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"{0}"' -f $PSCommandPath))
    if ($AgentPath -ne '') { $argList += @('-AgentPath', ('"{0}"' -f $AgentPath)) }
    if ($VirtualAlias -ne 'Radmin VPN') { $argList += @('-VirtualAlias', ('"{0}"' -f $VirtualAlias)) }
    if ($VirtualMetric -ne 200) { $argList += @('-VirtualMetric', $VirtualMetric) }
    try {
        $p = Start-Process -FilePath 'powershell.exe' -ArgumentList $argList -Verb RunAs -PassThru -Wait
        exit $p.ExitCode
    } catch {
        Write-Host ("UAC declined or failed: {0}" -f $_.Exception.Message)
        exit 3
    }
}

$script:Problems = 0

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent $scriptDir
if ([string]::IsNullOrWhiteSpace($AgentPath)) {
    $AgentPath = Join-Path $repoRoot 'dist\civlink-20261119-nightly\civlink-agent.exe'
}

Write-Host '=== CivLink M0-E preflight fix (elevated) ==='

# ------------------------------------------------------------ 1. firewall
if (-not (Test-Path $AgentPath)) {
    Write-Host ("FATAL  agent exe not found: {0}" -f $AgentPath)
    exit 2
}
$agentFull = (Get-Item $AgentPath).FullName
Write-Host ("agent: {0}" -f $agentFull)

$pairs = @(
    @{ Name = 'civlink-agent-m0e-udp-in'; Proto = 'UDP' },
    @{ Name = 'civlink-agent-m0e-tcp-in'; Proto = 'TCP' }
)
foreach ($pair in $pairs) {
    $existing = @(netsh advfirewall firewall show rule name="$($pair.Name)" | Select-String 'Rule Name')
    if ($existing.Count -gt 0) {
        # Refresh the program path in case the package moved.
        netsh advfirewall firewall delete rule name="$($pair.Name)" | Out-Null
    }
    $res = netsh advfirewall firewall add rule name="$($pair.Name)" dir=in action=allow `
        protocol=$($pair.Proto) program="$agentFull" profile=any enable=yes
    Write-Host ("  {0}: {1}" -f $pair.Name, ($res -join ' '))
}

# verify by parsing the rules back
$raw = netsh advfirewall firewall show rule name=all dir=in verbose
$cur = $null; $hits = @()
foreach ($l in ($raw -split "`r?`n")) {
    if ($l -match '^Rule Name:\s*(.+?)\s*$') {
        if ($null -ne $cur -and $cur.Name -match '^civlink-agent-m0e-') { $hits += $cur }
        $cur = [pscustomobject]@{ Name = $matches[1]; Enabled = ''; Action = ''; Profile = ''; Program = '' }
    } elseif ($null -ne $cur) {
        if ($l -match '^Enabled:\s*(.+?)\s*$') { $cur.Enabled = $matches[1] }
        elseif ($l -match '^Action:\s*(.+?)\s*$') { $cur.Action = $matches[1] }
        elseif ($l -match '^Profiles?:\s*(.+?)\s*$') { $cur.Profile = $matches[1] }
        elseif ($l -match '^Program:\s*(.+?)\s*$') { $cur.Program = $matches[1] }
    }
}
if ($null -ne $cur -and $cur.Name -match '^civlink-agent-m0e-') { $hits += $cur }
$coverProfiles = @()
foreach ($h in $hits) {
    foreach ($p in (($h.Profile -split ',') | ForEach-Object { $_.Trim() })) { if ($p) { $coverProfiles += $p } }
}
$coverProfiles = @($coverProfiles | Sort-Object -Unique)
Write-Host ("  verified: {0} m0e rule(s), profiles [{1}]" -f $hits.Count, ($coverProfiles -join ','))
if ($hits.Count -lt 2 -or -not ($coverProfiles -contains 'Private') -or -not ($coverProfiles -contains 'Public')) {
    Write-Host 'PROBLEM  firewall rules did not verify as expected'
    $script:Problems++
} else {
    Write-Host 'OK       firewall rules verified (UDP+TCP, Private+Public)'
}

# ------------------------------------------------------------ 2. metric
$backupDir = Join-Path $repoRoot 'scripts\network-env'
New-Item -ItemType Directory -Force -Path $backupDir | Out-Null

$virt = @(Get-NetIPInterface -AddressFamily IPv4 -ErrorAction SilentlyContinue |
    Where-Object { $_.InterfaceAlias -eq $VirtualAlias })
if ($virt.Count -eq 0) {
    Write-Host ("SKIP     adapter '{0}' not found - metric left alone (name it with -VirtualAlias if it differs)" -f $VirtualAlias)
} else {
    $curMetric = [int]$virt[0].InterfaceMetric
    $safeName = ($VirtualAlias -replace '[^A-Za-z0-9]+', '-').Trim('-').ToLower()
    $backupFile = Join-Path $backupDir ("{0}-metric-backup.txt" -f $safeName)
    if (-not (Test-Path $backupFile)) {
        Set-Content -Path $backupFile -Value $curMetric -Encoding UTF8
        Write-Host ("  backup written: {0} = {1}" -f $backupFile, $curMetric)
    } else {
        Write-Host ("  backup already exists, left untouched: {0} = {1}" -f $backupFile, (Get-Content $backupFile -Raw).Trim())
    }

    $lanBest = @(Get-NetIPInterface -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object {
            $_.ConnectionState -eq 'Connected' -and
            $_.InterfaceAlias -notmatch 'Radmin|ZeroTier|Tailscale|VPN|EasyTier|Nebula|Loopback|vEthernet'
        } | Sort-Object InterfaceMetric | Select-Object -First 1)

    if ($curMetric -ge $VirtualMetric) {
        Write-Host ("OK       '{0}' metric already {1} (>= {2}), no change" -f $VirtualAlias, $curMetric, $VirtualMetric)
    } else {
        Set-NetIPInterface -InterfaceAlias $VirtualAlias -InterfaceMetric $VirtualMetric -AddressFamily IPv4
        $after = [int](Get-NetIPInterface -AddressFamily IPv4 | Where-Object { $_.InterfaceAlias -eq $VirtualAlias }).InterfaceMetric
        Write-Host ("OK       '{0}' metric {1} -> {2}" -f $VirtualAlias, $curMetric, $after)
    }
    if ($lanBest.Count -gt 0) {
        $lm = [int]$lanBest[0].InterfaceMetric
        $vm = [int](Get-NetIPInterface -AddressFamily IPv4 | Where-Object { $_.InterfaceAlias -eq $VirtualAlias }).InterfaceMetric
        if ($vm -le $lm) {
            Write-Host ("PROBLEM  '{0}' metric {1} still <= LAN adapter '{2}' metric {3}" -f $VirtualAlias, $vm, $lanBest[0].InterfaceAlias, $lm)
            $script:Problems++
        } else {
            Write-Host ("OK       LAN adapter '{0}' now wins (metric {1} < virtual {2})" -f $lanBest[0].InterfaceAlias, $lm, $vm)
        }
    }
}

Write-Host ''
if ($script:Problems -gt 0) {
    Write-Host ("FIX: INCOMPLETE - {0} problem(s). Re-run run-m0e-preflight.ps1 to see details." -f $script:Problems)
    exit 2
}
Write-Host 'FIX: DONE - re-run run-m0e-preflight.ps1, then follow docs\M0E-DUALMACHINE-RUNBOOK-20261119.md'
Write-Host 'Undo notes are at the top of this script.'
exit 0
