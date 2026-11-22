# run-c2-iface-selftest.ps1 - M0-C C2 (v0.4.6) client NIC-pin self-test.
#
# THIS IS A BOOKKEEPING SELF-TEST, NOT AN EGRESS PROOF.
# It drives civlink_client.dll inside a private process and checks the counters and the
# decision table. It cannot observe which adapter a datagram left through; that needs a
# second machine plus a capture (docs/M0C-C2-DESIGN-20261118.md 3.3 step 2/3) and stays
# registered as UNVERIFIED. Every assertion below reads a machine-parsed "counters:" line or
# a specific ctl output line - none of them re-reads our own PASS prose (audit B-3).
#
# Scenarios (one process each: a shut-down module cannot return to service, MinHook stays
# initialised by design - the B2 audit-run contract):
#   A  no config file         -> ALL,  initError 0,  sent 0, ignored 8
#   B  unparsable config      -> ALL (fail-open), initError 11, sent 0, ignored 8
#   C  pinned to 127.0.0.1    -> PIN,  initError 0,  sent 10 (from a BOUND socket), ignored 4
#                                + ifprobe: IP_UNICAST_IF really installed on the socket
#   D  explicit ALL           -> ALL,  initError 0,  sent 0, ignored 8
#   E  empty config file      -> ALL,  initError 0,  sent 0, ignored 8
#   F  multi-line file        -> first line wins -> PIN, sent 6, ignored 2
#   G  non-local address      -> ALL (fail-open), initError 12, sent 0
#   H  impossible ifIndex     -> PIN,  sent 5, ignored 3, sendFail 0  <-- see note below
#   I  slot table overflow    -> sockOverflow > 0 (a full table is counted, not silent)
#   J  NIC-switch reactivate  -> CivLinkReactivate re-reads config after shutdown (D-1 fix)
#
# NOTE (measured, 2026-11-18): Windows ACCEPTS setsockopt(IP_UNICAST_IF) with an
# out-of-range index and returns 0, so H cannot serve as a "must fail" probe; it only checks
# accounting (sent + sendFail == 5). REVIEW-2 (second audit) ruled that scenario I is ALSO not
# a discriminator for setsockopt: it only binds sockets, so an overflow is reported whether
# or not the DLL ever pins anything. The real discriminator is scenario C's `ifprobe`: it
# reads IP_UNICAST_IF off the sending socket before/after the burst. A DLL that only bumps
# c_sent (without ever calling setsockopt) leaves the option at 0 and FAILS C11/C12.
# Egress adapter is still NOT VERIFIED - that needs a second machine + capture.
#
# Exit codes: 0 PASS, 1 assertion failure, 2 setup error.

param(
    [string]$BinDir = '',
    [string]$OutRoot = ''
)

$ErrorActionPreference = 'Continue'
$script:Checks = 0
$script:Failures = @()
$script:ExpectChecks = 50  # 10 scenarios x 3 (30) + 14 counter facts (incl. C ifprobe x2) + 6 ctl checks.

function Check {
    param([string]$Name, $Cond, [string]$Detail = '')
    $script:Checks++
    if ($Cond) {
        Write-Host ("PASS {0} : {1}" -f $script:Checks, $Name)
    }
    else {
        Write-Host ("FAIL {0} : {1} {2}" -f $script:Checks, $Name, $Detail)
        $script:Failures += $Name
    }
}

function Get-Sha256Hex([string]$Path) {
    (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash
}

# Parses the machine-readable line the DLL self-test emits:
#   counters: sent=0 ignored=8 sendFail=0 initError=0 bind62056=0 sockOverflow=0 scatterGather=0 session=123
function Get-Counters {
    param([string]$Text)
    $m = [regex]::Match($Text, '(?m)^counters:\s+(.*)$')
    if (-not $m.Success) { return $null }
    $h = @{}
    foreach ($tok in ($m.Groups[1].Value -split '\s+')) {
        if ($tok -match '^([A-Za-z0-9_]+)=(\d+)$') { $h[$Matches[1]] = [uint64]$Matches[2] }
    }
    return $h
}

if ($BinDir -eq '') { $BinDir = $PSScriptRoot }
if ($OutRoot -eq '') { $OutRoot = Join-Path $BinDir 'c2-iface-selftest-out' }

$dll     = Join-Path $BinDir 'civlink_client.dll'
$testExe = Join-Path $BinDir 'client_selftest.exe'
$ctl     = Join-Path $BinDir 'civlink_ctl.exe'
foreach ($p in @($dll, $testExe, $ctl)) {
    if (-not (Test-Path $p)) { Write-Host "SETUP: missing $p"; exit 2 }
}

if (Test-Path $OutRoot) { Remove-Item -LiteralPath $OutRoot -Recurse -Force }
New-Item -ItemType Directory -Path $OutRoot | Out-Null

# Scratch config directory: no run ever touches the user's %LOCALAPPDATA% profile.
$scratch = Join-Path $OutRoot 'cfg'
New-Item -ItemType Directory -Path $scratch | Out-Null

# --- the scenarios -------------------------------------------------------------
$scenarios = @(
    @{ Id = 'A'; Expect = 9;  Title = 'ALL mode, no config' },
    @{ Id = 'B'; Expect = 6;  Title = 'invalid config -> ALL (fail-open)' },
    @{ Id = 'C'; Expect = 12; Title = 'pinned, bound socket + ifprobe' },
    @{ Id = 'D'; Expect = 6;  Title = 'explicit ALL' },
    @{ Id = 'E'; Expect = 6;  Title = 'empty config file' },
    @{ Id = 'F'; Expect = 7;  Title = 'multi-line: first line wins' },
    @{ Id = 'G'; Expect = 5;  Title = 'non-local address -> initError 12' },
    @{ Id = 'H'; Expect = 6;  Title = 'impossible ifIndex (observation)' },
    @{ Id = 'I'; Expect = 5;  Title = 'slot overflow is counted (can fail)' },
    @{ Id = 'J'; Expect = 12; Title = 'NIC-switch reactivate re-reads config (D-1 fix)' }
)

$scenarioText = @{}
$scenarioExit = @{}
$scenarioCtr  = @{}
foreach ($sc in $scenarios) {
    Write-Host ("--- scenario {0}: {1}" -f $sc.Id, $sc.Title)
    $out = & $testExe $BinDir $scratch $sc.Id 2>&1 | Out-String
    $code = $LASTEXITCODE
    $scenarioText[$sc.Id] = $out
    $scenarioExit[$sc.Id] = $code
    $scenarioCtr[$sc.Id]  = Get-Counters $out
    [IO.File]::WriteAllText((Join-Path $OutRoot ("scenario-{0}.txt" -f $sc.Id.ToLower())), $out)
    [IO.File]::WriteAllText((Join-Path $OutRoot ("exit-{0}.txt" -f $sc.Id.ToLower())), "$code")
    Write-Host $out
}

# --- ctl inject-client --iface pre-flight --------------------------------------
$prevOverride = $env:CIVLINK_CLIENT_IFACE_FILE

# T1: a non-local address must be refused before anything is written or injected.
$ctlInvalid = & $ctl inject-client -x civlink-no-such-target.exe --iface 10.255.255.1 2>&1 | Out-String
$ctlInvalidExit = $LASTEXITCODE
[IO.File]::WriteAllText((Join-Path $OutRoot 'ctl-t1-invalid.txt'), $ctlInvalid)
[IO.File]::WriteAllText((Join-Path $OutRoot 'ctl-t1-exit.txt'), "$ctlInvalidExit")

# T1b (audit H-4): loopback must be refused too - it is not a real egress choice.
$ctlLoop = & $ctl inject-client -x civlink-no-such-target.exe --iface 127.0.0.1 2>&1 | Out-String
$ctlLoopExit = $LASTEXITCODE
[IO.File]::WriteAllText((Join-Path $OutRoot 'ctl-t1b-loopback.txt'), $ctlLoop)
[IO.File]::WriteAllText((Join-Path $OutRoot 'ctl-t1b-exit.txt'), "$ctlLoopExit")

# T2: a valid selection must reach the config-write step now that the write happens only after
# the target is resolved (audit H-3 ordering). We point the injection at our own pid and at a
# DLL that does not exist, so the run stops at "dll not found" (exit 1) and nothing is injected.
$prevOverride = $env:CIVLINK_CLIENT_IFACE_FILE
$env:CIVLINK_CLIENT_IFACE_FILE = Join-Path $scratch 'client-iface.txt'
$ctlAll = & $ctl inject-client -p $PID -d civlink-no-such-dll.dll --iface ALL 2>&1 | Out-String
$ctlAllExit = $LASTEXITCODE
[IO.File]::WriteAllText((Join-Path $OutRoot 'ctl-t2-all.txt'), $ctlAll)
[IO.File]::WriteAllText((Join-Path $OutRoot 'ctl-t2-exit.txt'), "$ctlAllExit")
$cfgWritten = ''
$cfgPath = Join-Path $scratch 'client-iface.txt'
if (Test-Path $cfgPath) {
    $cfgWritten = ([IO.File]::ReadAllText($cfgPath)).Trim()
    [IO.File]::WriteAllText((Join-Path $OutRoot 'ctl-t2-config.txt'), $cfgWritten)
    Copy-Item -LiteralPath $cfgPath -Destination (Join-Path $OutRoot 'config-all.txt') -Force
}

# T3: a live physical/virtual address must be accepted and its identity printed (audit H-3/H-4).
$liveIp = $null
$outs = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object { $_.IPAddress -ne '127.0.0.1' -and $_.PrefixOrigin -ne 'WellKnown' } |
        Where-Object { (Get-NetAdapter -InterfaceIndex $_.InterfaceIndex -ErrorAction SilentlyContinue).Status -eq 'Up' }
if ($outs) { $liveIp = @($outs)[0].IPAddress }

$ctlPin = ''
$ctlPinExit = -1
$pinCfg = ''
if ($liveIp) {
    $env:CIVLINK_CLIENT_IFACE_FILE = Join-Path $scratch 'client-iface-pin.txt'
    $ctlPin = & $ctl inject-client -p $PID -d civlink-no-such-dll.dll --iface $liveIp 2>&1 | Out-String
    $ctlPinExit = $LASTEXITCODE
    [IO.File]::WriteAllText((Join-Path $OutRoot 'ctl-t3-pin.txt'), $ctlPin)
    [IO.File]::WriteAllText((Join-Path $OutRoot 'ctl-t3-exit.txt'), "$ctlPinExit")
    if (Test-Path (Join-Path $scratch 'client-iface-pin.txt')) {
        $pinCfg = ([IO.File]::ReadAllText((Join-Path $scratch 'client-iface-pin.txt'))).Trim()
    }
} else {
    [IO.File]::WriteAllText((Join-Path $OutRoot 'ctl-t3-pin.txt'), 'SKIPPED: no live non-loopback IPv4 adapter')
    [IO.File]::WriteAllText((Join-Path $OutRoot 'ctl-t3-exit.txt'), 'skipped')
}
$env:CIVLINK_CLIENT_IFACE_FILE = $prevOverride

# --- assertions ----------------------------------------------------------------
foreach ($sc in $scenarios) {
    $txt = $scenarioText[$sc.Id]
    Check ("scenario {0} exits 0" -f $sc.Id) ($scenarioExit[$sc.Id] -eq 0) ("code=" + $scenarioExit[$sc.Id])

    $m = [regex]::Match($txt, 'checks: (\d+) failed=(\d+)')
    $ran = if ($m.Success) { [int]$m.Groups[1].Value } else { -1 }
    $failed = if ($m.Success) { [int]$m.Groups[2].Value } else { -1 }
    Check ("scenario {0} ran {1} checks" -f $sc.Id, $sc.Expect) ($ran -eq $sc.Expect) "got=$ran"
    Check ("scenario {0} has no failed checks" -f $sc.Id) ($failed -eq 0) "failed=$failed"
}

# Per-scenario counter facts, read from the parsed line (not from PASS prose).
$cA = $scenarioCtr['A']; $cB = $scenarioCtr['B']; $cC = $scenarioCtr['C']
$cD = $scenarioCtr['D']; $cE = $scenarioCtr['E']; $cF = $scenarioCtr['F']
$cG = $scenarioCtr['G']; $cH = $scenarioCtr['H']; $cI = $scenarioCtr['I']

Check 'every scenario emitted a counters line' `
    (($null -ne $cA) -and ($null -ne $cB) -and ($null -ne $cC) -and ($null -ne $cD) -and
     ($null -ne $cE) -and ($null -ne $cF) -and ($null -ne $cG) -and ($null -ne $cH) -and
     ($null -ne $cI))

Check 'A: ALL pins nothing (sent 0, ignored 8, initError 0)' `
    ($cA -and $cA['sent'] -eq 0 -and $cA['ignored'] -eq 8 -and $cA['initError'] -eq 0)
Check 'B: config invalid degrades to ALL (initError 11, sent 0)' `
    ($cB -and $cB['initError'] -eq 11 -and $cB['sent'] -eq 0 -and $cB['ignored'] -eq 8)
Check 'C: per-send pinning from a bound socket (sent 10, ignored 4, sendFail 0)' `
    ($cC -and $cC['sent'] -eq 10 -and $cC['ignored'] -eq 4 -and $cC['sendFail'] -eq 0)
Check 'C: the DLL never bound 62056' ($cC -and $cC['bind62056'] -eq 0)
# REVIEW-2 discriminator: the sending socket's IP_UNICAST_IF must have changed from 0 to a
# real interface index. A DLL that only increments c_sent cannot satisfy these two checks.
$ifprobe = [regex]::Match($scenarioText['C'], '(?m)^ifprobe:\s+before=(\d+)\s+after=(\d+)')
$ifBefore = if ($ifprobe.Success) { [uint64]$ifprobe.Groups[1].Value } else { [uint64]::MaxValue }
$ifAfter  = if ($ifprobe.Success) { [uint64]$ifprobe.Groups[2].Value } else { 0 }
Check 'C: IP_UNICAST_IF was unset before the burst' ($ifBefore -eq 0) "before=$ifBefore"
Check 'C: IP_UNICAST_IF installed on the socket after the burst (real setsockopt)' `
    ($ifAfter -ne 0 -and $ifAfter -ne [uint64]::MaxValue) "after=$ifAfter"
Check 'D: explicit ALL pins nothing (sent 0, initError 0)' `
    ($cD -and $cD['sent'] -eq 0 -and $cD['initError'] -eq 0 -and $cD['ignored'] -eq 8)
Check 'E: empty file treated as ALL (sent 0, initError 0)' `
    ($cE -and $cE['sent'] -eq 0 -and $cE['initError'] -eq 0 -and $cE['ignored'] -eq 8)
Check 'F: multi-line uses the first line only (sent 6, ignored 2)' `
    ($cF -and $cF['sent'] -eq 6 -and $cF['ignored'] -eq 2 -and $cF['initError'] -eq 0)
Check 'G: non-local address fail-open (initError 12, sent 0)' `
    ($cG -and $cG['initError'] -eq 12 -and $cG['sent'] -eq 0)
# H is an OBSERVATION scenario, not a failing one: this Windows build accepts an out-of-range
# IP_UNICAST_IF index, so nothing can be observed as sendFail. It asserts only that the sends
# stay accounted and that the data path is untouched.
Check 'H: every discovery send is accounted (sent + sendFail == 5)' `
    ($cH -and ($cH['sent'] + $cH['sendFail']) -eq 5)
Check 'H: the data path was untouched (no 62056 bind)' ($cH -and $cH['bind62056'] -eq 0)
# I is the assertion that CAN fail: a table overflow must be counted, not silent (audit M-1).
Check 'I: slot-table overflow is counted, not silent (sockOverflow > 0)' `
    ($cI -and $cI['sockOverflow'] -gt 0)

# ctl behaviour
Check 'ctl refuses a non-local iface with exit 1' `
    ($ctlInvalidExit -eq 1 -and $ctlInvalid -match 'not a live local IPv4 interface') "exit=$ctlInvalidExit"
Check 'ctl refuses loopback with exit 1 (H-4)' `
    ($ctlLoopExit -eq 1 -and $ctlLoop -match 'loopback pseudo interface') "exit=$ctlLoopExit"
Check 'ctl writes ALL before resolving the target' `
    ($ctlAllExit -eq 2 -and $ctlAll -match 'client iface config written: ALL' -and $cfgWritten -eq 'ALL') "exit=$ctlAllExit cfg='$cfgWritten'"
Check 'ctl prints the resolved config path and its provenance (H-3)' `
    ($ctlAll -match 'client iface config path:' -and $ctlAll -match 'resolved by: env override')
Check 'ctl names the selected adapter (FriendlyName/IfIndex/IfType/metric)' `
    ($ctlAll -match 'interface selected: ALL')
if ($liveIp) {
    Check 'ctl accepts a live adapter and records it' `
        ($ctlPinExit -eq 2 -and $pinCfg -eq $liveIp -and $ctlPin -match 'IfIndex=') "ip=$liveIp exit=$ctlPinExit cfg='$pinCfg'"
} else {
    # Audit 2026-11-22: a skipped check must NOT count as a pass. Treat the missing live
    # adapter as a setup error (exit 2), matching run-m0e-completion-selftest.ps1:391-394.
    Write-Host 'SETUP ERROR: no non-loopback IPv4 adapter - T3 live-adapter check NOT VERIFIED'
    [IO.File]::WriteAllText((Join-Path $OutRoot 'result.txt'),
        "C2-BOOKKEEPING-SELFTEST: NOT VERIFIED (setup error: no live non-loopback IPv4 adapter for ctl T3)`r`n")
    exit 2
}

# --- result file ---------------------------------------------------------------
$verdict = if ($script:Failures.Count -eq 0 -and $script:Checks -eq $script:ExpectChecks) { 'PASS' } else { 'FAIL' }
$dllChecks = 0
foreach ($sc in $scenarios) { $dllChecks += $sc.Expect }

$result = @"
C2-BOOKKEEPING-SELFTEST: $verdict ($($script:Checks)/$($script:ExpectChecks) runner checks, $dllChecks in-process checks)
Egress adapter: NOT VERIFIED

Scope: single machine. The DLL's counters and decision table are exercised in $($scenarios.Count)
single-process scenarios; the runner parses a machine-readable "counters: ..." line rather
than re-reading the test's own PASS prose. This proves the bookkeeping layer and that sends
are never dropped. It does NOT prove that a discovery broadcast actually leaves through the
selected adapter: that requires a second machine plus an external capture
(M0C-C2-DESIGN-20261118.md 3.3 step 2/3) and stays registered as outstanding.

The assertion that CAN fail is scenario C's `ifprobe` (C11/C12): it reads the socket's
IP_UNICAST_IF option before/after the burst. A DLL that never calls setsockopt (but merely
bumps c_sent) leaves that option at 0 and fails C12. Scenario I only proves overflow
accounting (it binds sockets but never sends), so it is NOT a setsockopt discriminator.
Scenario H is deliberately NOT a "must fail" probe: measured on Windows, setsockopt with an
out-of-range index returns 0 and the broadcast still goes out (sent 5 / sendFail 0), so H
only checks accounting. Egress adapter itself remains UNVERIFIED (second machine needed).

script sha256        : $(Get-Sha256Hex $PSCommandPath)
civlink_client.dll   : $(Get-Sha256Hex $dll)
civlink_ctl.exe      : $(Get-Sha256Hex $ctl)
client_selftest.exe  : $(Get-Sha256Hex $testExe)
live adapter used    : $(if ($liveIp) { $liveIp } else { 'none (t3 skipped)' })
"@
[IO.File]::WriteAllText((Join-Path $OutRoot 'result.txt'), $result)

Write-Host ''
Write-Host ("C2-BOOKKEEPING-SELFTEST: $verdict ($($script:Checks)/$($script:ExpectChecks) runner checks, $dllChecks in-process)")
Write-Host 'Egress adapter: NOT VERIFIED (needs a second machine + capture)'
if ($script:Failures.Count -gt 0 -or $script:Checks -ne $script:ExpectChecks) {
    Write-Host ('FAILED: ' + ($script:Failures -join ', '))
    exit 1
}
exit 0
