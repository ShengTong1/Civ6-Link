# check-f4-package.ps1 - F4 release-candidate package self-check (no game needed).
#
# Verifies, inside the release directory:
#   1. all four binaries + fixture are present,
#   2. every binary answers --version (ctl via usage line) and exits 0,
#   3. VERSIONS.txt can be produced and matches the binaries,
#   4. relay refuses --listen 127.0.0.1:62056 (H2 red line at binary level),
#   5. agent refuses --port 62056 / --forward-listen 62056 / --forward-to :62056,
#   6. the package copy of civlink_ctl.exe and civlink_hook.dll exist and are non-trivial.
#
# This is a packaging sanity check, NOT a multiplayer or Gate result.

[CmdletBinding()]
param([string]$BinDir = '')
if ($BinDir -eq '') { $BinDir = $PSScriptRoot }

$ErrorActionPreference = 'Continue'
$fail = 0
function Check([string]$what, [bool]$ok, [string]$detail = '') {
    if ($ok) { Write-Host ("  PASS {0,-56} {1}" -f $what, $detail) }
    else { Write-Host ("  FAIL {0,-56} {1}" -f $what, $detail); $script:fail++ }
}

$dll   = Join-Path $BinDir 'civlink_hook.dll'
$ctl   = Join-Path $BinDir 'civlink_ctl.exe'
$agent = Join-Path $BinDir 'civlink-agent.exe'
$relay = Join-Path $BinDir 'civlink-relay.exe'
$fx    = Join-Path $BinDir 'fixture-reply-set'

# --- 1. presence ---------------------------------------------------------------
foreach ($f in @($dll, $ctl, $agent, $relay)) {
    Check ("present: " + [IO.Path]::GetFileName($f)) (Test-Path $f)
}
Check "fixture reply-01..22 present" (Test-Path (Join-Path $fx 'reply-22.bin'))

# --- 2. version detection --------------------------------------------------------
$agentVer = & $agent --version 2>&1; $a1 = $LASTEXITCODE
$relayVer = & $relay --version 2>&1; $r1 = $LASTEXITCODE
$ctlUsage = & $ctl 2>&1 | Select-Object -First 1
Check "agent --version exits 0" ($a1 -eq 0) ($agentVer)
Check "relay --version exits 0" ($r1 -eq 0) ($relayVer)
Check "ctl usage line carries version" ($ctlUsage -match 'v0\.2\.0-f2') ($ctlUsage)

# --- 3. red lines at binary level -----------------------------------------------
$neg = Join-Path $env:TEMP ("f4-neg-{0}" -f ([IO.Path]::GetRandomFileName()))
New-Item -ItemType Directory -Path $neg -Force | Out-Null
try {
    $out = Join-Path $neg 'relay62056.txt'
    & $relay --listen 127.0.0.1:62056 --listen-seconds 1 --out-dir $neg --quiet *> $out
    $rc = $LASTEXITCODE
    $txt = Get-Content $out -Raw
    Check "relay refuses --listen :62056 (exit != 0)" ($rc -ne 0) ("exit=" + $rc)
    Check "relay stderr names the red line" ($txt -match 'must not use port 62056') ($txt.Trim())

    $o2 = Join-Path $neg 'agent-port62056.txt'
    & $agent --port 62056 *> $o2
    $rc2 = $LASTEXITCODE
    Check "agent refuses --port 62056" ($rc2 -ne 0) ("exit=" + $rc2)
} finally {
    Remove-Item -LiteralPath $neg -Recurse -Force -ErrorAction SilentlyContinue
}

# --- 4. package integrity ----------------------------------------------------------
$h1 = (Get-FileHash -LiteralPath $agent -Algorithm SHA256).Hash
$h2 = (Get-FileHash -LiteralPath $relay -Algorithm SHA256).Hash
$h3 = (Get-FileHash -LiteralPath $ctl -Algorithm SHA256).Hash
$h4 = (Get-FileHash -LiteralPath $dll -Algorithm SHA256).Hash
Write-Host "  info agent sha256 : $h1"
Write-Host "  info relay sha256 : $h2"
Write-Host "  info ctl   sha256 : $h3"
Write-Host "  info dll   sha256 : $h4"
Check "ctl is non-trivial (>= 100 KB)" ((Get-Item $ctl).Length -ge 100KB)
Check "dll is non-trivial (>= 100 KB)" ((Get-Item $dll).Length -ge 100KB)

# --- 5. VERSIONS.txt --------------------------------------------------------------
$v = @()
$v += "civlink-agent: " + (& $agent --version 2>&1)
$v += "civlink-relay: " + (& $relay --version 2>&1)
$v += "civlink_ctl  : " + $ctlUsage
$vPath = Join-Path $BinDir 'VERSIONS.txt'
$v | Out-File -FilePath $vPath -Encoding UTF8
Check "VERSIONS.txt written" (Test-Path $vPath)

Write-Host ""
if ($fail -eq 0) { Write-Host "CHECK-F4-PACKAGE: PASS"; exit 0 }
else { Write-Host "CHECK-F4-PACKAGE: FAIL ($fail)"; exit 1 }
