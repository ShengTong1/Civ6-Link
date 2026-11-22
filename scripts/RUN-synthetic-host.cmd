REM RUN-synthetic-host.cmd - start the bounded synthetic room responder for the
REM real Civ6 CLIENT experiment (authorized by REV-013-REVIEW section 4).
REM
REM Preconditions:
REM   1. NO Civ6 HOST lobby may be open on this machine (the host binds UDP 62900;
REM      the responder refuses to start while 62900 is occupied, no force-kill).
REM      A Civ6 CLIENT lobby window is fine - the client does not bind 62900.
REM   2. Run this from an ordinary (non-elevated) shell; the script needs no admin.
REM
REM Procedure:
REM   1. Run this cmd. It starts the responder in a hidden window and prints the
REM      PID once UDP 62900 is confirmed bound.
REM   2. Open Civ6 -> Multiplayer -> LAN (client). Refresh the lobby list at most
REM      3 times. Look for a room named 'CivLink-Test-Room-2222'.
REM   3. Report what you see (found / not found). The responder keeps passively
REM      recording for 90 s after the last reply, then stops by itself.
REM   4. Evidence lands in M0A\captures\E2B-synthetic-<timestamp>\ - tell the
REM      agent when done; it will collect and analyze the evidence.
REM
REM NOTE: the responder writes all evidence to its own OutDir; its console
REM output is not captured (Start-Process -RedirectStandardOutput blocks in
REM PS 5.1). Check M0A\captures\E2B-synthetic-<timestamp>\ for evidence.

@echo off
setlocal

set BASE=%~dp0..\..
set SCRIPT=%BASE%\CivLink-M0A-audit\scripts\synthetic-host-responder.ps1
set FIXTURE=%BASE%\M0A\captures\E2A-H4-reply-20261113\reply-set

echo === RUN-synthetic-host: bounded synthetic room responder ===
echo script : %SCRIPT%
echo fixture: %FIXTURE%
echo.
echo The responder itself refuses to start if UDP 62900 is already occupied
echo (a Civ6 HOST lobby). A Civ6 CLIENT lobby does not bind 62900 and is fine.
echo.

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$p=Start-Process powershell -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File',('%SCRIPT%'),'-FixtureDir',('%FIXTURE%'),'-ListenSeconds','600','-PostResponseSec','90' -WindowStyle Hidden -PassThru;" ^
  "$dead=[datetime]::Now.AddSeconds(15);" ^
  "$bound=$false;" ^
  "while(-not $bound -and [datetime]::Now -lt $dead){ $bound = [bool](Get-NetUDPEndpoint -ErrorAction SilentlyContinue|Where-Object{$_.LocalPort -eq 62900 -and $_.OwningProcess -eq $p.Id}); if(-not $bound){ Start-Sleep -Milliseconds 250 } };" ^
  "if($bound){ Write-Host ('READY: responder pid={0} listening on 0.0.0.0:62900' -f $p.Id) } else { Write-Host ('NOT READY: responder did not bind 62900 within 15 s (pid={0}). A Civ6 HOST lobby may hold the port.' -f $p.Id) }"

echo.
echo NEXT STEPS (you):
echo   1. Open Civ6 - Multiplayer - LAN (CLIENT; no host lobby on this machine).
echo   2. Refresh the lobby list at most 3 times.
echo   3. Look for a room named:  CivLink-Test-Room-2222
echo   4. Report to the agent: found / not found.
echo.
echo Evidence dir: %BASE%\M0A\captures\E2B-synthetic-<timestamp>\
echo The responder stops itself 90 s after the last reply (or after 600 s).

endlocal
