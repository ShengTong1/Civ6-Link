@echo off
rem ============================================================================
rem  CivLink M0-A · 提权命令助手（常驻）
rem  ---------------------------------------------------------------------------
rem  用法：右键本文件 -> "以管理员身份运行"（只需点一次 UAC）
rem
rem  启动后它会在 captures\ 目录里轮询 <name>.cmd 文件，执行并写 <name>.out。
rem  这样 agent 侧只需要写文件，不再触发任何 UAC 弹窗。
rem
rem  支持的命令（写入 cmd 文件的第一行即可）：
rem    pktmon-start  <label>      开始抓包
rem    pktmon-stop   <label>      停止抓包并转 pcapng
rem    inject                     注入 civtrace.dll 到 CivilizationVI.exe
rem    unload                     停用 civtrace（-u）
rem    status                     查看 pktmon 与游戏进程状态
rem    quit                       结束助手
rem ============================================================================
setlocal EnableDelayedExpansion
set "WORKDIR=%~dp0..\..\M0A\captures"
if not exist "%WORKDIR%" mkdir "%WORKDIR%"
set "HELPERDIR=%~dp0"
set "CIVDIR=%~dp0..\civtrace"
set "LOG=%WORKDIR%\helper.log"

echo [%DATE% %TIME%] helper started (elevated) >> "%LOG%"
echo CivLink elevated helper running.
echo Work dir : %WORKDIR%
echo Log file : %LOG%

:loop
for %%F in ("%WORKDIR%\*.cmd") do (
    set "CMDNAME=%%~nF"
    set "CMDFILE=%%~fF"
    call :HANDLE !CMDNAME! "!CMDFILE!"
)

rem ---- 单次抓包状态文件由 capture-run.ps1 维护，这里只处理命令 ----
timeout /t 2 /nobreak >nul
goto loop

:HANDLE
set "NAME=%~1"
set "FILE=%~2"
set "LINE1="
set /p LINE1=<"%FILE%"
echo [%DATE% %TIME%] cmd %NAME%: "%LINE1%" >> "%LOG%"

for /f "tokens=1,* delims= " %%A in ("%LINE1%") do (
    set "VERB=%%A"
    set "ARG=%%B"
)

if /I "!VERB!"=="quit" (
    echo [%DATE% %TIME%] quit requested >> "%LOG%"
    del "%FILE%" >nul 2>&1
    exit /b 0
)

if /I "!VERB!"=="pktmon-start" (
    powershell -NoProfile -ExecutionPolicy Bypass -Command "& '%HELPERDIR%capture-run.ps1' -Label '!ARG!' -OutRoot '%WORKDIR%' -MaxSeconds 3600" >> "%LOG%" 2>&1
)

if /I "!VERB!"=="inject" (
    "%CIVDIR%\civinject.exe" -x CivilizationVI.exe -i >> "%LOG%" 2>&1
    echo %ERRORLEVEL% > "%WORKDIR%\%NAME%.exit"
)

if /I "!VERB!"=="unload" (
    "%CIVDIR%\civinject.exe" -x CivilizationVI.exe -u >> "%LOG%" 2>&1
    echo %ERRORLEVEL% > "%WORKDIR%\%NAME%.exit"
)

if /I "!VERB!"=="status" (
    echo === pktmon status === >> "%WORKDIR%\%NAME%.out"
    pktmon status >> "%WORKDIR%\%NAME%.out" 2>&1
    echo === game procs === >> "%WORKDIR%\%NAME%.out"
    tasklist /FI "IMAGENAME eq CivilizationVI.exe" >> "%WORKDIR%\%NAME%.out" 2>&1
    tasklist /FI "IMAGENAME eq CivilizationVI_DX12.exe" >> "%WORKDIR%\%NAME%.out" 2>&1
)

echo done >> "%WORKDIR%\%NAME%.out"
del "%FILE%" >nul 2>&1
exit /b 0
