@echo off
chcp 936 >nul
setlocal
set PEER=%~1
if "%PEER%"=="" set PEER=26.74.126.98
echo.
echo ============================================================
echo  CivLink REV-009  --  ONE real apply -^> restore round trip
echo ============================================================
echo.
echo  PEER = %PEER%
echo.
echo  This performs the single controlled round trip REV-009 approved:
echo  WLAN and ZeroTier are raised to 2045, then restored to the values
echo  captured right before the test.
echo.
echo  Close Civilization VI and stop any capture first.
echo  Network may drop for a few seconds while the metrics change.
echo.
echo  Type YES and press Enter to continue (anything else aborts).
set /p GO=^> 
if /i not "%GO%"=="YES" goto :abort
echo.
echo Elevating ...
powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process powershell -Verb RunAs -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-NoExit','-File','%~dp0rev009-roundtrip.ps1','-PeerIp','%PEER%','-Execute')"
if errorlevel 1 echo [!] Elevation was cancelled - nothing was changed.
echo.
echo A new elevated window is now running the round trip.
goto :end
:abort
echo.
echo Aborted - nothing was changed.
:end
pause