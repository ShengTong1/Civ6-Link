@echo off
setlocal

REM F0-selftest.cmd - end-to-end self-test of the F0 fixture, WITHOUT Civ6.
REM
REM Proves the whole F0 loop works before a human ever opens the game:
REM   1. start synthetic-host-responder.ps1 in the same profile F0-run.cmd uses
REM      (full 62900..62999 range bind, 3 s burst window, response budget);
REM   2. send ONE magic request to a loopback port that is NOT 62900, which only
REM      succeeds if the range bind really works;
REM   3. require 22 replies of 1104 B from that same port;
REM   4. let the responder finish its listen window and finalise its summary;
REM   5. run F0-verify.ps1 on the evidence directory and require exit 0.
REM
REM What it does NOT prove: that Civ6 shows the room. That is the human step in
REM F0-run.cmd and cannot be automated here.
REM
REM Loopback only - no traffic leaves this machine. No admin needed.
REM Evidence: M0A\captures\F0-selftest-<timestamp>\ plus its verify-report.txt

set BASE=%~dp0..\..\..
set SCRIPTS=%BASE%\CivLink-M0A-audit\scripts
set SCRIPT=%SCRIPTS%\synthetic-host-responder.ps1
set VERIFY=%SCRIPTS%\F0\F0-verify.ps1
set FIXTURE=%BASE%\M0A\captures\E2A-H4-reply-20261113\reply-set
set TESTPORT=62957

REM Locale-independent timestamp; %date%/%time% break on non-English locales.
set STAMP=
for /f %%i in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd-HHmmss"') do set STAMP=%%i
if "%STAMP%"=="" set STAMP=unknown
set OUT=%BASE%\M0A\captures\F0-selftest-%STAMP%

if not exist "%SCRIPT%" ( echo FATAL: responder missing: %SCRIPT% & exit /b 2 )
if not exist "%VERIFY%" ( echo FATAL: verifier missing: %VERIFY% & exit /b 2 )
if not exist "%FIXTURE%\reply-01.bin" ( echo FATAL: fixture missing: %FIXTURE% & exit /b 2 )

echo === F0 self-test (loopback, no Civ6) ===
echo out     : %OUT%
echo profile : range 62900..62999, budget 5, burst window 3000 ms, listen 20 s
echo probe   : 127.0.0.1:%TESTPORT% (not 62900 - proves the range bind)
echo.

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$ErrorActionPreference='Stop';" ^
  "$p=Start-Process powershell -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File',('%SCRIPT%'),'-FixtureDir',('%FIXTURE%'),'-OutDir',('%OUT%'),'-MaxResponses','5','-BurstWindowMs','3000','-ListenSeconds','20','-PostResponseSec','3' -WindowStyle Hidden -PassThru;" ^
  "$dead=[datetime]::Now.AddSeconds(20);" ^
  "while(-not (Get-NetUDPEndpoint -ErrorAction SilentlyContinue|Where-Object{$_.LocalPort -eq %TESTPORT% -and $_.OwningProcess -eq $p.Id}) -and [datetime]::Now -lt $dead){ Start-Sleep -Milliseconds 200 };" ^
  "$bound=(Get-NetUDPEndpoint -ErrorAction SilentlyContinue|Where-Object{$_.OwningProcess -eq $p.Id}).Count;" ^
  "Write-Host ('responder pid={0} bound_ports={1}' -f $p.Id,$bound);" ^
  "$s=[System.Net.Sockets.Socket]::new([System.Net.Sockets.AddressFamily]::InterNetwork,[System.Net.Sockets.SocketType]::Dgram,[System.Net.Sockets.ProtocolType]::Udp);" ^
  "$s.Bind([System.Net.IPEndPoint]::new([System.Net.IPAddress]::Loopback,0));" ^
  "$s.SendTo([byte[]](0x8d,0xe8,0xfc,0x70),[System.Net.IPEndPoint]::new([System.Net.IPAddress]::Loopback,%TESTPORT%))|Out-Null;" ^
  "$s.ReceiveTimeout=8000;$got=0;$fromTestPort=0;$wrongLen=0;$buf=[byte[]]::new(65536);" ^
  "while($got -lt 22){ try{ $ep=[System.Net.EndPoint][System.Net.IPEndPoint]::new([System.Net.IPAddress]::Any,0); $n=$s.ReceiveFrom($buf,[ref]$ep); if($n -eq 1104){$got++; if((($ep -as [System.Net.IPEndPoint]).Port) -eq %TESTPORT%){$fromTestPort++}}else{$wrongLen++} }catch{ break } };" ^
  "$s.Dispose();" ^
  "Write-Host ('SELFTEST-NET: replies={0}/22 from_probe_port={1} wrong_length={2}' -f $got,$fromTestPort,$wrongLen);" ^
  "$done=$p.WaitForExit(45000);" ^
  "if(-not $done){ Write-Host 'SELFTEST-NET: responder did not finalise in time, stopping it'; Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue } else { Write-Host ('SELFTEST-NET: responder exited naturally, code={0}' -f $p.ExitCode) };"

echo.
echo --- verifying evidence ---
powershell -NoProfile -ExecutionPolicy Bypass -File "%VERIFY%" -EvidenceDir "%OUT%"
set VEXIT=%ERRORLEVEL%

echo.
echo --- selftest result ---
if %VEXIT%==0 (
    echo F0-SELFTEST: PASS ^(fixture + evidence chain verified^)
) else (
    echo F0-SELFTEST: FAIL ^(F0-verify exit %VEXIT%^)
)
echo evidence: %OUT%
echo.
echo Reminder: this proves the fixture, not that Civ6 lists the room. Run F0-run.cmd
echo and refresh the in-game LAN list to close that part of F0.

endlocal & exit /b %VEXIT%
