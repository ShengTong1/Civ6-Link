# run-f5-b-probe.ps1 - F5 dual-machine one-shot probe for PC-B (the client side).
#
# Sends a Civ6-style discovery burst (one 4-byte magic per port 62900..62999, all from
# ONE fixed local port) to the LAN broadcast address, then waits for the simulated-host
# reply (22 pages of 1104 B) and reports whether it arrived.
#
# This is EXACTLY the mechanism a real Civ6 LAN client uses when the user clicks
# Refresh. If PC-A runs `--sim-lan-listen 0.0.0.0` and this probe receives the
# 22-page fixture, then a real Civ6 on PC-B would show the simulated room too.
#
# Usage (on PC-B, run from any directory):
#   powershell.exe -NoProfile -ExecutionPolicy Bypass -File run-f5-b-probe.ps1
#     [-OutRoot DIR]        evidence dir (default: Desktop\civlink-f5-b-probe-out)
#     [-LocalPort 54321]    fixed local port the burst is sent from and the reply is
#                           received on (a firewall allow rule is added for it)
#     [-WaitMs 4000]        how long to wait for replies
#
# Exit codes: 0 = PASS (22 pages received), 1 = FAIL (no/partial reply),
#             2 = setup error.
#
# The script self-elevates (one UAC prompt) because adding the inbound firewall rule
# needs admin. The rule is removed before exit. Evidence files:
#   probe-console.txt / probe-stderr.txt / result.txt / firewall-rule.txt /
#   probe-reply-01..22.bin (received pages, if any)

param(
    [string]$OutRoot = '',
    [int]$LocalPort = 54321,
    [int]$WaitMs = 4000
)

$ErrorActionPreference = 'Continue'

# ---- self-elevate (one UAC click) ---------------------------------------------
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $script = $MyInvocation.MyCommand.Path
    if (-not $script) { $script = 'run-f5-b-probe.ps1' }
    $argsLine = ""
    if ($OutRoot -ne '') { $argsLine += " -OutRoot `"$OutRoot`"" }
    if ($LocalPort -ne 54321) { $argsLine += " -LocalPort $LocalPort" }
    if ($WaitMs -ne 4000) { $argsLine += " -WaitMs $WaitMs" }
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = 'powershell.exe'
    $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$script`" $argsLine"
    $psi.Verb = 'runas'
    $psi.UseShellExecute = $true
    try {
        $p = [System.Diagnostics.Process]::Start($psi)
        $p.WaitForExit()
        exit $p.ExitCode
    }
    catch {
        Write-Host 'F5-B-PROBE: elevation cancelled or failed - the probe needs admin for the firewall rule.'
        exit 2
    }
}

if ($OutRoot -eq '') { $OutRoot = Join-Path ([Environment]::GetFolderPath('Desktop')) 'civlink-f5-b-probe-out' }
if (Test-Path $OutRoot) { Remove-Item -LiteralPath $OutRoot -Recurse -Force }
New-Item -ItemType Directory -Path $OutRoot | Out-Null

$script:Checks = 0
$script:Failures = @()
function Check {
    param([string]$Name, [bool]$Cond, [string]$Detail = '')
    $script:Checks++
    if ($Cond) { Write-Host ("PASS {0} : {1}" -f $script:Checks, $Name) }
    else { Write-Host ("FAIL {0} : {1} {2}" -f $script:Checks, $Name, $Detail); $script:Failures += $Name }
}

# ---- firewall rule for the fixed local port ------------------------------------
$ruleName = 'civlink-f5-b-probe'
$ruleNote = ''
try {
    # remove any leftover rule from a previous run
    Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue | Remove-NetFirewallRule
    New-NetFirewallRule -DisplayName $ruleName -Direction Inbound -Protocol UDP -LocalPort $LocalPort -Action Allow -Profile Any | Out-Null
    $ruleNote = "allow rule added for UDP $LocalPort"
}
catch {
    $ruleNote = "firewall rule FAILED: $($_.Exception.Message)"
    Write-Host "WARN: $ruleNote"
}
[IO.File]::WriteAllText((Join-Path $OutRoot 'firewall-rule.txt'), $ruleNote)

# ---- send the discovery burst from the fixed local port ------------------------
$cli = New-Object System.Net.Sockets.UdpClient
$cli.Client.Bind((New-Object System.Net.IPEndPoint([System.Net.IPAddress]::Any, $LocalPort)))
$cli.Client.ReceiveBufferSize = 1048576
$cli.EnableBroadcast = $true
$magic = [byte[]](0x8D, 0xE8, 0xFC, 0x70)
$sent = 0
for ($p = 62900; $p -le 62999; $p++) {
    $n = $cli.Send($magic, 4, ([System.Net.IPAddress]'255.255.255.255'), $p)
    if ($n -eq 4) { $sent++ }
}

# ---- wait for the reply ---------------------------------------------------------
Start-Sleep -Milliseconds $WaitMs
$pages = New-Object System.Collections.ArrayList
$recvBytes = 0
$replySrc = $null
while ($cli.Available -gt 0) {
    $ep = New-Object System.Net.IPEndPoint([System.Net.IPAddress]'0.0.0.0', 0)
    $data = $cli.Receive([ref]$ep)
    $recvBytes += $data.Length
    if ($data.Length -eq 1104) { [void]$pages.Add($data) }
    if ($null -eq $replySrc) { $replySrc = $ep.ToString() }
}
$cli.Close()

# ---- dump received pages --------------------------------------------------------
for ($i = 0; $i -lt $pages.Count; $i++) {
    [IO.File]::WriteAllBytes((Join-Path $OutRoot ('probe-reply-{0:D2}.bin' -f ($i + 1))), $pages[$i])
}

# ---- assertions ------------------------------------------------------------------
Check 'discovery burst sent (100 magic datagrams)' ($sent -eq 100) "sent=$sent"
Check 'reply received (22 pages of 1104 B)' ($pages.Count -eq 22 -and $recvBytes -eq 22 * 1104) "pages=$($pages.Count) bytes=$recvBytes"
if ($pages.Count -gt 0) {
    $head = ($pages[0][0..3] | ForEach-Object { $_.ToString('X2') }) -join ' '
    $room = [System.Text.Encoding]::ASCII.GetString($pages[0][24..45])
    Check 'first page head magic 59 60 69 9B' ($head -eq '59 60 69 9B') "head=$head"
    Check 'room name CivLink-Test-Room-2222' ($room -eq 'CivLink-Test-Room-2222') "room=$room"
}

# ---- remove the firewall rule ----------------------------------------------------
try {
    Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue | Remove-NetFirewallRule
    $ruleNote += " ; rule removed"
}
catch { $ruleNote += " ; rule removal FAILED: $($_.Exception.Message)" }
[IO.File]::WriteAllText((Join-Path $OutRoot 'firewall-rule.txt'), $ruleNote)

# ---- result ----------------------------------------------------------------------
$stamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
$result = @"
F5-B-PROBE: $(if ($script:Failures.Count -eq 0) { 'PASS' } else { 'FAIL' }) ($($script:Checks) checks)
time       : $stamp
local port : $LocalPort
burst sent : $sent magic datagrams to 255.255.255.255:62900..62999
reply      : $($pages.Count) pages / $recvBytes bytes, source $replySrc
firewall   : $ruleNote
This probe emulates exactly what a real Civ6 LAN client sends on Refresh. PASS means
PC-A's simulated host answered the cross-machine broadcast - a real Civ6 client on this
machine would show the room CivLink-Test-Room-2222. Simulated-host evidence only: NOT a
two-real-hosts multiplayer result, NOT E2-B/E3.
"@
[IO.File]::WriteAllText((Join-Path $OutRoot 'result.txt'), $result)
Write-Host ''
Write-Host ('F5-B-PROBE: ' + $(if ($script:Failures.Count -eq 0) { 'PASS' } else { 'FAIL' }) + " ($($script:Checks) checks)")
if ($script:Failures.Count -gt 0) {
    Write-Host ('FAILED: ' + ($script:Failures -join ', '))
    exit 1
}
exit 0
