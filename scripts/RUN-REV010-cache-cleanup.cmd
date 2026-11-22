@echo off
chcp 936 >nul
title REV-010 destination cache cleanup (targeted)
net session >nul 2>&1
if not errorlevel 1 goto run
echo.
echo   This window is NOT elevated - requesting administrator rights...
powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
exit /b
:run
echo   Elevated. Running targeted cleanup:
echo     netsh interface ipv4 delete destinationcache interface=10 address=26.187.101.177
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "C:\Users\dd\Desktop\injciv6-v0.3.3\CivLink-M0A-audit\scripts\rev010-apply.ps1"
echo.
echo   Result file: C:\Users\dd\Desktop\injciv6-v0.3.3\CivLink-M0A-audit\scripts\rev010-result.txt
pause