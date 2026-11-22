@echo off
REM civlink F1 build script -- MSVC (cl) version, /MT static CRT (project hard rule).
REM Produces:
REM   civlink_hook.dll   observation-only discovery Hook DLL (x64)
REM   civlink_ctl.exe    inject / status / counters / shutdown controller
REM MinHook is the same pinned v1.3.4 tree used by civtrace (..\deps\MinHook).
REM
REM NOTE ON OBJECT PATHS: our hook\hook.cpp and MinHook's src\hook.c share the object base
REM name "hook". Compiling both into the same directory made cl overwrite one with the other
REM (LNK4042 "object specified multiple times"), silently producing a DLL with none of our
REM code and no exports. Every target therefore gets its own /Fo directory, and the build
REM FAILS if the four required exports are missing.
cd /d "%~dp0"
setlocal enabledelayedexpansion

set "VC=%VCVARS%"
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

set "MH=..\deps\MinHook"
if not exist "%MH%\include\MinHook.h" (
    echo [!] MinHook not found at %MH%
    exit /b 1
)

set "CFLAGS=/nologo /utf-8 /O2 /MT /EHsc /W3 /D_WIN32_WINNT=0x0601 /D_CRT_SECURE_NO_WARNINGS"
set "INC=/I%MH%\include /Icommon"

if not exist obj\cvl     mkdir obj\cvl
if not exist obj\minhook mkdir obj\minhook
if not exist obj\ctl     mkdir obj\ctl
if not exist obj\client  mkdir obj\client
del /q obj\cvl\*.obj obj\minhook\*.obj obj\ctl\*.obj obj\client\*.obj 2>nul

echo [*] building civlink_hook.dll
if defined CIVLINK_SKIP_DLL (
    REM The DLL stays mapped in the target process until that process exits
    REM (B2 audit-run mode: shutdown never unloads it), so the file is locked and
    REM link fails with LNK1104. When only the controller changed, set
    REM CIVLINK_SKIP_DLL=1 to rebuild the other targets against the existing DLL.
    echo [*] CIVLINK_SKIP_DLL set - reusing the existing civlink_hook.dll
    goto after_dll
)
cl %CFLAGS% %INC% /DCIVLINK_HOOK_EXPORTS /Foobj\cvl\ /c hook\hook.cpp
if errorlevel 1 (
    echo [!] civlink_hook.dll compile failed ^(hook.cpp^)
    exit /b 1
)
cl %CFLAGS% /Foobj\minhook\ /c %MH%\src\buffer.c %MH%\src\hook.c %MH%\src\trampoline.c %MH%\src\HDE\hde32.c %MH%\src\HDE\hde64.c
if errorlevel 1 (
    echo [!] civlink_hook.dll compile failed ^(MinHook^)
    exit /b 1
)
link /nologo /DLL /OUT:civlink_hook.dll /PDB:civlink_hook.pdb ^
     obj\cvl\hook.obj ^
     obj\minhook\buffer.obj obj\minhook\hook.obj obj\minhook\trampoline.obj ^
     obj\minhook\hde32.obj obj\minhook\hde64.obj ^
     ws2_32.lib psapi.lib
if errorlevel 1 (
    echo [!] civlink_hook.dll link failed
    exit /b 1
)

echo [*] checking exports
set "MISSING="
for %%E in (CivLinkHookState CivLinkShutdown CivLinkGetCounters CivLinkSessionId) do (
    dumpbin /nologo /exports civlink_hook.dll | findstr /C:"%%E" >nul
    if errorlevel 1 set "MISSING=!MISSING! %%E"
)
if defined MISSING (
    echo [!] civlink_hook.dll is missing required exports:!MISSING!
    exit /b 1
)

:after_dll
echo [*] building civlink_client.dll ^(C2 client NIC-pin Hook DLL^)
if defined CIVLINK_SKIP_CLIENT_DLL (
    echo [*] CIVLINK_SKIP_CLIENT_DLL set - reusing the existing civlink_client.dll
    goto after_client_dll
)
cl %CFLAGS% %INC% /DCIVLINK_HOOK_EXPORTS /Foobj\client\ /c client\civlink_client.cpp
if errorlevel 1 (
    echo [!] civlink_client.dll compile failed ^(civlink_client.cpp^)
    exit /b 1
)
cl %CFLAGS% /Foobj\minhook\ /c %MH%\src\buffer.c %MH%\src\hook.c %MH%\src\trampoline.c %MH%\src\HDE\hde32.c %MH%\src\HDE\hde64.c
if errorlevel 1 (
    echo [!] civlink_client.dll compile failed ^(MinHook^)
    exit /b 1
)
link /nologo /DLL /OUT:civlink_client.dll /PDB:civlink_client.pdb ^
     obj\client\civlink_client.obj ^
     obj\minhook\buffer.obj obj\minhook\hook.obj obj\minhook\trampoline.obj ^
     obj\minhook\hde32.obj obj\minhook\hde64.obj ^
     ws2_32.lib iphlpapi.lib psapi.lib
if errorlevel 1 (
    echo [!] civlink_client.dll link failed
    exit /b 1
)
echo [*] checking civlink_client.dll exports
set "CLIENT_MISSING="
for %%E in (CivLinkHookState CivLinkShutdown CivLinkGetCounters CivLinkSessionId CivLinkReactivate) do (
    dumpbin /nologo /exports civlink_client.dll | findstr /C:"%%E" >nul
    if errorlevel 1 set "CLIENT_MISSING=!CLIENT_MISSING! %%E"
)
if defined CLIENT_MISSING (
    echo [!] civlink_client.dll is missing required exports:!CLIENT_MISSING!
    exit /b 1
)

:after_client_dll
echo [*] building civlink_ctl.exe
cl %CFLAGS% %INC% /Foobj\ctl\ /c ctl\civlink_ctl.cpp
if errorlevel 1 (
    echo [!] civlink_ctl.exe compile failed
    exit /b 1
)
link /nologo /OUT:civlink_ctl.exe /PDB:civlink_ctl.pdb obj\ctl\civlink_ctl.obj advapi32.lib psapi.lib iphlpapi.lib ws2_32.lib
if errorlevel 1 (
    echo [!] civlink_ctl.exe link failed
    exit /b 1
)

echo [*] building hook_selftest.exe
if not exist obj\selftest mkdir obj\selftest
cl %CFLAGS% %INC% /Foobj\selftest\ /c selftest\hook_selftest.cpp
if errorlevel 1 (
    echo [!] hook_selftest.exe compile failed
    exit /b 1
)
link /nologo /OUT:hook_selftest.exe /PDB:hook_selftest.pdb obj\selftest\hook_selftest.obj ws2_32.lib
if errorlevel 1 (
    echo [!] hook_selftest.exe link failed
    exit /b 1
)

echo [*] building client_selftest.exe
cl %CFLAGS% %INC% /Foobj\selftest\ /c selftest\client_selftest.cpp
if errorlevel 1 (
    echo [!] client_selftest.exe compile failed
    exit /b 1
)
link /nologo /OUT:client_selftest.exe /PDB:client_selftest.pdb obj\selftest\client_selftest.obj ws2_32.lib iphlpapi.lib
if errorlevel 1 (
    echo [!] client_selftest.exe link failed
    exit /b 1
)

echo [*] done
for %%F in (civlink_hook.dll civlink_client.dll civlink_ctl.exe hook_selftest.exe client_selftest.exe) do (
    for /f "usebackq" %%H in (`powershell -NoProfile -Command "(Get-FileHash -Algorithm SHA256 '%%F').Hash.ToUpper()"`) do (
        for %%S in (%%F) do echo     %%F  %%~zS B  sha256=%%H
    )
)
endlocal
exit /b 0
