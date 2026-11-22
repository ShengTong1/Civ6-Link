# run-logbound-selftest.ps1 -- CivLink M0-A civtrace v0.4.5 log-volume bound self-test
#
# Purpose: prove the fix for the "log exploded to 15.4 GB" defect. The defect was that
# civtrace.dll emitted one line for every hooked Winsock call, and Civ6's data-plane socket
# busy-polls WSARecvFrom at roughly 1.6 M calls/s, so one 20-minute session produced 15.4 GB.
#
# v0.4.5 bounds that: a socket is "discovery" when it binds/sends to 255.255.255.255 or to
# 62900-62999; discovery sockets are logged in full (they are the evidence we need), every
# other socket is logged at most once per 200 ms, and the skips are counted in the
# "session end ... throttled=N" line.
#
# The payload (injected process) does, in order: 100 broadcast datagrams to
# 255.255.255.255:62900-62999 (must be recorded in full), then a non-blocking recvfrom busy
# loop on a non-discovery socket for 10 s (must be throttled).
#
# Exit: 0 = all checks passed, 1 = at least one check failed, 2 = setup failure.
# Run elevated (civinject needs admin); this script re-launches itself through UAC once.
$ErrorActionPreference = 'Continue'

$base = 'C:\Users\dd\Desktop\injciv6-v0.3.3\CivLink-M0A-audit'
$civ  = "$base\civtrace"
$injector = "$civ\civinject.exe"
$dllpath  = "$civ\civtrace.dll"
$out  = "$base\docs\reports\logbound"

if (-not (Test-Path $injector)) { Write-Host "FATAL: injector missing: $injector"; exit 2 }
if (-not (Test-Path $dllpath))  { Write-Host "FATAL: dll missing: $dllpath"; exit 2 }

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "[*] not elevated - relaunching through UAC ..."
    $psi = New-Object Diagnostics.ProcessStartInfo
    $psi.FileName = 'powershell.exe'
    $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    $psi.UseShellExecute = $true
    $psi.Verb = 'runas'
    $p = [Diagnostics.Process]::Start($psi)
    $p.WaitForExit()
    exit $p.ExitCode
}

$DurationMs = 10000          # busy-poll window (mimics Civ6 data-plane socket)
$ThrottleMs = 200            # must match kThrottleMs in trace_dll.cpp
$BoundBytes = 4MB            # log size ceiling for the whole window (v0.4.4 was ~GB)
$LogDir = Join-Path $env:LOCALAPPDATA 'CivLink\M0A\logs'

New-Item -ItemType Directory -Force -Path $out | Out-Null
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$rep = Join-Path $out "run-$stamp"
New-Item -ItemType Directory -Force -Path $rep | Out-Null
$resultFile = Join-Path $rep 'result.txt'
function Log([string]$s) { $s | Tee-Object -FilePath $resultFile -Append }

try { Add-MpPreference -ExclusionPath $civ -ErrorAction SilentlyContinue } catch {}
try { Add-MpPreference -ExclusionPath $rep -ErrorAction SilentlyContinue } catch {}

$checks = 0
$fails = New-Object System.Collections.ArrayList
function Check([string]$name, [bool]$cond, [string]$detail) {
    $script:checks++
    if ($cond) { Log ("PASS {0} ({1})" -f $name, $detail) }
    else       { [void]$script:fails.Add($name); Log ("FAIL {0} ({1})" -f $name, $detail) }
}

Log "civtrace log-volume bound self-test $stamp"
Log "dll_sha256=$((Get-FileHash $dllpath -Algorithm SHA256).Hash.ToLower())"
Log "injector_sha256=$((Get-FileHash $injector -Algorithm SHA256).Hash.ToLower())"
Log "window_ms=$DurationMs throttle_ms=$ThrottleMs bound_bytes=$BoundBytes"

# ---------- payload: broadcast burst + busy non-blocking recvfrom, inside the target process ----------
$tmp = Join-Path $env:TEMP 'civlogbound'
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
Remove-Item "$tmp\*.txt" -Force -ErrorAction SilentlyContinue
$pBusy = @'
Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class Busy {
  [DllImport("ws2_32.dll", SetLastError=true)] public static extern IntPtr socket(int af, int type, int proto);
  [DllImport("ws2_32.dll", SetLastError=true)] public static extern int bind(IntPtr s, byte[] name, int len);
  [DllImport("ws2_32.dll", SetLastError=true)] public static extern int setsockopt(IntPtr s, int level, int optname, ref int optval, int optlen);
  [DllImport("ws2_32.dll", SetLastError=true)] public static extern int ioctlsocket(IntPtr s, long cmd, ref int argp);
  [DllImport("ws2_32.dll", SetLastError=true)] public static extern int recvfrom(IntPtr s, byte[] buf, int len, int flags, byte[] from, ref int fromlen);
  [DllImport("ws2_32.dll", SetLastError=true)] public static extern int sendto(IntPtr s, byte[] buf, int len, int flags, byte[] to, int tolen);
  [DllImport("ws2_32.dll", SetLastError=true)] public static extern int WSAStartup(ushort ver, IntPtr data);
  [DllImport("ws2_32.dll")] public static extern int WSAGetLastError();
  public static long Calls;
  public static int Burst;
  public static string Note = "";

  public static void Init() {              // raw ws2_32 P/Invoke needs WSAStartup (PowerShell host has not called it)
    IntPtr p = Marshal.AllocHGlobal(512);
    int rc = WSAStartup(0x0202, p);
    Marshal.FreeHGlobal(p);
    Note = "wsa_startup=" + rc;
  }

  // one datagram to 255.255.255.255:<port>, four-byte Civ6 discovery magic
  static int SendDisc(IntPtr s, int port) {
    byte[] to = new byte[16];
    to[0] = 2;                       // AF_INET
    to[2] = (byte)((port >> 8) & 0xFF);
    to[3] = (byte)(port & 0xFF);
    to[4] = 255; to[5] = 255; to[6] = 255; to[7] = 255;   // INADDR_BROADCAST
    byte[] m = new byte[4]; m[0] = 0x8D; m[1] = 0xE8; m[2] = 0xFC; m[3] = 0x70;
    return sendto(s, m, 4, 0, to, 16);
  }

  public static void Burst100() {
    IntPtr s = socket(2, 2, 17);
    if (s == (IntPtr)(-1)) { Burst = -1; Note += " burst_sock_err=" + WSAGetLastError(); return; }
    byte[] sa = new byte[16]; sa[0] = 2;
    bind(s, sa, 16);
    int on = 1;
    setsockopt(s, 0xFFFF, 0x20, ref on, 4);      // SOL_SOCKET, SO_BROADCAST
    int ok = 0;
    for (int p = 62900; p <= 62999; p++) { if (SendDisc(s, p) == 4) ok++; }
    Burst = ok;
  }

  public static void Run(int ms) {
    IntPtr s = socket(2, 2, 17);                 // AF_INET SOCK_DGRAM IPPROTO_UDP
    if (s == (IntPtr)(-1)) { Calls = -1; Note += " busy_sock_err=" + WSAGetLastError(); return; }
    byte[] sa = new byte[16]; sa[0] = 2;         // port 0 -> ephemeral (not a discovery socket)
    bind(s, sa, 16);
    int nb = 1;
    ioctlsocket(s, unchecked((long)0x8004667E), ref nb);   // FIONBIO (non-blocking)
    byte[] buf = new byte[120];
    byte[] from = new byte[16];
    int fl = 16;
    var sw = System.Diagnostics.Stopwatch.StartNew();
    long n = 0;
    while (sw.ElapsedMilliseconds < ms) {
      recvfrom(s, buf, 120, 0, from, ref fl);    // WSAEWOULDBLOCK each time -> Hook_recvfrom
      fl = 16;
      n++;
    }
    Calls = n;
  }
}
"@
[Busy]::Init()
"busy_ready note=$([Busy]::Note)" | Out-File "$env:TEMP\civlogbound\busy_ready.txt" -Encoding ascii
$go = "$env:TEMP\civlogbound\busy_go.txt"
for ($i = 0; $i -lt 300 -and -not (Test-Path $go); $i++) { Start-Sleep -Milliseconds 100 }   # wait for injection
[Busy]::Burst100()
"burst=$([Busy]::Burst)" | Out-File "$env:TEMP\civlogbound\burst_done.txt" -Encoding ascii
[Busy]::Run(__MS__)
"calls=$([Busy]::Calls)" | Out-File "$env:TEMP\civlogbound\busy_done.txt" -Encoding ascii
Start-Sleep -Seconds 900
'@
$pBusy = $pBusy.Replace('__MS__', [string]$DurationMs)
$payloadPath = Join-Path $tmp 'busy_payload.ps1'
[IO.File]::WriteAllText($payloadPath, $pBusy, (New-Object Text.UTF8Encoding($true)))

$psi = New-Object Diagnostics.ProcessStartInfo
$psi.FileName = 'powershell.exe'
$psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$payloadPath`""
$psi.UseShellExecute = $false
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
$payload = [Diagnostics.Process]::Start($psi)
Log "payload_pid=$($payload.Id)"

for ($i = 0; $i -lt 300 -and -not (Test-Path "$tmp\busy_ready.txt"); $i++) { Start-Sleep -Milliseconds 100 }
Check 'payload_ready' (Test-Path "$tmp\busy_ready.txt") "ready_file=$((Test-Path "$tmp\busy_ready.txt"))"

# ---------- inject ----------
$injOut = (& $injector -x powershell.exe -p $payload.Id 2>&1 | Out-String)
$injExit = $LASTEXITCODE
Log $injOut.Trim()
Log "inject_exit=$injExit"
Check 'A1 inject exit 0' ($injExit -eq 0) "exit=$injExit"

$logFile = $null
for ($i = 0; $i -lt 50 -and -not $logFile; $i++) {
    Start-Sleep -Milliseconds 200
    $logFile = Get-ChildItem $LogDir -Filter "civtrace_*_pid$($payload.Id)*.log" -ErrorAction SilentlyContinue |
               Sort-Object LastWriteTime -Descending | Select-Object -First 1
}
Check 'A2 log file created' ($null -ne $logFile) "path=$($logFile.FullName)"

# hooks-installed line is written by the DLL (not by the injector), so read it from the log.
# The DLL keeps the log open for writing, so a plain [IO.File]::ReadAllText (FileShare.Read)
# can raise "file in use"; with $ErrorActionPreference='Continue' that exception silently left
# $t=$null and burned the whole poll window (that was the first-run A3 failure). Read through a
# FileStream that shares read+write, and surface any exception text in the check detail.
function Read-Shared([string]$path) {
    $fs = [IO.File]::Open($path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
    try {
        $sr = New-Object IO.StreamReader($fs, [Text.Encoding]::UTF8)
        return $sr.ReadToEnd()
    } finally { $fs.Dispose() }
}
$hooksLine = $false
$a3len = -1; $a3err = ''
for ($i = 0; $i -lt 100 -and -not $hooksLine; $i++) {
    Start-Sleep -Milliseconds 200
    if ($logFile) {
        try {
            $t = Read-Shared $logFile.FullName
            $a3len = $t.Length
            $hooksLine = $t -match 'hooks installed ok=31 fail=0'
        } catch { $a3err = $_.Exception.Message }
    }
}
Check 'A3 hooks installed ok=31' ($hooksLine -eq $true) "matched=$hooksLine len=$a3len err=$a3err"

# ---------- drive the payload: broadcast burst, then the busy window ----------
"go" | Out-File "$tmp\busy_go.txt" -Encoding ascii
for ($i = 0; $i -lt 300 -and -not (Test-Path "$tmp\burst_done.txt"); $i++) { Start-Sleep -Milliseconds 200 }
$burst = 0
if (Test-Path "$tmp\burst_done.txt") {
    $mb = [regex]::Match((Get-Content "$tmp\burst_done.txt" -Raw), 'burst=(\d+)')
    if ($mb.Success) { $burst = [int]$mb.Groups[1].Value }
}
Log "payload_burst_reported=$burst"

for ($i = 0; $i -lt 900 -and -not (Test-Path "$tmp\busy_done.txt"); $i++) { Start-Sleep -Milliseconds 200 }
$calls = 0
if (Test-Path "$tmp\busy_done.txt") {
    $m = [regex]::Match((Get-Content "$tmp\busy_done.txt" -Raw), 'calls=(\d+)')
    if ($m.Success) { $calls = [long]$m.Groups[1].Value }
}
Log "busy_calls=$calls busy_seconds=$([math]::Round($DurationMs/1000,1))"

# ---------- measure size, then unload (the DLL holds the file open while running) ----------
Start-Sleep -Milliseconds 800
$logSize = (Get-Item $logFile.FullName).Length
Log "log_bytes_during_session=$logSize"

$unOut = (& $injector -x powershell.exe -p $payload.Id -u 2>&1 | Out-String)
$unExit = $LASTEXITCODE
Log $unOut.Trim()
Log "unload_exit=$unExit"
Check 'A8 unload exit 0' ($unExit -eq 0) "exit=$unExit"

function Count-Lines([string]$path, [string]$pattern) {
    $n = 0
    $sr = New-Object IO.StreamReader($path, [Text.Encoding]::UTF8)
    try {
        while (-not $sr.EndOfStream) {
            $l = $sr.ReadLine()
            if ($l.Length -gt 0 -and $l.Contains($pattern)) { $n++ }
        }
    } finally { $sr.Close() }
    return $n
}
$bcastLines = Count-Lines $logFile.FullName 'dst=255.255.255.255:629'
$busyLines  = Count-Lines $logFile.FullName 'recvfrom s='
$sessLine   = $null
$sr = New-Object IO.StreamReader($logFile.FullName, [Text.Encoding]::UTF8)
try { while (-not $sr.EndOfStream) { $l = $sr.ReadLine(); if ($l.Contains('session end')) { $sessLine = $l } } } finally { $sr.Close() }
Log "broadcast_lines=$bcastLines recv_lines=$busyLines"
Log "session_end_line=$sessLine"

$maxBusy = [math]::Ceiling($DurationMs / $ThrottleMs) + 5
Check 'A4 all 100 broadcast sends recorded' ($bcastLines -eq 100) "broadcast_lines=$bcastLines expect 100"
Check 'A5 busy socket lines bounded by window' ($busyLines -le $maxBusy) "recv_lines=$busyLines max=$maxBusy"
Check 'A6 log size bounded' ($logSize -lt $BoundBytes) "bytes=$logSize bound=$BoundBytes"

$mTh = [regex]::Match([string]$sessLine, 'throttled=(\d+)')
Check 'A9 session end carries throttled counter' ($mTh.Success) "found=$($mTh.Success)"
if ($mTh.Success) {
    $throttled = [long]$mTh.Groups[1].Value
    Log "throttled=$throttled"
    Check 'A10 throttled counter large' ($throttled -gt 10000) "throttled=$throttled expect >10000"
    if ($calls -gt 0) {
        $delta = [math]::Abs(($throttled + $busyLines) - $calls)
        $tol = [math]::Max(1000, [math]::Ceiling($calls * 0.02))
        Check 'A11 throttled + recorded reconciles with call count' ($delta -le $tol) "delta=$delta tol=$tol calls=$calls throttled=$throttled recorded=$busyLines"
    }
}
$rate = if ($DurationMs -gt 0) { [math]::Round($logSize / ($DurationMs / 1000.0), 1) } else { 0 }
Log "bytes_per_second=$rate (v0.4.4 unbounded: one line per call)"
Log "checks=$checks failures=$($fails.Count)"
foreach ($f in $fails) { Log "failed_check=$f" }
Copy-Item $logFile.FullName (Join-Path $rep ("raw-" + ($logFile.LastWriteTime.ToString('HHmmss')) + "-pid$($payload.Id).log")) -Force -ErrorAction SilentlyContinue
Get-FileHash $dllpath, $injector, $logFile.FullName -Algorithm SHA256 |
    ForEach-Object { "{0} {1}" -f $_.Hash.ToLower(), (Split-Path $_.Path -Leaf) } |
    Out-File (Join-Path $rep 'sha256.txt') -Encoding utf8

if ($payload -and -not $payload.HasExited) { Stop-Process -Id $payload.Id -Force -ErrorAction SilentlyContinue }
try { Remove-MpPreference -ExclusionPath $civ -ErrorAction SilentlyContinue } catch {}

if ($fails.Count -eq 0) { Log "LOGBOUND-SELFTEST: PASS ($checks/$checks)"; exit 0 }
Log "LOGBOUND-SELFTEST: FAIL ($($checks - $fails.Count)/$checks)"; exit 1
