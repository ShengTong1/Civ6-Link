#requires -Version 5.1
<#
  CivLink P1 GUI - T1 reproducible build.
  Design: docs/M0D-GUI-DESIGN-20261118.md §1.2 (T1 preconditions) and §5 (T1 acceptance).
  Compiles the EXISTING civlink/ctl/civlink_ctl_gui.cs VERBATIM with a fixed Roslyn csc,
  then writes build-manifest.txt (csc version, args, refs, source/output SHA-256).
  No source file is modified. Any failure stops the build (exit 1).
#>
$ErrorActionPreference = 'Stop'

$guiDir = $PSScriptRoot
# Product GUI source (T2-T5). The T1 prototype civlink/ctl/civlink_ctl_gui.cs is retained for history.
$src    = Join-Path $guiDir 'civlink_tray.cs'
$csc    = 'D:\MSVC\BuildTools\MSBuild\Current\Bin\Roslyn\csc.exe'
$fxDir  = 'C:\Windows\Microsoft.NET\Framework64\v4.0.30319'
$out    = Join-Path $guiDir 'civlink_tray.exe'
$manifest = Join-Path $guiDir 'build-manifest.txt'

# Pinned reference assemblies. System.Core added for HashSet<T> (T2 product source).
$refs = @(
  (Join-Path $fxDir 'mscorlib.dll'),
  (Join-Path $fxDir 'System.dll'),
  (Join-Path $fxDir 'System.Core.dll'),
  (Join-Path $fxDir 'System.Windows.Forms.dll'),
  (Join-Path $fxDir 'System.Drawing.dll')
)

foreach ($f in (@($csc, $src) + $refs)) {
  if (-not (Test-Path -LiteralPath $f)) { throw "missing required file: $f" }
}
if (Test-Path -LiteralPath $out) { Remove-Item -LiteralPath $out -Force }

# Fixed argument order; refs pinned to absolute paths for reproducibility.
# Verbatim-shape compile (bare /r names) was proven by parent agent: EXIT=0, 9,216 B.
$argList = @('/nologo', '/target:winexe', '/optimize+', '/deterministic+')
foreach ($r in $refs) { $argList += ('/r:"{0}"' -f $r) }
$argList += ('"{0}"' -f $src)
$argList += ('/out:"{0}"' -f $out)
$argString = ($argList -join ' ')

$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = $csc
$psi.Arguments = $argString
$psi.UseShellExecute = $false
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
$psi.CreateNoWindow = $true
$psi.WorkingDirectory = $guiDir

$p = [System.Diagnostics.Process]::Start($psi)
$so = $p.StandardOutput.ReadToEndAsync()
$se = $p.StandardError.ReadToEndAsync()
$p.WaitForExit() | Out-Null
$stdout = $so.Result
$stderr = $se.Result

if ($p.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $out)) {
  Write-Error "csc failed (exit=$($p.ExitCode))`nSTDOUT:`n$stdout`nSTDERR:`n$stderr"
  exit 1
}

$exeInfo = Get-Item -LiteralPath $out
$exeHash = (Get-FileHash -LiteralPath $out -Algorithm SHA256).Hash
$srcHash = (Get-FileHash -LiteralPath $src -Algorithm SHA256).Hash
$cscVer  = (Get-Item -LiteralPath $csc).VersionInfo.FileVersion

$m = New-Object System.Collections.Generic.List[string]
$m.Add('CivLink P1 GUI - T1 build manifest')
$m.Add("generated_utc   : $([DateTime]::UtcNow.ToString('o'))")
$m.Add("csc_path        : $csc")
$m.Add("csc_version     : $cscVer")
$m.Add("source          : $src")
$m.Add("source_sha256   : $srcHash")
$m.Add("arguments       : $argString")
$m.Add('references      :')
foreach ($r in $refs) {
  $rv = (Get-Item -LiteralPath $r).VersionInfo.FileVersion
  $rh = (Get-FileHash -LiteralPath $r -Algorithm SHA256).Hash
  $m.Add("  - $r")
  $m.Add("      version  : $rv")
  $m.Add("      sha256   : $rh")
}
$m.Add("output          : $out")
$m.Add("output_bytes    : $($exeInfo.Length)")
$m.Add("output_sha256   : $exeHash")
$m.Add('note            : output_sha256 is NOT stable across rebuilds even with /deterministic+ (verified 2026-11-18: same source+refs -> 22 PE/MVID bytes differ, PE TimeDateStamp + MVID GUID, because this host has no official .NET Framework reference assemblies). Acceptance = source_sha256 (stable) + output_bytes (stable for a fixed source) + zero-error exit; do NOT treat a changed output_sha256 as tampering. T2 product source replaces the T1 prototype, so output_bytes is larger than the T1 9216 B baseline.')
[IO.File]::WriteAllLines($manifest, $m, (New-Object System.Text.UTF8Encoding($false)))

"BUILD_OK exit=$($p.ExitCode) bytes=$($exeInfo.Length) sha256=$exeHash"
"MANIFEST=$manifest"
