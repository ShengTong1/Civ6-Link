@echo off
setlocal enabledelayedexpansion

REM F0-run.cmd - single entry point for the F0 discovery regression fixture.
REM
REM F0 (REV-016) = "fixed simulated host, reproducible discovery regression".
REM This launcher starts synthetic-host-responder.ps1 in the F0 profile:
REM   - discovery range bound      : 62900..62999 (whole range, exact bind, no REUSEADDR)
REM   - response budget            : 20 (one per refresh; up to 20 refreshes per run)
REM   - listen window              : 1800 s
REM   - passive tail after last one: 30 s
REM
REM Preconditions (the responder enforces them; this is only a reminder):
REM   1. No Civ6 HOST lobby on this machine. A host binds UDP 62900 and the whole
REM      range; the responder refuses rather than force-killing or reusing.
REM      A Civ6 CLIENT lobby does NOT bind 62900 and is fine.
REM   2. Desktop unlocked and Civ6 in the foreground when you click Refresh; the
REM      game only emits its discovery burst from its own window.
REM   3. No admin needed. No route / metric / NIC / firewall / Steam change.
REM
REM Procedure:
REM   1. Double-click this file (or run it from a normal cmd window).
REM   2. Wait for "READY <pid>" - UDP 62900 is then bound by the responder.
REM   3. Switch to Civ6 -> Multiplayer -> LAN (client), click Refresh up to 20 times,
REM      about 6 s apart so each refresh falls outside the 3 s burst window.
REM      Note for each refresh whether CivLink-Test-Room-2222 appears.
REM   4. The responder stops by itself 30 s after the last reply (or after 1800 s).
REM      Leave this window open: it waits for that exit, then verifies the evidence
REM      automatically and prints the evidence directory.
REM
REM Everything is loopback/on-machine only; no traffic leaves this computer.

set BASE=%~dp0..\..\..
set SCRIPTS=%BASE%\CivLink-M0A-audit\scripts
set SCRIPT=%SCRIPTS%\synthetic-host-responder.ps1
set VERIFY=%SCRIPTS%\F0\F0-verify.ps1
set FIXTURE=%BASE%\M0A\captures\E2A-H4-reply-20261113\reply-set

set STAMP=
for /f %%i in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd-HHmmss"') do set STAMP=%%i
if "%STAMP%"=="" set STAMP=unknown
set OUT=%BASE%\M0A\captures\F0-run-%STAMP%

if not exist "%SCRIPT%" ( echo FATAL: responder not found at %SCRIPT% & exit /b 2 )
if not exist "%VERIFY%" ( echo FATAL: verifier not found at %VERIFY% & exit /b 2 )
if not exist "%FIXTURE%\reply-01.bin" ( echo FATAL: fixture set not found at %FIXTURE% & exit /b 2 )

echo === F0: fixed simulated host (discovery regression) ===
echo responder : %SCRIPT%
echo fixture   : %FIXTURE%
echo profile   : range 62900..62999, budget 20 responses, window 1800 s
echo evidence  : %OUT%
echo.

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$ErrorActionPreference='Stop';" ^
  "$p=Start-Process powershell -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File',('%SCRIPT%'),'-FixtureDir',('%FIXTURE%'),'-OutDir',('%OUT%'),'-MaxResponses','20','-BurstWindowMs','3000','-ListenSeconds','1800','-PostResponseSec','30' -WindowStyle Hidden -PassThru;" ^
  "$dead=[datetime]::Now.AddSeconds(20);$bound=$false;" ^
  "while(-not $bound -and [datetime]::Now -lt $dead){ $bound=[bool](Get-NetUDPEndpoint -ErrorAction SilentlyContinue|Where-Object{$_.LocalPort -eq 62900 -and $_.OwningProcess -eq $p.Id}); if(-not $bound){ Start-Sleep -Milliseconds 250 } };" ^
  "if($bound){ Write-Host ('READY {0}' -f $p.Id) } else { Write-Host ('NOT-READY {0}: UDP 62900 not bound within 20 s - is a Civ6 HOST lobby running?' -f $p.Id); exit 3 };"

if errorlevel 3 (
    echo.
    echo F0-RUN: ABORT - the responder could not bind the discovery range.
    echo Check for a running CivilizationVI host lobby, then try again.
    endlocal & exit /b 3
)

echo.
echo NEXT (you):
echo   1. Civ6 - Multiplayer - LAN (client window; do not host)
echo   2. Click Refresh up to 20 times, about 6 s apart
echo   3. Note per refresh whether 'CivLink-Test-Room-2222' appears
echo.
echo Waiting for the responder to write summary.txt (30 s after the last reply,
echo or when the 1800 s window ends). Leave this window open. Ctrl+C aborts.

set WAITED=0
:WAITLOOP
if exist "%OUT%\summary.txt" goto FINISH
ping -n 6 127.0.0.1 >nul 2>&1
set /a WAITED+=5
if %WAITED% GEQ 1830 (
    echo.
    echo F0-RUN: timed out waiting for summary.txt after %WAITED% s.
    echo The responder may still be running; check the evidence dir %OUT%
    endlocal & exit /b 4
)
if %WAITED% GEQ 60 (
    set /a MOD=WAITED %% 60
    if !MOD! EQU 0 echo    still waiting ... %WAITED% s
)
goto WAITLOOP

:FINISH
echo.
echo --- responder finished, verifying evidence ---
powershell -NoProfile -ExecutionPolicy Bypass -File "%VERIFY%" -EvidenceDir "%OUT%"
set VEXIT=%ERRORLEVEL%

echo.
echo --- F0 result ---
if %VEXIT%==0 (
    echo F0-RUN: MACHINE CHECKS PASSED for %OUT%
) else (
    echo F0-RUN: MACHINE CHECKS FAILED ^(F0-verify exit %VEXIT%^) for %OUT%
)
echo.
echo Still yours to confirm (the verifier cannot see the screen):
echo   - how many of your 20 refreshes actually listed CivLink-Test-Room-2222
echo   - any refresh that timed out or errored
echo Send the agent: the evidence dir path, verify-report.txt, and that per-refresh list.
echo Boundary: this shows a simulated host being discovered by one real Civ6 client.
echo It is NOT two real Civ6 copies playing, NOT E2-B, NOT M0-B, and moves no Gate.

endlocal & exit /b %VEXIT%
