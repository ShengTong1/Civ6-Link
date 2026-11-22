# run-fakeip-selftest.ps1 - F2 S3 mechanical verification driver for civlink-fakeip.
#
#  1. Runs the real test suite on the pristine crate and asserts 17/17 pass.
#  2. Applies a set of semantic mutations to src/lib.rs one at a time; for each,
#     asserts that at least one test FAILS (the mutation is caught). Restores the
#     pristine file afterwards.
#
# Exit codes: 0 = ALL PASS (pristine 17/17 + every mutation caught), 1 = any
# pristine failure, 2 = any mutation was NOT caught, 3 = file not found.
#
# Requirements: cargo +1.75.0 in PATH (offline build, no network).
# Run from a neutral directory copy if the project tree is Low-IL; the crate
# itself only compiles/links locally, so the project tree is normally fine.

$ErrorActionPreference = 'Continue'
$crateDir = Join-Path $PSScriptRoot 'fakeip'
$libPath  = Join-Path $crateDir 'src\lib.rs'

if (-not (Test-Path $libPath)) {
    Write-Host "[!] missing $libPath" -ForegroundColor Red
    exit 3
}

function Run-TestSuite {
    param([string]$Label)
    $lines = @(& cargo +1.75.0 test --offline --manifest-path (Join-Path $crateDir 'Cargo.toml') 2>&1 | ForEach-Object { $_.ToString() })
    $exit = $LASTEXITCODE
    $text = $lines -join "`n"
    $passed = '0'; $failed = '0'
    # cargo exits 101 when tests FAIL, and the result line reads "test result: FAILED. N passed; M failed"
    if ($text -match 'test result: (?:ok|FAILED)\. (\d+) passed') { $passed = $Matches[1] }
    if ($text -match 'test result: (?:ok|FAILED)\. \d+ passed; (\d+) failed') { $failed = $Matches[1] }
    Write-Host "[$Label] exit=$exit passed=$passed failed=$failed"
    return [pscustomobject]@{ Exit = $exit; Passed = [int]$passed; Failed = [int]$failed }
}

# --- pristine run ---------------------------------------------------------
$orig = [IO.File]::ReadAllText($libPath, [Text.Encoding]::UTF8)
$pristine = Run-TestSuite 'pristine'
if ($pristine.Exit -ne 0 -or $pristine.Failed -ne 0 -or $pristine.Passed -ne 17) {
    Write-Host "[!] pristine suite not 17/17 (exit=$($pristine.Exit) passed=$($pristine.Passed) failed=$($pristine.Failed))" -ForegroundColor Red
    exit 1
}

# --- mutations ------------------------------------------------------------
# Each mutation: { name, old, new } - semantic break that one test must catch.
$mutations = @(
    @{ name = 'm01-pool-pop-order';        old = 'inner.pool.pop_front()';           new = 'inner.pool.pop_back()' },
    @{ name = 'm02-keyexists-skipped';     old = 'if inner.forward.contains_key(&key) {'; new = 'if false {' },
    @{ name = 'm03-fakeinuse-skipped';     old = 'if let Some((other_key, _)) = inner.forward.iter().find(|(k, _)| k.fake == fake) {'; new = 'if let Some((other_key, _)) = None::<(MappingKey, ())>.iter().find(|_| false) {' },
    @{ name = 'm04-reverseconflict-skipped'; old = 'if let Some(existing_key) = inner.reverse.get(&reverse_key) {'; new = 'if let Some(existing_key) = inner.reverse.get(&(u32::MAX, u64::MAX, u16::MAX)) {' },
    @{ name = 'm05-touch-skipped';         old = 'entry.last_seen = now;';            new = 'let _ = now;' },
    @{ name = 'm06-ttl-inflated';          old = 'now.saturating_sub(e.last_seen) >= DISCOVERY_TTL_TICKS'; new = 'now.saturating_sub(e.last_seen) >= DISCOVERY_TTL_TICKS * 1000' },
    @{ name = 'm07-release-keeps-forward'; old = 'let entry = inner.forward.remove(key).expect("key present");'; new = 'let entry = inner.forward.remove(&MappingKey { session_id: u64::MAX, logical_socket_id: key.logical_socket_id, socket_generation: key.socket_generation, fake: key.fake }).expect("key present");' }
)

$allCaught = $true
foreach ($m in $mutations) {
    $mutated = $orig.Replace($m.old, $m.new)
    if ($mutated -eq $orig) {
        Write-Host "[!!] mutation '$($m.name)': pattern not found, SKIPPED - cannot claim discrimination" -ForegroundColor Red
        $allCaught = $false
        continue
    }
    [IO.File]::WriteAllText($libPath, $mutated, [Text.Encoding]::UTF8)
    $r = Run-TestSuite $m.name
    # cargo exits 101 when tests fail; any failing test proves the mutation was caught
    if ($r.Failed -ge 1) {
        Write-Host "  [ok] mutation caught by $($r.Failed) failing test(s)"
    } else {
        Write-Host "  [!!] mutation NOT caught (exit=$($r.Exit) failed=$($r.Failed))" -ForegroundColor Red
        $allCaught = $false
    }
}

# --- restore ---------------------------------------------------------------
[IO.File]::WriteAllText($libPath, $orig, [Text.Encoding]::UTF8)
$restored = Run-TestSuite 'restored'
if ($restored.Exit -ne 0 -or $restored.Passed -ne 17) {
    Write-Host "[!] restore check failed (exit=$($restored.Exit) passed=$($restored.Passed))" -ForegroundColor Red
    exit 1
}

if ($allCaught) {
    Write-Host "FAKEIP-SELFTEST: PASS (pristine 17/17 + $($mutations.Count) mutations caught, file restored)"
    exit 0
} else {
    Write-Host "FAKEIP-SELFTEST: FAIL (at least one mutation not caught)" -ForegroundColor Red
    exit 2
}
