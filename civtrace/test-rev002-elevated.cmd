@echo off
setlocal
REM test-rev002-elevated.cmd - self-elevating runner for test-rev002.ps1
REM Adds Defender exclusions BEFORE running so civinject.exe is not quarantined.

net session >nul 2>&1
if %errorlevel% neq 0 (
    echo [elevated] Not running as administrator - relaunching elevated...
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -Command "Add-MpPreference -ExclusionPath '%CD%' -ErrorAction SilentlyContinue; Add-MpPreference -ExclusionPath '%CD%\..\docs\reports\rev002' -ErrorAction SilentlyContinue"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0test-rev002.ps1"
exit /b %errorlevel%
