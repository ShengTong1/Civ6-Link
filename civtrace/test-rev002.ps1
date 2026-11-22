# test-rev002.ps1 - CivLink M0A REV-002 evidence collection (run as Administrator)
# Covers codex acceptance evidence 1-5 (R1 unload state machine, R2 lifecycle,
# R3 flusher fail-closed, R4/R5 injector diagnostics, R6 enum growth, error-code passthrough).
# Evidence goes to docs\reports\rev002\
$ErrorActionPreference = 'Continue'
$base = 'C:\Users\dd\Desktop\injciv6-v0.3.3\CivLink-M0A-audit'
$rep  = "$base\docs\reports\rev002"
$civ  = "$base\civtrace"
$injector = "$civ\civinject.exe"
$dllpath  = "$civ\civtrace.dll"

if (-not (Test-Path $injector)) { Write-Host "FATAL: injector missing: $injector"; exit 3 }
if (-not (Test-Path $dllpath))  { Write-Host "FATAL: dll missing: $dllpath"; exit 3 }

# Defender exclusion (works only elevated; the .cmd elevates first)
try { Add-MpPreference -ExclusionPath $civ -ErrorAction SilentlyContinue } catch {}
try { Add-MpPreference -ExclusionPath $rep -ErrorAction SilentlyContinue } catch {}

New-Item -ItemType Directory -Force -Path $rep | Out-Null
Get-ChildItem "$rep\run-*.txt" -ErrorAction SilentlyContinue | Remove-Item -Force

$os = Get-CimInstance Win32_OperatingSystem
$cs = Get-CimInstance Win32_ComputerSystem
"REV-002 evidence $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss K')" | Out-File "$rep\environment.txt" -Encoding utf8
"$($os.Caption) build $($os.BuildNumber) UBR $((Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').UBR)" | Out-File "$rep\environment.txt" -Append -Encoding utf8
"Admin: $(([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))  User: $env:USERNAME  Machine: $($cs.Name)" | Out-File "$rep\environment.txt" -Append -Encoding utf8
"Injector SHA256: $((Get-FileHash $injector -Algorithm SHA256).Hash.ToLower())" | Out-File "$rep\environment.txt" -Append -Encoding utf8
"DLL SHA256: $((Get-FileHash $dllpath -Algorithm SHA256).Hash.ToLower())" | Out-File "$rep\environment.txt" -Append -Encoding utf8

# ---------------- payloads ----------------
$tmp = Join-Path $env:TEMP 'civrev002'
New-Item -ItemType Directory -Force -Path $tmp | Out-Null

# p_udp: sustained UDP socket churn (recvfrom/sendto) so hooks fire repeatedly
$pUdp = @'
$s = New-Object Net.Sockets.Socket([Net.Sockets.AddressFamily]::InterNetwork,[Net.Sockets.SocketType]::Dgram,[Net.Sockets.ProtocolType]::Udp)
$s.Bind((New-Object Net.IPEndPoint([Net.IPAddress]::Any,0)))
$s.Blocking = $false
$ep = New-Object Net.IPEndPoint([Net.IPAddress]::Loopback,62056)
$buf = New-Object byte[] 120
for ($i=0; $i -lt 120; $i++) {
  try { $null = $s.SendTo($buf,$ep) } catch {}
  try { $null = $s.ReceiveFrom($buf,[ref]$ep) } catch {}
  Start-Sleep -m 100
}
$s.Close()
Start-Sleep -Seconds 1200
'@
# p_mt: in-process C# threads hammering ws2_32 socket()/closesocket() directly (B2 concurrency stress;
# direct P/Invoke stays in the target process, so MinHook intercepts every call)
$pMt = @'
Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Threading;
public static class Mt {
  [DllImport("ws2_32.dll")] public static extern IntPtr socket(int af, int type, int proto);
  [DllImport("ws2_32.dll")] public static extern int closesocket(IntPtr s);
  public static int Runs;
  public static void Loop() {
    for (int i = 0; i < 2000; i++) {
      IntPtr s = socket(2, 2, 17);          // AF_INET SOCK_DGRAM IPPROTO_UDP
      if (s != (IntPtr)(-1)) closesocket(s);
      Interlocked.Increment(ref Runs);      // per-iteration: reflects live hammering at marker time
      Thread.Sleep(5);
    }
  }
  public static void Start() {              // C#-internal threads: no PowerShell scriptblock delegates
    for (int i = 0; i < 8; i++) {
      Thread t = new Thread(new ThreadStart(Loop));
      t.IsBackground = true;
      t.Start();
    }
  }
}
"@
[Console]::Out.WriteLine("mt_csharp_ok")
[Mt]::Start()
Start-Sleep -Seconds 12
"mt_runs=$([Mt]::Runs)" | Out-File "$env:TEMP\civrev002\mt_marker.txt" -Encoding ascii
Start-Sleep -Seconds 1200
'@
# p_block: B1 test target — sleeps 2s (so injection lands first), then calls ws2_32 socket() DIRECTLY via
# P/Invoke (Hook_socket seam CIVTRACE_SIM_HOOK_BLOCK is consumed on that first call; .NET Socket would
# go through WSASocketW and never hit Hook_socket). Blocks 7s inside the first hooked socket() call.
$pBlock = @'
Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class Blk {
  [DllImport("ws2_32.dll")] public static extern IntPtr socket(int af, int type, int proto);
  [DllImport("ws2_32.dll")] public static extern int closesocket(IntPtr s);
}
"@
[Console]::Out.WriteLine("blk_csharp_ok")
"blk_ready" | Out-File "$env:TEMP\civrev002\blk_ready.txt" -Encoding ascii   # Add-Type done, waiting for injector
$go = "$env:TEMP\civrev002\blk_go.txt"
for ($i = 0; $i -lt 300 -and -not (Test-Path $go); $i++) { Start-Sleep -Milliseconds 100 }  # wait up to 30s for inject
$s = [Blk]::socket(2,2,17)      # AF_INET SOCK_DGRAM IPPROTO_UDP -> Hook_socket blocks 7s (seam, one-shot)
"blk_socket_done" | Out-File "$env:TEMP\civrev002\blk_done.txt" -Encoding ascii
if ($s -ne [IntPtr](-1)) { $null = [Blk]::closesocket($s) }
Start-Sleep -Seconds 1200
'@
# p_inv: invalid-pointer + WSAEnumNetworkEvents failure path (P0-9/P0-10 exercised from a real process)
$pInv = @'
$sig = @"
using System;
using System.Runtime.InteropServices;
public static class Inv {
  [DllImport("ws2_32.dll", SetLastError=true)] public static extern int setsockopt(IntPtr s, int level, int optname, IntPtr optval, int optlen);
  [DllImport("ws2_32.dll", SetLastError=true)] public static extern int ioctlsocket(IntPtr s, long cmd, ref int argp);
  [DllImport("ws2_32.dll", SetLastError=true)] public static extern int recvfrom(IntPtr s, byte[] buf, int len, int flags, byte[] from, ref int fromlen);
  [DllImport("ws2_32.dll", SetLastError=true)] public static extern int WSAEnumNetworkEvents(IntPtr s, IntPtr ev, byte[] ne);
}
"@
Add-Type -TypeDefinition $sig
$s = New-Object Net.Sockets.Socket([Net.Sockets.AddressFamily]::InterNetwork,[Net.Sockets.SocketType]::Dgram,[Net.Sockets.ProtocolType]::Udp)
$s.Bind((New-Object Net.IPEndPoint([Net.IPAddress]::Any,0)))
$h = $s.Handle
$z = [IntPtr]::Zero
$b = New-Object byte[] 16
$fl = 16
$r1 = [Inv]::setsockopt($h, 0xffff, 0xffff, $z, -1)              # invalid pointers
$r2 = [Inv]::ioctlsocket($h, 0x8004667e, [ref]$r1)
$r3 = [Inv]::recvfrom($h, $b, 16, 0, $b, [ref]$fl)
$r4 = [Inv]::WSAEnumNetworkEvents($h, $z, $b)                    # invalid event handle
"inv_marker: setsockopt=$r1 ioctlsocket=$r2 recvfrom=$r3 wsaenum=$r4" | Out-File "$env:TEMP\civrev002\inv_marker.txt" -Encoding ascii
$s.Close()
Start-Sleep -Seconds 1200
'@
# p_xl: payload takes an extra LoadLibraryW reference AFTER the injector loads,
# so refcount is 1 (injector) + 1 (payload); unload frees only the injector's ref.
$pXl = @'
Start-Sleep -Seconds 6
$dll = $args[0]
Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class K32 {
  [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
  public static extern IntPtr LoadLibraryW(string lpFileName);
}
"@
$h = [K32]::LoadLibraryW($dll)   # +1 ref beyond the injector's (PS 5.1 has no NativeLibrary)
"extra_ref_marker: $h" | Out-File "$env:TEMP\civrev002\extra_ref_marker.txt" -Encoding ascii
Start-Sleep -Seconds 1200
'@
# p_err: exact-error-code passthrough assertion (evidence 5: WSAGetLastError before/after hook)
$pErr = @'
$sig2 = @"
using System;
using System.Runtime.InteropServices;
public static class Err {
  [DllImport("ws2_32.dll", SetLastError=true)] public static extern int socket(int af, int type, int proto);
  [DllImport("ws2_32.dll", SetLastError=true)] public static extern int sendto(IntPtr s, byte[] buf, int len, int flags, byte[] to, int tolen);
  [DllImport("ws2_32.dll", SetLastError=true)] public static extern int WSAGetLastError();
}
"@
Add-Type -TypeDefinition $sig2
# create a real socket FIRST so Winsock is initialized on this thread,
# otherwise the first invalid-socket call would report 10093 (WSAENOTINITIALISED)
$s = New-Object Net.Sockets.Socket([Net.Sockets.AddressFamily]::InterNetwork,[Net.Sockets.SocketType]::Dgram,[Net.Sockets.ProtocolType]::Udp)
$s.Bind((New-Object Net.IPEndPoint([Net.IPAddress]::Any,0)))
$s.Blocking = $false
$ep = New-Object Net.IPEndPoint([Net.IPAddress]::Loopback,62056)
# baseline: read exact error from an invalid-socket sendto (expect WSAENOTSOCK 10038)
$rc = [Err]::sendto([IntPtr](-1), (New-Object byte[] 8), 8, 0, (New-Object byte[] 16), 16)
$e1 = [Err]::WSAGetLastError()
"err_baseline rc=$rc err=$e1" | Out-File "$env:TEMP\civrev002\err_marker.txt" -Encoding ascii
# now churn a real socket so hooks run, then repeat the same call and compare exact values
for ($i=0; $i -lt 40; $i++) { try { $null = $s.SendTo((New-Object byte[] 120),$ep) } catch {}; Start-Sleep -m 100 }
$rc2 = [Err]::sendto([IntPtr](-1), (New-Object byte[] 8), 8, 0, (New-Object byte[] 16), 16)
$e2 = [Err]::WSAGetLastError()
"err_after_hook rc=$rc2 err=$e2 equal=$($e1 -eq $e2)" | Out-File "$env:TEMP\civrev002\err_marker.txt" -Append -Encoding ascii
$s.Close()
Start-Sleep -Seconds 1200
'@

Set-Content -Path "$tmp\p_udp.ps1" -Value $pUdp -Encoding Ascii
Set-Content -Path "$tmp\p_mt.ps1"  -Value $pMt  -Encoding Ascii
Set-Content -Path "$tmp\p_inv.ps1" -Value $pInv -Encoding Ascii
Set-Content -Path "$tmp\p_xl.ps1"  -Value $pXl  -Encoding Ascii
Set-Content -Path "$tmp\p_err.ps1" -Value $pErr -Encoding Ascii
Set-Content -Path "$tmp\p_block.ps1" -Value $pBlock -Encoding Ascii
$pfUdp = "$tmp\p_udp.ps1"; $pfMt = "$tmp\p_mt.ps1"; $pfInv = "$tmp\p_inv.ps1"
$pfXl  = "$tmp\p_xl.ps1";  $pfErr = "$tmp\p_err.ps1"; $pfBlock = "$tmp\p_block.ps1"

# ---------------- helpers ----------------
$ap = "$env:LOCALAPPDATA\CivLink\M0A\logs"
function Start-Target([string]$pf, [string[]]$extra) {
  $a = @('-NoProfile','-ExecutionPolicy','Bypass','-File',$pf)
  if ($extra) { $a += $extra }
  $p = Start-Process powershell -WindowStyle Hidden -PassThru -ArgumentList $a
  Start-Sleep -Seconds 2
  if ($p.HasExited) { Write-Host "FATAL: target exited early (payload path?): $pf"; exit 4 }
  return $p
}
function Get-LogFor([int]$pid0) {
  $l = Get-ChildItem $ap -Filter "civtrace_*_pid$pid0*.log" | Sort-Object LastWriteTime | Select-Object -Last 1
  return $l
}
function Env-Set([string]$k, [string]$v) { Set-Item "Env:$k" $v }
function Env-Clear([string]$k) { Remove-Item "Env:$k" -ErrorAction SilentlyContinue }

# ---------------- T1: baseline inject + dup + unload (shutdown 0) ----------------
$A = Start-Target $pfUdp
"T1_pid=$($A.Id)" | Out-File "$rep\run-T1-baseline.txt" -Encoding utf8
$tA = (Get-Process -Id $A.Id).Threads.Count; $hA = (Get-Process -Id $A.Id).HandleCount
"threads_before=$tA handles_before=$hA" | Out-File "$rep\run-T1-baseline.txt" -Append -Encoding utf8
(& $injector -x powershell.exe -p $A.Id | Out-String) | Out-File "$rep\run-T1-baseline.txt" -Append -Encoding utf8
"exit=$LASTEXITCODE" | Out-File "$rep\run-T1-baseline.txt" -Append -Encoding utf8
Start-Sleep -Seconds 3
$la = Get-LogFor $A.Id
"hookline: $((Select-String -Path $la.FullName -Pattern 'hooks installed').Line)" | Out-File "$rep\run-T1-baseline.txt" -Append -Encoding utf8
$sz0 = $la.Length; Start-Sleep -Seconds 5
$sz1 = (Get-Item $la.FullName).Length
"liveflush size0=$sz0 size1=$sz1 grew=$($sz1-$sz0)" | Out-File "$rep\run-T1-baseline.txt" -Append -Encoding utf8
# dup
(& $injector -x powershell.exe -p $A.Id | Out-String) | Out-File "$rep\run-T1-baseline.txt" -Append -Encoding utf8
"dup_exit=$LASTEXITCODE (expect 0 skip)" | Out-File "$rep\run-T1-baseline.txt" -Append -Encoding utf8
# unload (shutdown code 0 -> B2 audit-run mode: no FreeLibrary, module left mapped until process exit)
(& $injector -x powershell.exe -p $A.Id -u | Out-String) | Out-File "$rep\run-T1-baseline.txt" -Append -Encoding utf8
"unload_exit=$LASTEXITCODE (expect 0: shutdown confirmed; module LEFT MAPPED by design)" | Out-File "$rep\run-T1-baseline.txt" -Append -Encoding utf8
Start-Sleep -Seconds 1
$tA3 = (Get-Process -Id $A.Id).Threads.Count; $hA3 = (Get-Process -Id $A.Id).HandleCount
"threads_after=$tA3 handles_after=$hA3" | Out-File "$rep\run-T1-baseline.txt" -Append -Encoding utf8
"module_left_mapped: $(((& $injector -x powershell.exe -p $A.Id 2>&1) | Out-String) -match 'already loaded') (expect True: -u leaves module mapped, re-inject reports dup)" | Out-File "$rep\run-T1-baseline.txt" -Append -Encoding utf8
"log_tail:" | Out-File "$rep\run-T1-baseline.txt" -Append -Encoding utf8
Get-Content $la.FullName -Tail 3 | Out-File "$rep\run-T1-baseline.txt" -Append -Encoding utf8

# ---------------- T2: abnormal kill (force-kill while injected) ----------------
$B = Start-Target $pfUdp
"T2_pid=$($B.Id)" | Out-File "$rep\run-T2-abnormal-kill.txt" -Encoding utf8
(& $injector -x powershell.exe -p $B.Id | Out-String) | Out-File "$rep\run-T2-abnormal-kill.txt" -Append -Encoding utf8
"exit=$LASTEXITCODE" | Out-File "$rep\run-T2-abnormal-kill.txt" -Append -Encoding utf8
Start-Sleep -Seconds 4
$lb = Get-LogFor $B.Id
$szb0 = $lb.Length; Start-Sleep -Seconds 5
$szb1 = (Get-Item $lb.FullName).Length
"log_before_kill size0=$szb0 size1=$szb1 grew=$($szb1-$szb0)" | Out-File "$rep\run-T2-abnormal-kill.txt" -Append -Encoding utf8
taskkill /F /PID $B.Id 2>&1 | Out-String | Out-File "$rep\run-T2-abnormal-kill.txt" -Append -Encoding utf8
Start-Sleep -Seconds 1
$szb2 = (Get-Item $lb.FullName).Length
$lastB = Get-Content $lb.FullName -Tail 1
"log_after_forcekill size=$szb2 lastline=[$lastB] (no session-end expected)" | Out-File "$rep\run-T2-abnormal-kill.txt" -Append -Encoding utf8

# ---------------- T3: double shutdown (R1 idempotence, second call code=1) ----------------
Env-Set 'CIVTRACE_INJ_TEST_DOUBLE_SHUTDOWN' '1'
$C = Start-Target $pfUdp
"T3_pid=$($C.Id)" | Out-File "$rep\run-T3-double-shutdown.txt" -Encoding utf8
(& $injector -x powershell.exe -p $C.Id | Out-String) | Out-File "$rep\run-T3-double-shutdown.txt" -Append -Encoding utf8
"inject_exit=$LASTEXITCODE (expect 0)" | Out-File "$rep\run-T3-double-shutdown.txt" -Append -Encoding utf8
(& $injector -x powershell.exe -p $C.Id -u | Out-String) | Out-File "$rep\run-T3-double-shutdown.txt" -Append -Encoding utf8
"unload_exit=$LASTEXITCODE (expect 0; second shutdown code=1 still confirms)" | Out-File "$rep\run-T3-double-shutdown.txt" -Append -Encoding utf8
Env-Clear 'CIVTRACE_INJ_TEST_DOUBLE_SHUTDOWN'

# ---------------- T4: GetExitCodeThread failure (R1: sim GEC fail -> shutdown NOT confirmed, abort) ----------------
Env-Set 'CIVTRACE_INJ_SIM_GEC_FAIL' '1'
$D = Start-Target $pfUdp
"T4_pid=$($D.Id)" | Out-File "$rep\run-T4-gec-fail.txt" -Encoding utf8
(& $injector -x powershell.exe -p $D.Id | Out-String) | Out-File "$rep\run-T4-gec-fail.txt" -Append -Encoding utf8
"inject_exit=$LASTEXITCODE (expect 0)" | Out-File "$rep\run-T4-gec-fail.txt" -Append -Encoding utf8
(& $injector -x powershell.exe -p $D.Id -u | Out-String) | Out-File "$rep\run-T4-gec-fail.txt" -Append -Encoding utf8
"first_unload_exit=$LASTEXITCODE (expect 2: shutdown NOT confirmed, abort per contract)" | Out-File "$rep\run-T4-gec-fail.txt" -Append -Encoding utf8
Env-Clear 'CIVTRACE_INJ_SIM_GEC_FAIL'
# shutdown was NOT confirmed on first attempt (aborted) -> normal -u now confirms
(& $injector -x powershell.exe -p $D.Id -u | Out-String) | Out-File "$rep\run-T4-gec-fail.txt" -Append -Encoding utf8
"second_unload_exit=$LASTEXITCODE (expect 0: retry confirms shutdown)" | Out-File "$rep\run-T4-gec-fail.txt" -Append -Encoding utf8

# ---------------- T5: disable-hook failure (R2: resources kept, retry works) ----------------
Env-Set 'CIVTRACE_SIM_DISABLE_FAIL' '1'
$E = Start-Target $pfUdp
"T5_pid=$($E.Id)" | Out-File "$rep\run-T5-disable-fail.txt" -Encoding utf8
(& $injector -x powershell.exe -p $E.Id | Out-String) | Out-File "$rep\run-T5-disable-fail.txt" -Append -Encoding utf8
"inject_exit=$LASTEXITCODE (expect 0)" | Out-File "$rep\run-T5-disable-fail.txt" -Append -Encoding utf8
(& $injector -x powershell.exe -p $E.Id -u | Out-String) | Out-File "$rep\run-T5-disable-fail.txt" -Append -Encoding utf8
"first_unload_exit=$LASTEXITCODE (expect 2: disable failed, DLL kept, no FreeLibrary)" | Out-File "$rep\run-T5-disable-fail.txt" -Append -Encoding utf8
Env-Clear 'CIVTRACE_SIM_DISABLE_FAIL'
(& $injector -x powershell.exe -p $E.Id -u | Out-String) | Out-File "$rep\run-T5-disable-fail.txt" -Append -Encoding utf8
"second_unload_exit=$LASTEXITCODE (expect 0: retry after failure completes shutdown)" | Out-File "$rep\run-T5-disable-fail.txt" -Append -Encoding utf8
# ---------------- T6: flusher creation failure (R3 fail-closed, hooks NOT installed) ----------------
Env-Set 'CIVTRACE_SIM_FLUSHER_FAIL' '1'
$F = Start-Target $pfUdp
"T6_pid=$($F.Id)" | Out-File "$rep\run-T6-flusher-fail.txt" -Encoding utf8
(& $injector -x powershell.exe -p $F.Id | Out-String) | Out-File "$rep\run-T6-flusher-fail.txt" -Append -Encoding utf8
"inject_exit=$LASTEXITCODE (expect 0; DLL loads but no hooks)" | Out-File "$rep\run-T6-flusher-fail.txt" -Append -Encoding utf8
Start-Sleep -Seconds 2
$lf = Get-LogFor $F.Id
"failclosed: $((Select-String -Path $lf.FullName -Pattern 'fail-closed').Line)" | Out-File "$rep\run-T6-flusher-fail.txt" -Append -Encoding utf8
"hooks_installed_count=$((Select-String -Path $lf.FullName -Pattern 'hooks installed').Count) (expect 0)" | Out-File "$rep\run-T6-flusher-fail.txt" -Append -Encoding utf8
Env-Clear 'CIVTRACE_SIM_FLUSHER_FAIL'
taskkill /F /PID $F.Id 2>&1 | Out-String | Out-File "$rep\run-T6-flusher-fail.txt" -Append -Encoding utf8
"killed (no unload: shutdown of FAILED state has no hooks to disable)" | Out-File "$rep\run-T6-flusher-fail.txt" -Append -Encoding utf8

# ---------------- T7: module enum growth (R6 SimSmallBuf -> grow+retry) ----------------
Env-Set 'CIVTRACE_INJ_SIM_ENUM_SMALLBUF' '1'
$G = Start-Target $pfUdp
"T7_pid=$($G.Id)" | Out-File "$rep\run-T7-enum-grow.txt" -Encoding utf8
(& $injector -x powershell.exe -p $G.Id | Out-String) | Out-File "$rep\run-T7-enum-grow.txt" -Append -Encoding utf8
"inject_exit=$LASTEXITCODE (expect 0: small buffer grown and retried)" | Out-File "$rep\run-T7-enum-grow.txt" -Append -Encoding utf8
Env-Clear 'CIVTRACE_INJ_SIM_ENUM_SMALLBUF'
(& $injector -x powershell.exe -p $G.Id -u | Out-String) | Out-File "$rep\run-T7-enum-grow.txt" -Append -Encoding utf8
"unload_exit=$LASTEXITCODE (expect 0)" | Out-File "$rep\run-T7-enum-grow.txt" -Append -Encoding utf8

# ---------------- T8: wrong-dll unload refusal (PE identity / export) ----------------
$H = Start-Target $pfUdp
"T8_pid=$($H.Id)" | Out-File "$rep\run-T8-wrong-dll.txt" -Encoding utf8
(& $injector -x powershell.exe -p $H.Id | Out-String) | Out-File "$rep\run-T8-wrong-dll.txt" -Append -Encoding utf8
"inject_exit=$LASTEXITCODE (expect 0)" | Out-File "$rep\run-T8-wrong-dll.txt" -Append -Encoding utf8
(& $injector -x powershell.exe -p $H.Id -u C:\Windows\System32\ws2_32.dll | Out-String) | Out-File "$rep\run-T8-wrong-dll.txt" -Append -Encoding utf8
"wrongdll_unload_exit=$LASTEXITCODE (expect 2: export not resolvable -> refuse)" | Out-File "$rep\run-T8-wrong-dll.txt" -Append -Encoding utf8
(& $injector -x powershell.exe -p $H.Id -u | Out-String) | Out-File "$rep\run-T8-wrong-dll.txt" -Append -Encoding utf8
"normal_unload_exit=$LASTEXITCODE (expect 0)" | Out-File "$rep\run-T8-wrong-dll.txt" -Append -Encoding utf8

# ---------------- T9: LoadLibraryW remote-thread timeout (P0-8: buffer kept) ----------------
Env-Set 'CIVTRACE_INJ_SIM_LOAD_TIMEOUT' '1'
$I = Start-Target $pfUdp
"T9_pid=$($I.Id)" | Out-File "$rep\run-T9-load-timeout.txt" -Encoding utf8
(& $injector -x powershell.exe -p $I.Id | Out-String) | Out-File "$rep\run-T9-load-timeout.txt" -Append -Encoding utf8
"inject_exit=$LASTEXITCODE (expect 2: not confirmed -> ABORT, buffer left)" | Out-File "$rep\run-T9-load-timeout.txt" -Append -Encoding utf8
Env-Clear 'CIVTRACE_INJ_SIM_LOAD_TIMEOUT'

# ---------------- T10: arch query failure (R5 fail-closed) ----------------
Env-Set 'CIVTRACE_INJ_SIM_ARCH_FAIL' '1'
$J = Start-Target $pfUdp
"T10_pid=$($J.Id)" | Out-File "$rep\run-T10-arch-fail.txt" -Encoding utf8
(& $injector -x powershell.exe -p $J.Id | Out-String) | Out-File "$rep\run-T10-arch-fail.txt" -Append -Encoding utf8
"inject_exit=$LASTEXITCODE (expect 2: architecture UNDETERMINED -> refuse)" | Out-File "$rep\run-T10-arch-fail.txt" -Append -Encoding utf8
Env-Clear 'CIVTRACE_INJ_SIM_ARCH_FAIL'
# target was never injected; verify normal path still works on it
(& $injector -x powershell.exe -p $J.Id | Out-String) | Out-File "$rep\run-T10-arch-fail.txt" -Append -Encoding utf8
"normal_inject_exit=$LASTEXITCODE (expect 0)" | Out-File "$rep\run-T10-arch-fail.txt" -Append -Encoding utf8
(& $injector -x powershell.exe -p $J.Id -u | Out-String) | Out-File "$rep\run-T10-arch-fail.txt" -Append -Encoding utf8
"unload_exit=$LASTEXITCODE (expect 0)" | Out-File "$rep\run-T10-arch-fail.txt" -Append -Encoding utf8

# ---------------- T11: extra reference (B2 audit-run mode: module left mapped regardless; shutdown must still confirm) ----------------
$K = Start-Target $pfXl @($dllpath)
"T11_pid=$($K.Id)" | Out-File "$rep\run-T11-extra-ref.txt" -Encoding utf8
# inject first (payload takes its extra ref at t+6s)
(& $injector -x powershell.exe -p $K.Id | Out-String) | Out-File "$rep\run-T11-extra-ref.txt" -Append -Encoding utf8
"inject_exit=$LASTEXITCODE (expect 0)" | Out-File "$rep\run-T11-extra-ref.txt" -Append -Encoding utf8
Start-Sleep -Seconds 8
"extra_ref_marker: $(Get-Content "$tmp\extra_ref_marker.txt" -ErrorAction SilentlyContinue)" | Out-File "$rep\run-T11-extra-ref.txt" -Append -Encoding utf8
(& $injector -x powershell.exe -p $K.Id -u | Out-String) | Out-File "$rep\run-T11-extra-ref.txt" -Append -Encoding utf8
"unload_exit=$LASTEXITCODE (expect 0: extra ref present, shutdown still confirms; no FreeLibrary attempted under B2 mode)" | Out-File "$rep\run-T11-extra-ref.txt" -Append -Encoding utf8

# ---------------- T12: exact error-code passthrough (evidence 5) ----------------
$L = Start-Target $pfErr
"T12_pid=$($L.Id)" | Out-File "$rep\run-T12-err-passthrough.txt" -Encoding utf8
Start-Sleep -Seconds 2
"baseline: $(Get-Content "$tmp\err_marker.txt" -ErrorAction SilentlyContinue | Select-Object -First 1)" | Out-File "$rep\run-T12-err-passthrough.txt" -Append -Encoding utf8
(& $injector -x powershell.exe -p $L.Id | Out-String) | Out-File "$rep\run-T12-err-passthrough.txt" -Append -Encoding utf8
"inject_exit=$LASTEXITCODE (expect 0)" | Out-File "$rep\run-T12-err-passthrough.txt" -Append -Encoding utf8
Start-Sleep -Seconds 8
"after_hook: $(Get-Content "$tmp\err_marker.txt" -ErrorAction SilentlyContinue | Select-Object -Last 1)" | Out-File "$rep\run-T12-err-passthrough.txt" -Append -Encoding utf8
(& $injector -x powershell.exe -p $L.Id -u | Out-String) | Out-File "$rep\run-T12-err-passthrough.txt" -Append -Encoding utf8
"unload_exit=$LASTEXITCODE (expect 0)" | Out-File "$rep\run-T12-err-passthrough.txt" -Append -Encoding utf8

# ---------------- T13: static checks (evidence 2/3/4 supplements) ----------------
$t13 = "$rep\run-T13-static.txt"
"t_socket_decl=$((Select-String -Path "$civ\trace_dll.cpp" -Pattern 'typedef SOCKET \(WSAAPI \*T_socket\)').Count) (expect 1)" | Out-File $t13 -Encoding utf8
"hook_socket_decl=$((Select-String -Path "$civ\trace_dll.cpp" -Pattern 'static SOCKET WSAAPI Hook_socket').Count)" | Out-File $t13 -Append -Encoding utf8
"thread_local=$((Select-String -Path "$civ\trace_dll.cpp" -Pattern 'thread_local').Count)" | Out-File $t13 -Append -Encoding utf8
"g_inFlight_refs=$((Select-String -Path "$civ\trace_dll.cpp" -Pattern 'g_inFlight').Count)" | Out-File $t13 -Append -Encoding utf8
"g_inHook_residual=$((Select-String -Path "$civ\trace_dll.cpp" -Pattern 'g_inHook').Count) (expect 0)" | Out-File $t13 -Append -Encoding utf8
"findpids_dynamic=$((Select-String -Path "$civ\injector.cpp" -Pattern 'std::vector<DWORD>& out').Count) (expect 1)" | Out-File $t13 -Append -Encoding utf8
$dump = Get-ChildItem 'D:\MSVC\BuildTools' -Recurse -Filter dumpbin.exe -ErrorAction SilentlyContinue | Select-Object -First 1
if ($dump) {
  & $dump.FullName /dependents $injector 2>&1 | Select-String 'MSVCP|VCRUNTIME' | Out-File $t13 -Append -Encoding utf8
  "dumpbin_msvcp_vcruntime_lines=$((Select-String -Path $t13 -Pattern 'MSVCP|VCRUNTIME').Count) (expect 0 = /MT static CRT)" | Out-File $t13 -Append -Encoding utf8
} else {
  "dumpbin not found under D:\MSVC\BuildTools" | Out-File $t13 -Append -Encoding utf8
}

# ---------------- T14: B1 drain-timeout — closing chain ABORTED, resources kept, retry succeeds ----------------
# CIVTRACE_SIM_HOOK_BLOCK=1: Hook_socket blocks 7s on the payload's first socket call,
# so the in-flight count stays >0 while Shutdown runs -> 5s drain deadline -> abort (exit2),
# then the socket unblocks and a retry Shutdown completes the shutdown (exit0; module left mapped by B2 mode).
Set-Item "Env:CIVTRACE_SIM_HOOK_BLOCK" "1"   # MUST be set BEFORE Start-Target: payload inherits it; seam consumed on first socket() after inject
Remove-Item "$tmp\blk_ready.txt","$tmp\blk_go.txt","$tmp\blk_done.txt" -ErrorAction SilentlyContinue
$M = Start-Target $pfBlock
"T14_pid=$($M.Id)" | Out-File "$rep\run-T14-b1-timeout.txt" -Encoding utf8
# wait for Add-Type compile to finish (blk_ready), THEN inject (hooks installed while payload waits for blk_go)
$ready = "$tmp\blk_ready.txt"
for ($i = 0; $i -lt 150 -and -not (Test-Path $ready); $i++) { Start-Sleep -Milliseconds 100 }
"blk_ready_seen=$(Test-Path $ready)" | Out-File "$rep\run-T14-b1-timeout.txt" -Append -Encoding utf8
(& $injector -x powershell.exe -p $M.Id | Out-String) | Out-File "$rep\run-T14-b1-timeout.txt" -Append -Encoding utf8
"inject_exit=$LASTEXITCODE (expect 0)" | Out-File "$rep\run-T14-b1-timeout.txt" -Append -Encoding utf8
Remove-Item "Env:CIVTRACE_SIM_HOOK_BLOCK" -ErrorAction SilentlyContinue
# release the payload's socket() call (goes through hooked Hook_socket, blocks 7s), then unload DURING the block
Set-Content -Path "$tmp\blk_go.txt" -Value "go" -Encoding ascii
Start-Sleep -Seconds 1
(& $injector -x powershell.exe -p $M.Id -u | Out-String) | Out-File "$rep\run-T14-b1-timeout.txt" -Append -Encoding utf8
"first_unload_exit=$LASTEXITCODE (expect 2: drain timeout, chain aborted, resources kept)" | Out-File "$rep\run-T14-b1-timeout.txt" -Append -Encoding utf8
"still_alive_after_timeout=$(-not $M.HasExited)" | Out-File "$rep\run-T14-b1-timeout.txt" -Append -Encoding utf8
Start-Sleep -Seconds 10   # socket unblocks (~7s), in-flight drains to 0
(& $injector -x powershell.exe -p $M.Id -u | Out-String) | Out-File "$rep\run-T14-b1-timeout.txt" -Append -Encoding utf8
"second_unload_exit=$LASTEXITCODE (expect 0: retry completes shutdown)" | Out-File "$rep\run-T14-b1-timeout.txt" -Append -Encoding utf8
"blk_socket_done=$(Test-Path "$tmp\blk_done.txt") (expect True: blocked socket eventually returned)" | Out-File "$rep\run-T14-b1-timeout.txt" -Append -Encoding utf8
$lM = Get-LogFor $M.Id
if ($lM) {
  "timeout_line: $((Select-String -Path $lM.FullName -Pattern 'did NOT drain within 5s').Count) (expect 1)" | Out-File "$rep\run-T14-b1-timeout.txt" -Append -Encoding utf8
  "session_end: $((Select-String -Path $lM.FullName -Pattern 'session end').Count) (expect 1)" | Out-File "$rep\run-T14-b1-timeout.txt" -Append -Encoding utf8
}

# ---------------- T15: B2 concurrent shutdown — shutdown while 8 threads hammer socket() ----------------
$N = Start-Target $pfMt
"T15_pid=$($N.Id)" | Out-File "$rep\run-T15-b2-concurrent.txt" -Encoding utf8
Start-Sleep -Seconds 4    # let Add-Type compile + threads start
(& $injector -x powershell.exe -p $N.Id | Out-String) | Out-File "$rep\run-T15-b2-concurrent.txt" -Append -Encoding utf8
"inject_exit=$LASTEXITCODE (expect 0)" | Out-File "$rep\run-T15-b2-concurrent.txt" -Append -Encoding utf8
Start-Sleep -Seconds 2
(& $injector -x powershell.exe -p $N.Id -u | Out-String) | Out-File "$rep\run-T15-b2-concurrent.txt" -Append -Encoding utf8
"unload_exit=$LASTEXITCODE (expect 0: shutdown under concurrent hook activity)" | Out-File "$rep\run-T15-b2-concurrent.txt" -Append -Encoding utf8
"still_alive=$(-not $N.HasExited)" | Out-File "$rep\run-T15-b2-concurrent.txt" -Append -Encoding utf8
$mtm = "$tmp\mt_marker.txt"
for ($i = 0; $i -lt 150 -and -not (Test-Path $mtm); $i++) { Start-Sleep -Milliseconds 100 }
"mt_runs: $(Get-Content $mtm -ErrorAction SilentlyContinue)" | Out-File "$rep\run-T15-b2-concurrent.txt" -Append -Encoding utf8
$lN = Get-LogFor $N.Id
if ($lN) {
  "session_end: $((Select-String -Path $lN.FullName -Pattern 'session end').Count) (expect 1)" | Out-File "$rep\run-T15-b2-concurrent.txt" -Append -Encoding utf8
}

# ---------------- preserve raw logs + hashes ----------------
Get-ChildItem $ap -Filter 'civtrace_*.log' | Sort-Object LastWriteTime | Select-Object -Last 16 | ForEach-Object {
  Copy-Item $_.FullName "$rep\raw-$($_.LastWriteTime.ToString('HHmmss'))-pid$($_.Name.Substring($_.Name.IndexOf('pid')+3).Replace('.log','')).log" -Force -ErrorAction SilentlyContinue
}
Get-FileHash $la.FullName, $lb.FullName, $lf.FullName -Algorithm SHA256 -ErrorAction SilentlyContinue | ForEach-Object {
  "{0} {1}" -f $_.Hash.ToLower(), (Split-Path $_.Path -Leaf)
} | Out-File "$rep\raw-log-sha256.txt" -Encoding utf8

foreach ($p in @($A,$B,$C,$D,$E,$F,$G,$H,$I,$J,$K,$L,$M,$N)) {
  if ($p -and -not $p.HasExited) { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue }
}
"done $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" | Out-File "$rep\done.txt" -Encoding utf8
