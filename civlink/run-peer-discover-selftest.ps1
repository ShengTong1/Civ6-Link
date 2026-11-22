# M0-G peer-discover selftest (single-instance, mechanical)
# Runs the agent's built-in core selftest, then 5 source mutations against it.
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File run-peer-discover-selftest.ps1 [-OutDir <dir>]
param([string]$OutDir = '')

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.Encoding]::UTF8

$repo   = Split-Path -Parent $MyInvocation.MyCommand.Path   # civlink\
$agentD = Join-Path $repo 'agent'
$exe    = Join-Path $agentD 'target\release\civlink-agent-pd.exe'
$srcCore= Join-Path $agentD 'src\peer_discover_core.rs'
$srcNet = Join-Path $agentD 'src\peer_discover_net.rs'

if(-not (Test-Path $exe -PathType Leaf)){ Write-Host "FATAL agent-pd exe missing: $exe"; exit 3 }
if(-not (Test-Path $srcCore) -or -not (Test-Path $srcNet)){ Write-Host "FATAL source files missing"; exit 3 }

# The baseline must run the SAME binary the mutations use. A stale civlink-agent-pd.exe once
# produced a bogus baseline failure (it was a leftover mutated build), so refresh it here.
Copy-Item (Join-Path $agentD 'target\release\civlink-agent.exe') $exe -Force

if($OutDir -eq ''){ $OutDir = Join-Path $env:TEMP ("pd-selftest-" + (Get-Date -Format 'HHmmss')) }
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$script:Fails = 0
$script:Checks = 0
function Check([string]$id, [bool]$ok){ $script:Checks++; if($ok){ Write-Host "PASS $id" } else { Write-Host "FAIL $id"; $script:Fails++ } }

# ---------- baseline: built-in core selftest ----------
$env:CIVLINK_PD_DEBUG = ''
$st = & $exe --peer-discover-selftest 2>&1 | Out-String
$st | Set-Content (Join-Path $OutDir 'selftest-baseline.txt')
# Audit 2026-11-22: exact-count assertion (31) was stale after legit checks were added.
# Assert failed=0 with a floor, so adding a check no longer turns a green harness red.
$bm = [regex]::Match($st, 'checks=(\d+) failed=(\d+)')
$baseN = if ($bm.Success) { [int]$bm.Groups[1].Value } else { 0 }
Check "baseline core selftest passed" ($bm.Success -and $bm.Groups[2].Value -eq '0' -and $baseN -ge 36)

# ---------- helper to build + run core selftest with mutated source ----------
function Mutated-Selftest([string]$id, [scriptblock]$mutate){
    Copy-Item $srcCore "$srcCore.bak" -Force
    Copy-Item $srcNet  "$srcNet.bak"  -Force
    # Audit 2026-11-22: capture pre-mutation bytes so a no-op .Replace (expired pattern)
    # can never be counted as "mutation caught" (silent-pass family, cf. fakeip fail-closed).
    $coreBefore = [IO.File]::ReadAllBytes($srcCore)
    $netBefore  = [IO.File]::ReadAllBytes($srcNet)
    try {
        & $mutate
        $coreAfter = [IO.File]::ReadAllBytes($srcCore)
        $netAfter  = [IO.File]::ReadAllBytes($srcNet)
        $applied = -not ([Convert]::ToBase64String($coreBefore) -eq [Convert]::ToBase64String($coreAfter) -and
                         [Convert]::ToBase64String($netBefore)  -eq [Convert]::ToBase64String($netAfter))
        if (-not $applied) { Check "mut-$id applied" $false 'source unchanged'; return }
        & cmd /c "cd /d `"$agentD`" && cargo +1.75.0 build --offline --release --features peer-discover > mut.log 2>&1"
        if($LASTEXITCODE -ne 0){ Check "mut-$id build failed (unexpected)" $false; return }
        Copy-Item (Join-Path $agentD 'target\release\civlink-agent.exe') $exe -Force
        $out = & $exe --peer-discover-selftest 2>&1 | Out-String
        $out | Set-Content (Join-Path $OutDir "mut-$id.txt")
        # the mutation MUST be caught: selftest must report failures
        Check "mut-$id caught by selftest" ($out -match 'failed=[1-9]')
    } finally {
        Copy-Item "$srcCore.bak" $srcCore -Force
        Copy-Item "$srcNet.bak"  $srcNet  -Force
        Remove-Item "$srcCore.bak","$srcNet.bak" -Force -ErrorAction SilentlyContinue
        # Copy-Item preserves the .bak mtime, which can be OLDER than the mutated build artefact:
        # cargo then considers the cached (mutated) build "fresh" and keeps it. Touch the restored
        # sources so the restore rebuild actually recompiles them.
        (Get-Item $srcCore).LastWriteTime = Get-Date
        (Get-Item $srcNet).LastWriteTime  = Get-Date
        & cmd /c "cd /d `"$agentD`" && cargo +1.75.0 build --offline --release --features peer-discover > restore.log 2>&1"
        Copy-Item (Join-Path $agentD 'target\release\civlink-agent.exe') $exe -Force
    }
}

# ---------- M1: N1 RTT formula (perturb the PRODUCTION result, not the test's expected constant) ----------
# Audit 2026-11-22: the old pattern replaced '130_000_000', which only appears in a comment and
# the selftest assertion -> it corrupted the test, producing a false "mutation caught". Now mutate
# rtt_ns() itself (+20 ms); the rtt-130ms check must then fail for the right reason.
Mutated-Selftest 'n1-rtt-formula' {
    $c = [IO.File]::ReadAllText($srcCore)
    $c = $c.Replace('Some(rtt as u64)', 'Some(rtt as u64 + 20_000_000)')
    [IO.File]::WriteAllText($srcCore, $c, (New-Object Text.UTF8Encoding($false)))
}

# ---------- M2: response magic (CLPR -> CLPD) ----------
Mutated-Selftest 'resp-magic' {
    $c = [IO.File]::ReadAllText($srcCore)
    $c = $c.Replace("b[0..4].copy_from_slice(magic);", "b[0..4].copy_from_slice(DISC_MAGIC);")
    [IO.File]::WriteAllText($srcCore, $c, (New-Object Text.UTF8Encoding($false)))
}

# ---------- M3: RTT clock-domain (skip reflector-dwell correction) ----------
Mutated-Selftest 'rtt-clock-domain' {
    $c = [IO.File]::ReadAllText($srcCore)
    $c = $c.Replace('let reflect = t3 as i128 - t2 as i128;', 'let reflect = 0 as i128;')
    [IO.File]::WriteAllText($srcCore, $c, (New-Object Text.UTF8Encoding($false)))
}

# ---------- M4: VPN keyword filter (drop the keyword list so only 26.x stays filtered) ----------
Mutated-Selftest 'vpn-filter' {
    $c = [IO.File]::ReadAllText($srcCore)
    $c = $c.Replace('if KW.iter().any(|k| hay.contains(k)) || ip[0] == 26 {', 'if ip[0] == 26 {')
    [IO.File]::WriteAllText($srcCore, $c, (New-Object Text.UTF8Encoding($false)))
}

# ---------- M5: loss computation (treat every gap as received -> loss always 0) ----------
# Audit 2026-11-22: signature is (sent: u64) after the 2026-11-22 denominator fix; the old
# max_seq:u16 pattern matched nothing, so the mutation never applied.
Mutated-Selftest 'loss-judgement' {
    $c = [IO.File]::ReadAllText($srcCore)
    $c = $c.Replace('pub fn loss_x100(&self, sent: u64) -> u64 {', 'pub fn loss_x100(&self, sent: u64) -> u64 { return 0;')
    [IO.File]::WriteAllText($srcCore, $c, (New-Object Text.UTF8Encoding($false)))
}

# ---------- verdict ----------
$verdict = "PD-SELFTEST: {0} checks, {1} failed, evidence in {2}" -f $script:Checks, $script:Fails, $OutDir
$verdict | Set-Content (Join-Path $OutDir 'verdict.txt')
Write-Host $verdict
if($script:Fails -gt 0){ exit 1 }
Write-Host "PD-SELFTEST: PASS - all mutations caught by core selftest"
exit 0
