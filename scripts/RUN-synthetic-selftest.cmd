REM RUN-synthetic-selftest.cmd
@echo off
setlocal
REM End-to-end self-test of synthetic-host-responder.ps1 v2 WITHOUT Civ6:
REM   - starts the responder in a separate powershell process (range bind 62900..62999)
REM   - sends 1 magic request (8d e8 fc 70) to 127.0.0.1:62957 (a NON-62900 port: the
REM     client was observed to pick 62957, so the test must prove the range bind works)
REM   - expects 22 replies of 1104 bytes FROM source port 62957
REM   - then inspects the evidence files and stops the responder
REM Loopback only: no traffic leaves this machine.

set BASE=%~dp0..\..\
set SCRIPT=%BASE%CivLink-M0A-audit\scripts\synthetic-host-responder.ps1
set FIXTURE=%BASE%M0A\captures\E2A-H4-reply-20261113\reply-set
set OUT=%BASE%M0A\captures\E2B-synthetic-selftest
set TESTPORT=62957

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$ErrorActionPreference='Stop';" ^
  "$p=Start-Process powershell -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File',('%SCRIPT%'),'-FixtureDir',('%FIXTURE%'),'-OutDir',('%OUT%'),'-ListenSeconds','40','-PostResponseSec','3' -WindowStyle Hidden -PassThru;" ^
  "$dead=[datetime]::Now.AddSeconds(25);" ^
  "while(-not (Get-NetUDPEndpoint -ErrorAction SilentlyContinue|Where-Object{$_.LocalPort -eq %TESTPORT% -and $_.OwningProcess -eq $p.Id}) -and [datetime]::Now -lt $dead){ Start-Sleep -Milliseconds 200 };" ^
  "$bound=(Get-NetUDPEndpoint -ErrorAction SilentlyContinue|Where-Object{$_.OwningProcess -eq $p.Id}).Count;" ^
  "Write-Host ('responder pid={0} bound_ports={1}' -f $p.Id,$bound);" ^
  "$s=[System.Net.Sockets.Socket]::new([System.Net.Sockets.AddressFamily]::InterNetwork,[System.Net.Sockets.SocketType]::Dgram,[System.Net.Sockets.ProtocolType]::Udp);" ^
  "$s.Bind([System.Net.IPEndPoint]::new([System.Net.IPAddress]::Loopback,0));" ^
  "$s.SendTo([byte[]](0x8d,0xe8,0xfc,0x70),[System.Net.IPEndPoint]::new([System.Net.IPAddress]::Loopback,%TESTPORT%))|Out-Null;" ^
  "$s.ReceiveTimeout=8000;$got=0;$fromTestPort=0;$buf=[byte[]]::new(65536);" ^
  "while($got -lt 22){ try{ $ep=[System.Net.EndPoint][System.Net.IPEndPoint]::new([System.Net.IPAddress]::Any,0); $n=$s.ReceiveFrom($buf,[ref]$ep); if($n -eq 1104){$got++; if((($ep -as [System.Net.IPEndPoint]).Port) -eq %TESTPORT%){$fromTestPort++} } }catch{ break } };" ^
  "$s.Dispose();" ^
  "Start-Sleep -Seconds 2;" ^
  "$st=Join-Path ('%OUT%') 'summary.txt';" ^
  "$req=Join-Path ('%OUT%') 'requests.log';" ^
  "$hasResp=(Test-Path $req) -and ((Select-String -Path $req -Pattern 'RESPONSE #1' -Quiet) -eq $true);" ^
  "$pageCount=0; if(Test-Path $req){ $pageCount=(Select-String -Path $req -Pattern 'page \d\d: sent' | Measure-Object).Count };" ^
  "Write-Host ('SELF-TEST: replies_received={0}/22  from_test_port={1}  responses_logged={2}  pages_sent_lines={3}' -f $got,$fromTestPort,$hasResp,$pageCount);" ^
  "Write-Host ('evidence: {0}' -f ('%OUT%'));" ^
  "if(Test-Path $st){ Get-Content $st | Select-Object -First 10 };" ^
  "Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue"

endlocal

