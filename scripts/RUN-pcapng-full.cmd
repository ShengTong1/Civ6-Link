@echo off
chcp 936 >nul
title CivLink - 完整载荷抓包（需管理员）
echo ============================================================
echo   Civilization VI 联机发现 - 完整 UDp 载荷抓包
echo   与之前不同的是：这次记录整个数据包（--pkt-size 0）
echo   并且只抓 IPv4/UDP，文件不会太大
echo ============================================================
echo.
net session >nul 2>&1
if errorlevel 1 (
  echo [错误] 当前不是管理员权限。
  echo 请右键本文件 - 以管理员身份运行
  echo.
  pause
  exit /b 1
)
echo [OK] 管理员权限
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0pcapng-capture-full.ps1"
echo.
pause