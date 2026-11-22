@echo off
REM civtrace build script -- MSVC (cl) version
REM Locates vcvars64.bat automatically (VCVARS env var overrides); MinHook pinned v1.3.4
REM is cloned to ..\deps\MinHook (BSD-2, build-time dependency only).
cd /d "%~dp0"
setlocal

set "VC=%VCVARS%"
if not defined VC call :findvcvars
if not defined VC (
    if exist "D:\MSVC\BuildTools\VC\Auxiliary\Build\vcvars64.bat" set "VC=D:\MSVC\BuildTools\VC\Auxiliary\Build\vcvars64.bat"
)
if not defined VC (
    echo [!] vcvars64.bat not found. Set VCVARS env var and rerun.
    exit /b 1
)

echo [*] vcvars: %VC%
call "%VC%" >nul
if errorlevel 1 (
    echo [!] vcvars64.bat failed
    exit /b 1
)

if not exist "..\deps\MinHook\include\MinHook.h" (
    echo [*] cloning MinHook v1.3.4 ...
    git clone --depth 1 --branch v1.3.4 https://github.com/TsudaKageyu/minhook.git "..\deps\MinHook"
    if errorlevel 1 exit /b 1
)

echo [*] build civtrace.dll ...
cl /nologo /utf-8 /O2 /MT /EHsc /D_WIN32_WINNT=0x0601 /D_CRT_SECURE_NO_WARNINGS /I..\deps\MinHook\include ^
   trace_dll.cpp ..\deps\MinHook\src\buffer.c ..\deps\MinHook\src\hook.c ^
   ..\deps\MinHook\src\trampoline.c ..\deps\MinHook\src\HDE\hde32.c ^
   ..\deps\MinHook\src\HDE\hde64.c ^
   /LD /Fe:civtrace.dll ws2_32.lib psapi.lib
if errorlevel 1 exit /b 1

echo [*] build civinject.exe ...
cl /nologo /utf-8 /O2 /MT /EHsc /D_CRT_SECURE_NO_WARNINGS injector.cpp /Fe:civinject.exe advapi32.lib
if errorlevel 1 exit /b 1

echo [+] done: civtrace.dll + civinject.exe
exit /b 0

:findvcvars
set "VSW=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe"
if not exist "%VSW%" goto :eof
for /f "usebackq delims=" %%i in (`"%VSW%" -latest -products * -property installationPath`) do (
    if exist "%%i\VC\Auxiliary\Build\vcvars64.bat" (
        set "VC=%%i\VC\Auxiliary\Build\vcvars64.bat"
        goto :eof
    )
)
goto :eof
