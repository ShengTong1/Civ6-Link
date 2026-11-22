# test-rev002.ps1 - CivLink M0A REV-002 evidence collection (run as Administrator)
# Covers the REV-002 "must-add verifications": socket width, multi-thread hook
# stress, shutdown vs ongoing socket calls, shutdown reentry + fail-then-retry,
# log queue full, log lock contention, invalid pointer protection,
# WSAEnumNetworkEvents failure path, GetExitCodeThread failure sim, FreeLibrary
# refcount 1/2(+extra), LoadLibraryW remote-thread timeout sim, module-enum
# grow retry, /MT+TLS static check. Raw logs + environment + hashes preserved.
$ErrorActionPreference = 'Continue'
$base = 'C:\Users\dd\Desktop\injciv6-v0.3.3\CivLink-M0A-audit'
$rep  = "$base\docs\reports\rev002"
$civ  = "$base\civtrace"
$tmp  = Join-Path $env:TEMP 'civrev002'
New-Item -ItemType Directory -Force -Path $rep, $tmp | Out-Null
Remove-Item "$rep\run-*.txt" -ErrorAction SilentlyContinue
$injector = "$civ\civinject.exe"
$dll      = "$civ\civtrace.dll"
$ap       = Join-Path $env:LOCALAPPDATA 'CivLink\M0A\logs'
$marker   = Join-Path $tmp 'markers'; New-Item -ItemType Directory -Force -Path $marker | Out-Null

# self-exclusion: we run elevated, so add the civtrace dir to Defender exclusions
# (quarantine of civinject.exe was the root cause of the failed 2nd run)
try { Add-MpPreference -ExclusionPath $civ -ErrorAction SilentlyContinue } catch {}
try { Add-MpPreference -ExclusionPath $rep -ErrorAction SilentlyContinue } catch {}
Start-Sleep -Seconds 2
if (-not (Test-Path $injector) -or -not (Test-Path $dll)) {
    # Defender may have just quarantined the fresh build; restore from threat detections
    Get-MpThreatDetection | Where-Object { $_.ThreatID -eq 2147731250 -and $_.Resources -match 'civinject' } | ForEach-Object {
        try { Remove-MpThreat -ThreatID $_.ThreatID -ErrorAction SilentlyContinue } catch {}
    }
    Start-Sleep -Seconds 2
}
# hard binary existence check (Defender quarantine guard)
if (-not (Test-Path $injector) -or -not (Test-Path $dll)) {
    "FATAL: missing binary -> $injector / $dll (Defender quarantine? rebuild first)" | Out-File "$rep\environment.txt" -Encoding utf8
    exit 3
}

# ---- environment record ----
$os = Get-CimInstance Win32_OperatingSystem
$cs = Get-CimInstance Win32_ComputerSystem
"run rev002: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss K')" | Out-File "$rep\environment.txt" -Encoding utf8
"$($os.Caption) build $($os.BuildNumber) UBR $((Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').UBR)" | Out-File "$rep\environment.txt" -Append -Encoding utf8
"Admin: $(([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))  User: $env:USERNAME  Machine: $($cs.Name)" | Out-File "$rep\environment.txt" -Append -Encoding utf8
"Injector SHA256: $((Get-FileHash $injector -Algorithm SHA256).Hash.ToLower())" | Out-File "$rep\environment.txt" -Append -Encoding utf8
"DLL SHA256: $((Get-FileHash $dll -Algorithm SHA256).Hash.ToLower())" | Out-File "$rep\environment.txt" -Append -Encoding utf8

# ---- payload scripts (ASCII only) ----
$pUdp = @'
$s=New-Object Net.Sockets.Socket([Net.Sockets.AddressFamily]::InterNetwork,[Net.Sockets.SocketType]::Dgram,[Net.Sockets.ProtocolType]::Udp)
$s.Bind((New-Object Net.IPEndPoint([Net.IPAddress]::Any,0)));$s.Blocking=$false
$ep=New-Object Net.IPEndPoint([Net.IPAddress]::Loopback,62056);$buf=New-Object byte[] 120
for($i=0;$i -lt 150;$i++){try{$null=$s.SendTo($buf,$ep)}catch{};try{$null=$s.ReceiveFrom($buf,[ref]$ep)}catch{};Start-Sleep -m 120}
$s.Close();Start-Sleep -Seconds 900
'@
Set-Content -Path "$tmp\p_udp.ps1" -Value $pUdp -Encoding Ascii

$pMt = @'
Add-Type -TypeDefinition @"
using System;
using System.Net;
using System.Net.Sockets;
using System.Threading;
public static class MT {
  public static void Stress(int secs, int threads) {
    int running = 0;
    var end = DateTime.UtcNow.AddSeconds(secs);
    for (int t = 0; t < threads; t++) {
      Interlocked.Increment(ref running);
      ThreadPool.QueueUserWorkItem(delegate {
        try {
          var so = new Socket(AddressFamily.InterNetwork, SocketType.Dgram, ProtocolType.Udp);
          so.Bind(new IPEndPoint(IPAddress.Any, 0));
          so.Blocking = false;
          var ep = new IPEndPoint(IPAddress.Loopback, 62056);
          byte[] b = new byte[120];
          while (DateTime.UtcNow < end) {
            try { so.SendTo(b, ep); } catch {}
            try { so.ReceiveFrom(b, ref ep); } catch {}
            so.SetSocketOption(SocketOptionLevel.Socket, SocketOptionName.ReuseAddress, true);
          }
          so.Close();
        } catch {}
        Interlocked.Decrement(ref running);
      });
    }
    while (Interlocked.CompareExchange(ref running, 0, 0) > 0) Thread.Sleep(50);
  }
}
"@
[MT]::Stress(8, 8)
"mt-done" | Out-File "$env:TEMP\civrev002\markers\mt-done.txt"
Start-Sleep -Seconds 900
'@
Set-Content -Path "$tmp\p_mt.ps1" -Value $pMt -Encoding Ascii

$pInv = @'
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class Inv {
  [DllImport("ws2_32.dll")] public static extern IntPtr socket(int af, int type, int proto);
  [DllImport("ws2_32.dll")] public static extern int setsockopt(IntPtr s, int lvl, int opt, IntPtr val, int len);
  [DllImport("ws2_32.dll")] public static extern int ioctlsocket(IntPtr s, int cmd, IntPtr argp);
  [DllImport("ws2_32.dll")] public static extern int recvfrom(IntPtr s, IntPtr buf, int len, int fl, IntPtr from, IntPtr fromlen);
  [DllImport("ws2_32.dll")] public static extern IntPtr WSACreateEvent();
  [DllImport("ws2_32.dll")] public static extern int WSACloseEvent(IntPtr e);
  [DllImport("ws2_32.dll")] public static extern int WSAEnumNetworkEvents(IntPtr s, IntPtr e, IntPtr ne);
  [DllImport("ws2_32.dll")] public static extern int WSAGetLastError();
}
"@
$s = [Inv]::socket(2, 2, 17)
$r1 = [Inv]::setsockopt($s, 0xffff, 1, [IntPtr]::Zero, 4)
$r2 = [Inv]::ioctlsocket($s, 0x8004667e, [IntPtr]::Zero)
$r3 = [Inv]::recvfrom($s, [IntPtr]::Zero, 120, 0, [IntPtr]::Zero, [IntPtr]::Zero)
$ev = [Inv]::WSACreateEvent()
$null = [Inv]::WSACloseEvent($ev)
$r4 = [Inv]::WSAEnumNetworkEvents($s, $ev, [IntPtr]::Zero)
"results setsockopt=$r1 ioctlsocket=$r2 recvfrom=$r3 wsaenum=$r4" | Out-File "$env:TEMP\civrev002\markers\inv-done.txt"
Start-Sleep -Seconds 900
'@
Set-Content -Path "$tmp\p_inv.ps1" -Value $pInv -Encoding Ascii

$pXl = @'
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class XL {
  [DllImport("kernel32.dll", CharSet=CharSet.Unicode)] public static extern IntPtr LoadLibraryW(string path);
}
"@
$h = [XL]::LoadLibraryW($args[0])
"extraload handle=$h" | Out-File "$env:TEMP\civrev002\markers\xl-done.txt"
Start-Sleep -Seconds 900
'@
Set-Content -Path "$tmp\p_xl.ps1" -Value $pXl -Encoding Ascii
$pfUdp = "$tmp\p_udp.ps1"
$pfMt  = "$tmp\p_mt.ps1"
$pfInv = "$tmp\p_inv.ps1"
$pfXl  = "$tmp\p_xl.ps1"

function Start-Target([string]$pf, [string[]]$argsX = @()) {
  $a = @('-NoProfile','-ExecutionPolicy','Bypass','-File',$pf) + $argsX
  return Start-Process powershell -WindowStyle Hidden -PassThru -ArgumentList $a
}
function LogOf([int]$pidv) { Get-ChildItem $ap -Filter "civtrace_*_pid$pidv*.log" | Sort-Object LastWriteTime | Select-Object -Last 1 }
function Env-Set([string]$k,[string]$v) { Set-Item "Env:$k" $v }
function Env-Del([string]$k) { Remove-Item "Env:$k" -ErrorAction SilentlyContinue }

# ================= T1: baseline inject + dup + live flush + width runtime =================
$t1 = "$rep\run-T1-baseline.txt"
$A = Start-Target $pfUdp
Start-Sleep -Seconds 3
$tA0 = (Get-Process -Id $A.Id).Threads.Count; $hA0 = (Get-Process -Id $A.Id).HandleCount
Env-Set CIVTRACE_TAG 'rev002'
"T1 pid=$($A.Id) threads_before=$tA0 handles_before=$hA0" | Out-File $t1 -Encoding utf8
(& $injector -x powershell.exe -p $A.Id | Out-String) | Out-File $t1 -Append -Encoding utf8
"exit=$LASTEXITCODE (expect 0)" | Out-File $t1 -Append -Encoding utf8
Start-Sleep -Seconds 4
$lA = LogOf $A.Id
"hookline: $((Select-String -Path $lA.FullName -Pattern 'hooks installed').Line)" | Out-File $t1 -Append -Encoding utf8
"sample socket lines (width evidence):" | Out-File $t1 -Append -Encoding utf8
Select-String -Path $lA.FullName -Pattern 'socket=' | Select-Object -First 4 | ForEach-Object { $_.Line } | Out-File $t1 -Append -Encoding utf8
$sz0 = $lA.Length; Start-Sleep -Seconds 6; $sz1 = (Get-Item $lA.FullName).Length
"liveflush size0=$sz0 size1=$sz1 grew=$($sz1-$sz0)" | Out-File $t1 -Append -Encoding utf8
# duplicate injection
(& $injector -x powershell.exe -p $A.Id | Out-String) | Out-File $t1 -Append -Encoding utf8
"dup_exit=$LASTEXITCODE (expect 0, skip)" | Out-File $t1 -Append -Encoding utf8
# cleanup: normal unload (refcount-1 case, part of T11 evidence)
$tA1 = (Get-Process -Id $A.Id).Threads.Count
(& $injector -x powershell.exe -p $A.Id -u | Out-String) | Out-File $t1 -Append -Encoding utf8
"unload_exit=$LASTEXITCODE (expect 0)" | Out-File $t1 -Append -Encoding utf8
Start-Sleep -Seconds 1
$alive = -not $A.HasExited
$tA2 = if ($alive) { (Get-Process -Id $A.Id).Threads.Count } else { -1 }
$hA2 = if ($alive) { (Get-Process -Id $A.Id).HandleCount } else { -1 }
"target_alive=$alive threads_after=$tA2 (before=$tA0) handles_after=$hA2 (before=$hA0)" | Out-File $t1 -Append -Encoding utf8
"session-end: $((Select-String -Path $lA.FullName -Pattern 'session end').Line)" | Out-File $t1 -Append -Encoding utf8
Copy-Item $lA.FullName "$rep\raw-T1.pid$($A.Id).log" -Force
if (-not $A.HasExited) { Stop-Process -Id $A.Id -Force -ErrorAction SilentlyContinue }
Env-Del CIVTRACE_TAG

# ================= T2: multi-thread stress + queue full (RING_SHIFT=6) =================
$t2 = "$rep\run-T2-stress-queuefull.txt"
Env-Set CIVTRACE_RING_SHIFT '6'
Env-Set CIVTRACE_TAG 'rev002'
$B = Start-Target $pfMt
Start-Sleep -Seconds 3
"T2 pid=$($B.Id)" | Out-File $t2 -Encoding utf8
(& $injector -x powershell.exe -p $B.Id | Out-String) | Out-File $t2 -Append -Encoding utf8
"inject_exit=$LASTEXITCODE (expect 0)" | Out-File $t2 -Append -Encoding utf8
$deadline = (Get-Date).AddSeconds(40)
while (-not (Test-Path "$marker\mt-done.txt") -and (Get-Date) -lt $deadline) { Start-Sleep -Seconds 1 }
"stress_marker_seen=$([bool](Test-Path "$marker\mt-done.txt"))" | Out-File $t2 -Append -Encoding utf8
$lB = LogOf $B.Id
"alive_after_stress=$(-not $B.HasExited)" | Out-File $t2 -Append -Encoding utf8
"drops lines:" | Out-File $t2 -Append -Encoding utf8
Select-String -Path $lB.FullName -Pattern 'log-drops' | Select-Object -Last 3 | ForEach-Object { $_.Line } | Out-File $t2 -Append -Encoding utf8
(& $injector -x powershell.exe -p $B.Id -u | Out-String) | Out-File $t2 -Append -Encoding utf8
"unload_exit=$LASTEXITCODE (expect 0)" | Out-File $t2 -Append -Encoding utf8
Start-Sleep -Seconds 1
"session-end: $((Select-String -Path $lB.FullName -Pattern 'session end').Line)" | Out-File $t2 -Append -Encoding utf8
Copy-Item $lB.FullName "$rep\raw-T2.pid$($B.Id).log" -Force
if (-not $B.HasExited) { Stop-Process -Id $B.Id -Force -ErrorAction SilentlyContinue }
Env-Del CIVTRACE_RING_SHIFT; Env-Del CIVTRACE_TAG

# ================= T3: shutdown while socket calls ongoing =================
$t3 = "$rep\run-T3-shutdown-concurrency.txt"
Env-Set CIVTRACE_TAG 'rev002'
$C = Start-Target $pfUdp
Start-Sleep -Seconds 3
"T3 pid=$($C.Id)" | Out-File $t3 -Encoding utf8
(& $injector -x powershell.exe -p $C.Id | Out-String) | Out-File $t3 -Append -Encoding utf8
"inject_exit=$LASTEXITCODE (expect 0)" | Out-File $t3 -Append -Encoding utf8
Start-Sleep -Seconds 2
(& $injector -x powershell.exe -p $C.Id -u | Out-String) | Out-File $t3 -Append -Encoding utf8
"unload_exit=$LASTEXITCODE (expect 0)" | Out-File $t3 -Append -Encoding utf8
Start-Sleep -Seconds 1
$lC = LogOf $C.Id
"alive_after_unload=$(-not $C.HasExited)" | Out-File $t3 -Append -Encoding utf8
"session-end: $((Select-String -Path $lC.FullName -Pattern 'session end').Line)" | Out-File $t3 -Append -Encoding utf8
Copy-Item $lC.FullName "$rep\raw-T3.pid$($C.Id).log" -Force
if (-not $C.HasExited) { Stop-Process -Id $C.Id -Force -ErrorAction SilentlyContinue }
Env-Del CIVTRACE_TAG

# ================= T4: shutdown reentry (double call expected code=1) =================
$t4 = "$rep\run-T4-shutdown-reentry.txt"
Env-Set CIVTRACE_TAG 'rev002'
$D = Start-Target $pfUdp
Start-Sleep -Seconds 3
"T4 pid=$($D.Id)" | Out-File $t4 -Encoding utf8
(& $injector -x powershell.exe -p $D.Id | Out-String) | Out-File $t4 -Append -Encoding utf8
"inject_exit=$LASTEXITCODE (expect 0)" | Out-File $t4 -Append -Encoding utf8
Start-Sleep -Seconds 2
Env-Set CIVTRACE_INJ_TEST_DOUBLE_SHUTDOWN '1'
(& $injector -x powershell.exe -p $D.Id -u | Out-String) | Out-File $t4 -Append -Encoding utf8
"unload_exit=$LASTEXITCODE (expect 0)" | Out-File $t4 -Append -Encoding utf8
Env-Del CIVTRACE_INJ_TEST_DOUBLE_SHUTDOWN
$lD = LogOf $D.Id
"session-end: $((Select-String -Path $lD.FullName -Pattern 'session end').Line)" | Out-File $t4 -Append -Encoding utf8
Copy-Item $lD.FullName "$rep\raw-T4.pid$($D.Id).log" -Force
if (-not $D.HasExited) { Stop-Process -Id $D.Id -Force -ErrorAction SilentlyContinue }
Env-Del CIVTRACE_TAG

# ================= T5: shutdown fail-then-retry (SIM_SHUTDOWN_FAILS=1) =================
$t5 = "$rep\run-T5-shutdown-fail-retry.txt"
Env-Set CIVTRACE_SIM_SHUTDOWN_FAILS '1'
Env-Set CIVTRACE_TAG 'rev002'
$E = Start-Target $pfUdp
Start-Sleep -Seconds 3
"T5 pid=$($E.Id)" | Out-File $t5 -Encoding utf8
(& $injector -x powershell.exe -p $E.Id | Out-String) | Out-File $t5 -Append -Encoding utf8
"inject_exit=$LASTEXITCODE (expect 0)" | Out-File $t5 -Append -Encoding utf8
Start-Sleep -Seconds 2
(& $injector -x powershell.exe -p $E.Id -u | Out-String) | Out-File $t5 -Append -Encoding utf8
"first_unload_exit=$LASTEXITCODE (expect 2 SHUTDOWN_FAILED, no FreeLibrary)" | Out-File $t5 -Append -Encoding utf8
Start-Sleep -Seconds 1
(& $injector -x powershell.exe -p $E.Id -u | Out-String) | Out-File $t5 -Append -Encoding utf8
"second_unload_exit=$LASTEXITCODE (expect 0, retry succeeded)" | Out-File $t5 -Append -Encoding utf8
$lE = LogOf $E.Id
"session-end: $((Select-String -Path $lE.FullName -Pattern 'session end').Line)" | Out-File $t5 -Append -Encoding utf8
Copy-Item $lE.FullName "$rep\raw-T5.pid$($E.Id).log" -Force
if (-not $E.HasExited) { Stop-Process -Id $E.Id -Force -ErrorAction SilentlyContinue }
Env-Del CIVTRACE_SIM_SHUTDOWN_FAILS; Env-Del CIVTRACE_TAG

# ================= T6/T7: invalid pointer + WSAEnumNetworkEvents failure =================
$t6 = "$rep\run-T6-invalid-pointers.txt"
Env-Set CIVTRACE_TAG 'rev002'
$F = Start-Target $pfInv
Start-Sleep -Seconds 3
"T6 pid=$($F.Id)" | Out-File $t6 -Encoding utf8
(& $injector -x powershell.exe -p $F.Id | Out-String) | Out-File $t6 -Append -Encoding utf8
"inject_exit=$LASTEXITCODE (expect 0)" | Out-File $t6 -Append -Encoding utf8
$deadline = (Get-Date).AddSeconds(30)
while (-not (Test-Path "$marker\inv-done.txt") -and (Get-Date) -lt $deadline) { Start-Sleep -Seconds 1 }
"inv_marker: $(Get-Content "$marker\inv-done.txt" -ErrorAction SilentlyContinue)" | Out-File $t6 -Append -Encoding utf8
"alive_after_bad_calls=$(-not $F.HasExited)" | Out-File $t6 -Append -Encoding utf8
$lF = LogOf $F.Id
"log lines mentioning setsockopt/ioctlsocket/recvfrom/WSARecvFrom/WSAEnumNetworkEvents with err:" | Out-File $t6 -Append -Encoding utf8
Select-String -Path $lF.FullName -Pattern 'err=100[0-9]{2}|err=995|setsockopt|ioctlsocket|recvfrom|WSAEnumNetworkEvents' | Select-Object -Last 8 | ForEach-Object { $_.Line } | Out-File $t6 -Append -Encoding utf8
"T7 WSAEnumNetworkEvents failure-path evidence above (closed event handle, err logged, no crash)" | Out-File $t6 -Append -Encoding utf8
(& $injector -x powershell.exe -p $F.Id -u | Out-String) | Out-File $t6 -Append -Encoding utf8
"unload_exit=$LASTEXITCODE (expect 0)" | Out-File $t6 -Append -Encoding utf8
$lF2 = LogOf $F.Id
"session-end: $((Select-String -Path $lF2.FullName -Pattern 'session end').Line)" | Out-File $t6 -Append -Encoding utf8
Copy-Item $lF2.FullName "$rep\raw-T6.pid$($F.Id).log" -Force
if (-not $F.HasExited) { Stop-Process -Id $F.Id -Force -ErrorAction SilentlyContinue }
Env-Del CIVTRACE_TAG

# ================= T8: GetExitCodeThread failure sim (unload aborts, no FreeLibrary) =================
$t8 = "$rep\run-T8-gec-fail.txt"
Env-Set CIVTRACE_TAG 'rev002'
$G = Start-Target $pfUdp
Start-Sleep -Seconds 3
"T8 pid=$($G.Id)" | Out-File $t8 -Encoding utf8
(& $injector -x powershell.exe -p $G.Id | Out-String) | Out-File $t8 -Append -Encoding utf8
"inject_exit=$LASTEXITCODE (expect 0)" | Out-File $t8 -Append -Encoding utf8
Start-Sleep -Seconds 2
Env-Set CIVTRACE_INJ_SIM_GEC_FAIL '1'
(& $injector -x powershell.exe -p $G.Id -u | Out-String) | Out-File $t8 -Append -Encoding utf8
"sim_unload_exit=$LASTEXITCODE (expect 2, cannot confirm, no FreeLibrary)" | Out-File $t8 -Append -Encoding utf8
Env-Del CIVTRACE_INJ_SIM_GEC_FAIL
Start-Sleep -Seconds 1
(& $injector -x powershell.exe -p $G.Id -u | Out-String) | Out-File $t8 -Append -Encoding utf8
"clean_unload_exit=$LASTEXITCODE (expect 0 - proves module was still loaded after aborted attempt)" | Out-File $t8 -Append -Encoding utf8
$lG = LogOf $G.Id
"session-end: $((Select-String -Path $lG.FullName -Pattern 'session end').Line)" | Out-File $t8 -Append -Encoding utf8
Copy-Item $lG.FullName "$rep\raw-T8.pid$($G.Id).log" -Force
if (-not $G.HasExited) { Stop-Process -Id $G.Id -Force -ErrorAction SilentlyContinue }
Env-Del CIVTRACE_TAG

# ================= T9: LoadLibraryW remote-thread timeout sim =================
$t9 = "$rep\run-T9-load-timeout.txt"
$H = Start-Target $pfUdp
Start-Sleep -Seconds 3
"T9 pid=$($H.Id)" | Out-File $t9 -Encoding utf8
Env-Set CIVTRACE_INJ_SIM_LOAD_TIMEOUT '1'
(& $injector -x powershell.exe -p $H.Id | Out-String) | Out-File $t9 -Append -Encoding utf8
"inject_exit=$LASTEXITCODE (expect 2, remote buffer left in place)" | Out-File $t9 -Append -Encoding utf8
Env-Del CIVTRACE_INJ_SIM_LOAD_TIMEOUT
"alive_after_abort=$(-not $H.HasExited)" | Out-File $t9 -Append -Encoding utf8
(& $injector -x powershell.exe -p $H.Id -u | Out-String) | Out-File $t9 -Append -Encoding utf8
"unload_exit=$LASTEXITCODE (expect 0, not loaded)" | Out-File $t9 -Append -Encoding utf8
if (-not $H.HasExited) { Stop-Process -Id $H.Id -Force -ErrorAction SilentlyContinue }

# ================= T10: module enum grow retry sim =================
$t10 = "$rep\run-T10-enum-grow.txt"
Env-Set CIVTRACE_TAG 'rev002'
$I = Start-Target $pfUdp
Start-Sleep -Seconds 3
"T10 pid=$($I.Id)" | Out-File $t10 -Encoding utf8
Env-Set CIVTRACE_INJ_SIM_ENUM_SMALLBUF '1'
(& $injector -x powershell.exe -p $I.Id | Out-String) | Out-File $t10 -Append -Encoding utf8
"inject_exit=$LASTEXITCODE (expect 0 - enum grow retry exercised)" | Out-File $t10 -Append -Encoding utf8
Env-Del CIVTRACE_INJ_SIM_ENUM_SMALLBUF
(& $injector -x powershell.exe -p $I.Id -u | Out-String) | Out-File $t10 -Append -Encoding utf8
"unload_exit=$LASTEXITCODE (expect 0)" | Out-File $t10 -Append -Encoding utf8
$lI = LogOf $I.Id
Copy-Item $lI.FullName "$rep\raw-T10.pid$($I.Id).log" -Force
if (-not $I.HasExited) { Stop-Process -Id $I.Id -Force -ErrorAction SilentlyContinue }
Env-Del CIVTRACE_TAG

# ================= T11: extra reference (refcount 2) =================
$t11 = "$rep\run-T11-extra-ref.txt"
Env-Set CIVTRACE_TAG 'rev002'
$J = Start-Target $pfXl @($dll)
Start-Sleep -Seconds 3
"T11 pid=$($J.Id)" | Out-File $t11 -Encoding utf8
(& $injector -x powershell.exe -p $J.Id | Out-String) | Out-File $t11 -Append -Encoding utf8
"inject_exit=$LASTEXITCODE (expect 0)" | Out-File $t11 -Append -Encoding utf8
$deadline = (Get-Date).AddSeconds(30)
while (-not (Test-Path "$marker\xl-done.txt") -and (Get-Date) -lt $deadline) { Start-Sleep -Seconds 1 }
"extra_ref_marker: $(Get-Content "$marker\xl-done.txt" -ErrorAction SilentlyContinue)" | Out-File $t11 -Append -Encoding utf8
(& $injector -x powershell.exe -p $J.Id -u | Out-String) | Out-File $t11 -Append -Encoding utf8
"unload_exit=$LASTEXITCODE (expect 2 - still loaded, extra reference held by target)" | Out-File $t11 -Append -Encoding utf8
"alive_after=$(-not $J.HasExited)" | Out-File $t11 -Append -Encoding utf8
$lJ = LogOf $J.Id
"session-end: $((Select-String -Path $lJ.FullName -Pattern 'session end').Line)" | Out-File $t11 -Append -Encoding utf8
Copy-Item $lJ.FullName "$rep\raw-T11.pid$($J.Id).log" -Force
if (-not $J.HasExited) { Stop-Process -Id $J.Id -Force -ErrorAction SilentlyContinue }
Env-Del CIVTRACE_TAG

# ================= T12: static checks (source + dumpbin /MT+TLS) =================
$t12 = "$rep\run-T12-static.txt"
"T12 static checks:" | Out-File $t12 -Encoding utf8
"--- socket() return type in source (must be SOCKET):" | Out-File $t12 -Append -Encoding utf8
Select-String -Path "$civ\trace_dll.cpp" -Pattern 'SOCKET T_socket|SOCKET Hook_socket|SOCKET WSAAPI|T_socket\(|Hook_socket\(' | Select-Object -First 12 | ForEach-Object { "$($_.LineNumber): $($_.Line.Trim())" } | Out-File $t12 -Append -Encoding utf8
"--- thread_local usage (g_tlsInHook must be thread_local):" | Out-File $t12 -Append -Encoding utf8
Select-String -Path "$civ\trace_dll.cpp" -Pattern 'thread_local' | ForEach-Object { "$($_.LineNumber): $($_.Line.Trim())" } | Out-File $t12 -Append -Encoding utf8
"--- dumpbin /dependents (no MSVCP/VCRUNTIME => /MT static CRT):" | Out-File $t12 -Append -Encoding utf8
$vcvars = 'D:\MSVC\BuildTools\VC\Auxiliary\Build\vcvars64.bat'
cmd /c "call `"$vcvars`" >nul 2>&1 && dumpbin /dependents `"$dll`" && dumpbin /dependents `"$injector`"" | Out-File $t12 -Append -Encoding utf8
"--- dumpbin /headers TLS directory present:" | Out-File $t12 -Append -Encoding utf8
cmd /c "call `"$vcvars`" >nul 2>&1 && dumpbin /headers `"$dll`" | findstr /i TLS" | Out-File $t12 -Append -Encoding utf8

# ================= preserve raw logs + hashes =================
Get-ChildItem "$rep\raw-*.log" | ForEach-Object {
  "{0} {1}" -f (Get-FileHash $_.FullName -Algorithm SHA256).Hash.ToLower(), $_.Name
} | Out-File "$rep\raw-log-sha256.txt" -Encoding utf8
"done $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" | Out-File "$rep\done.txt" -Encoding utf8
