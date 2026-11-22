# run-m0e-mutation.ps1
#
# Mutation test for the M0-E completion self-test: each mutation must make the
# self-test FAIL, and the failure must land on the check that mutation targets.
# Without this, "27/27 PASS" proves only that the script runs, not that it can
# tell a working completion path from a broken one.
#
# The source file and the built exe are restored byte-for-byte afterwards; the
# script verifies that at the end (source sha256 == the backup's).
#
# Exit codes: 0 = every mutation was caught as expected, 1 = a mutation slipped
# through (the self-test lacks discriminating power), 2 = setup problem.

[CmdletBinding()]
param(
    [string]$OutRoot = ''
)

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$src = Join-Path $here 'agent\src\main.rs'
$exe = Join-Path $here 'civlink-agent.exe'
$rel = Join-Path $here 'agent\target\release\civlink-agent.exe'
$selftest = Join-Path $here 'run-m0e-completion-selftest.ps1'

foreach ($p in @($src, $exe, $selftest)) {
    if (-not (Test-Path $p)) { Write-Host "[!] missing $p"; exit 2 }
}

if ([string]::IsNullOrWhiteSpace($OutRoot)) {
    $stamp = (Get-Date).ToString('yyyyMMdd-HHmmss')
    $OutRoot = Join-Path (Join-Path (Split-Path -Parent $here) 'M0A\captures') "M0E-mutation-$stamp"
}
New-Item -ItemType Directory -Force -Path $OutRoot | Out-Null
$backupDir = Join-Path $OutRoot 'backup'
New-Item -ItemType Directory -Force -Path $backupDir | Out-Null

$srcHash0 = (Get-FileHash $src -Algorithm SHA256).Hash
$exeHash0 = (Get-FileHash $exe -Algorithm SHA256).Hash
Copy-Item $src (Join-Path $backupDir 'main.rs') -Force
Copy-Item $exe (Join-Path $backupDir 'civlink-agent.exe') -Force
Write-Host "=== M0-E mutation test ==="
Write-Host "  source sha256 (pristine): $srcHash0"
Write-Host "  evidence               : $OutRoot"
Write-Host ""

$env:PATH = "D:\cargo\bin;$env:PATH"
$agentDir = Join-Path $here 'agent'

function Build-Agent {
    # cargo writes progress to stderr; with $ErrorActionPreference='Stop' PowerShell turns
    # that into a terminating NativeCommandError. Route both streams through cmd.exe into a
    # log file instead, so the real exit code survives (Start-Process -Redirect* loses it).
    $log = Join-Path $OutRoot 'build-last.log'
    $manifest = Join-Path $agentDir 'Cargo.toml'
    $cmd = 'cargo.exe +1.75.0 build --release --offline --manifest-path "{0}" > "{1}" 2>&1' -f $manifest, $log
    $null = & cmd.exe /c $cmd
    $code = $LASTEXITCODE
    $text = if (Test-Path $log) { [IO.File]::ReadAllText($log, [Text.Encoding]::UTF8) } else { '' }
    if ($code -ne 0) {
        return [pscustomobject]@{ Ok = $false; Log = $text }
    }
    Copy-Item $rel $exe -Force
    return [pscustomobject]@{ Ok = $true; Log = $text }
}

$results = @()

# Each mutation: a unique anchor present exactly once, the replacement, the check
# text that must appear among the failures, and a one-line description.
$mutations = @(
    [pscustomobject]@{
        Id = 'M1'
        Desc = 'fail-closed removed: invent a reply when the target is silent'
        Anchor = @"
        if pages.is_empty() {
"@
        Replace = @"
        if pages.is_empty() {
            // MUTATION M1: never fail closed - invent a reply instead.
            let fake = vec![0u8; SIM_PAGE_SIZE];
            let _ = listener.send_to(&fake, client);
"@
        Expect = 'silent target -> client received nothing'
    }
    [pscustomobject]@{
        Id = 'M2'
        Desc = 'forward from the wrong socket instead of the probed port'
        Anchor = 'None => match listener.send_to(page, client) {'
        Replace = 'None => match self.forward.send_to(page, client) {'
        Expect = 'every page came from the probed port'
    }
    [pscustomobject]@{
        Id = 'M4'
        Desc = 'B-1 regression: never pin the source address (always use the routing table)'
        Anchor = @"
        let pin = match probed_addr {
            Some(SocketAddr::V4(v4)) if !v4.ip().is_unspecified() && !v4.ip().is_loopback() => {
                self.stats.probe_addr_seen += 1;
                Some(*v4.ip())
"@
        Replace = @"
        let pin = match probed_addr {
            Some(SocketAddr::V4(v4)) if false && !v4.ip().is_unspecified() && !v4.ip().is_loopback() => {
                self.stats.probe_addr_seen += 1;
                Some(*v4.ip())
"@
        Expect = 'egress pin: summary reports 0 unpinned pages'
    }
    [pscustomobject]@{
        Id = 'M5'
        Desc = 'B-2 regression: drop the cooldown so every magic replays'
        Anchor = '            if last.elapsed() < self.cooldown {'
        Replace = '            if false && last.elapsed() < self.cooldown {'
        Expect = 'duplicate run: replays sent == 1'
    }
    [pscustomobject]@{
        Id = 'M3'
        Desc = 'replay the magic twice instead of once (amplification)'
        Anchor = '        match self.forward.send_to(magic, self.game_addr) {'
        Replace = @"
        let _ = self.forward.send_to(magic, self.game_addr);
        match self.forward.send_to(magic, self.game_addr) {
"@
        Expect = 'target received exactly one replay'
    }
)

foreach ($m in $mutations) {
    Write-Host ("--- {0}: {1}" -f $m.Id, $m.Desc)
    $text = [IO.File]::ReadAllText($src, [Text.Encoding]::UTF8)
    $count = ([regex]::Matches($text, [regex]::Escape($m.Anchor))).Count
    if ($count -ne 1) {
        Write-Host ("    [!] anchor appears {0} time(s), expected exactly 1 - mutation not applied" -f $count)
        $results += [pscustomobject]@{ Id = $m.Id; Applied = $false; Caught = $false; Note = "anchor count $count" }
        continue
    }
    $mutated = $text.Replace($m.Anchor, $m.Replace)
    if ($mutated -eq $text) {
        Write-Host "    [!] replacement produced no change"
        $results += [pscustomobject]@{ Id = $m.Id; Applied = $false; Caught = $false; Note = 'no change' }
        continue
    }
    [IO.File]::WriteAllText($src, $mutated, (New-Object Text.UTF8Encoding($false)))

    $b = Build-Agent
    [IO.File]::WriteAllText((Join-Path $OutRoot ("{0}-build.log" -f $m.Id)), $b.Log, (New-Object Text.UTF8Encoding($false)))
    if (-not $b.Ok) {
        Write-Host "    [!] mutation did not compile"
        $results += [pscustomobject]@{ Id = $m.Id; Applied = $true; Caught = $false; Note = 'build failed' }
        [IO.File]::WriteAllText($src, $text, (New-Object Text.UTF8Encoding($false)))
        continue
    }
    $mutHash = (Get-FileHash $exe -Algorithm SHA256).Hash

    $out = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $selftest -ReplayPort 63000 2>&1
    $code = $LASTEXITCODE
    $text2 = ($out -join "`n")
    [IO.File]::WriteAllText((Join-Path $OutRoot ("{0}-selftest.log" -f $m.Id)), $text2, (New-Object Text.UTF8Encoding($false)))

    $caught = ($code -ne 0) -and ($text2 -match [regex]::Escape($m.Expect))
    $failedList = ($out | Where-Object { $_ -match '^\s+-\s' }) -join '; '
    Write-Host ("    mutated exe sha256: {0}" -f $mutHash)
    Write-Host ("    selftest exit={0} caught={1}" -f $code, $caught)
    if ($failedList) { Write-Host ("    failing checks   : {0}" -f $failedList) }
    $results += [pscustomobject]@{ Id = $m.Id; Applied = $true; Caught = $caught; Note = $failedList; Exe = $mutHash }

    [IO.File]::WriteAllText($src, $text, (New-Object Text.UTF8Encoding($false)))
}

# ------------------------------------------------------------------- restore + verify
Write-Host ""
Write-Host "--- restoring pristine source and binaries"
[IO.File]::WriteAllText($src, [IO.File]::ReadAllText((Join-Path $backupDir 'main.rs'), [Text.Encoding]::UTF8), (New-Object Text.UTF8Encoding($false)))
$b = Build-Agent
if (-not $b.Ok) {
    Write-Host "[!] restore build failed"
    [IO.File]::WriteAllText((Join-Path $OutRoot 'restore-build.log'), $b.Log, (New-Object Text.UTF8Encoding($false)))
    exit 2
}
$srcHash1 = (Get-FileHash $src -Algorithm SHA256).Hash
$exeHash1 = (Get-FileHash $exe -Algorithm SHA256).Hash
# The Rust exe is NOT reproducible byte-for-byte across builds (the linker stamps build
# metadata), so restore is verified by the SOURCE hash plus a passing self-test on the
# rebuilt binary. Requiring exe byte-equality would fail on a perfectly good restore.
$sourceRestored = ($srcHash1 -eq $srcHash0)
$restored = $sourceRestored
Write-Host ("    source sha256: {0} (match={1})" -f $srcHash1, $sourceRestored)
Write-Host ("    exe sha256   : {0} (pristine was {1}; Rust exe is not byte-reproducible)" -f $exeHash1, $exeHash0)

# The restored tree must still pass the self-test.
$out = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $selftest -ReplayPort 63000 2>&1
$code = $LASTEXITCODE
[IO.File]::WriteAllText((Join-Path $OutRoot 'restored-selftest.log'), ($out -join "`n"), (New-Object Text.UTF8Encoding($false)))
$restoredPass = ($code -eq 0)
Write-Host ("    restored selftest exit={0} (pass={1})" -f $code, $restoredPass)

$caughtAll = @($results | Where-Object { $_.Caught }).Count
$appliedAll = @($results | Where-Object { $_.Applied }).Count

$verdict = @(
    "M0-E MUTATION TEST",
    ("mutations applied : {0}/{1}" -f $appliedAll, $mutations.Count)
    ("mutations caught  : {0}/{1}" -f $caughtAll, $mutations.Count)
    ("source restored   : {0}" -f $sourceRestored)
    ("exe restored      : (Rust exe is not byte-reproducible; verified by source hash + selftest)")
    ("restored selftest : {0}" -f $(if ($restoredPass) { 'PASS' } else { 'FAIL' }))
    ""
    "Each mutation must be caught by the check it targets; otherwise the self-test"
    "cannot tell a working completion path from a broken one."
    ""
    "pristine source sha256 : $srcHash0"
    "pristine exe sha256    : $exeHash0"
)
$results | ForEach-Object {
    $verdict += ("{0}  applied={1}  caught={2}  {3}  {4}" -f $_.Id, $_.Applied, $_.Caught, $_.Exe, $_.Note)
}
[IO.File]::WriteAllText((Join-Path $OutRoot 'verdict.txt'), ($verdict -join "`r`n") + "`r`n", (New-Object Text.UTF8Encoding($false)))

Write-Host ""
if ($caughtAll -eq $mutations.Count -and $restored -and $restoredPass) {
    Write-Host ("M0E-MUTATION: PASS ({0}/{1} caught, tree restored)" -f $caughtAll, $mutations.Count) -ForegroundColor Green
    exit 0
}
Write-Host ("M0E-MUTATION: FAIL (caught {0}/{1}, restored={2}, selftest={3})" -f $caughtAll, $mutations.Count, $restored, $restoredPass) -ForegroundColor Red
exit 1
