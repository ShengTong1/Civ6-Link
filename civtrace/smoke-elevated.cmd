@echo off
REM elevated smoke test: Defender exclusion (temp) -> inject notepad -> verify -> unload -> remove exclusion
cd /d "%~dp0"
powershell -NoProfile -Command "Add-MpPreference -ExclusionPath '%~dp0'"
start "" notepad.exe
timeout /t 2 /nobreak >nul
echo === inject === > smoke.txt 2>&1
.\civinject.exe -x notepad.exe >> smoke.txt 2>&1
timeout /t 1 /nobreak >nul
echo === unload === >> smoke.txt 2>&1
.\civinject.exe -x notepad.exe -u >> smoke.txt 2>&1
taskkill /im notepad.exe /f >> smoke.txt 2>&1
powershell -NoProfile -Command "Remove-MpPreference -ExclusionPath '%~dp0'"
powershell -NoProfile -Command "((Get-MpPreference).ExclusionPath | Select-String 'CivLink-M0A') >> smoke.txt"
echo done
