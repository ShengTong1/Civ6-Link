# test-rev001.ps1 v2 - CivLink M0A REV-001 evidence collection (run as Administrator)
# Final-binary evidence pass: T1..T6 (+T6b). Outputs into docs\reports\rev001\
$ErrorActionPreference = 'Continue'
$base = 'C:\Users\dd\Desktop\injciv6-v0.3.3\CivLink-M0A-audit'
$rep  = "$base\docs\reports\rev001"
$civ  = "$base\civtrace"
$old  = "$rep\run1-*.txt"
Remove-Item $old -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $rep | Out-Null
$injector = "$civ\civinject.exe"

$os = Get-CimInstance Win32_OperatingSystem
$cs = Get-CimInstance Win32_ComputerSystem
"run2 final binary: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss K')" | Out-File "$rep\environment.txt" -Encoding utf8
"$($os.Caption) build $($os.BuildNumber) UBR $((Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').UBR)" | Out-File "$rep\environment.txt" -Append -Encoding utf8
"Admin: $(([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))  User: $env:USERNAME  Machine: $($cs.Name)" | Out-File "$rep\environment.txt" -Append -Encoding utf8
"Injector SHA256: $((Get-FileHash $injector -Algorithm SHA256).Hash.ToLower())" | Out-File "$rep\environment.txt" -Append -Encoding utf8
"DLL SHA256: $((Get-FileHash "$civ\civtrace.dll" -Algorithm SHA256).Hash.ToLower())" | Out-File "$rep\environment.txt" -Append -Encoding utf8

$payload = `
'$s=New-Object Net.Sockets.Socket([Net.Sockets.AddressFamily]::InterNetwork,[Net.Sockets.SocketType]::Dgram,[Net.Sockets.ProtocolType]::Udp);' + `
'$s.Bind((New-Object Net.IPEndPoint([Net.IPAddress]::Any,0)));$s.Blocking=$false;' + `
'$ep=New-Object Net.IPEndPoint([Net.IPAddress]::Loopback,62056);$buf=New-Object byte[] 120;' + `
'for($i=0;$i -lt 150;$i++){try{$null=$s.SendTo($buf,$ep)}catch{};try{$null=$s.ReceiveFrom($buf,[ref]$ep)}catch{};Start-Sleep -m 120};' + `
'$s.Close();Start-Sleep -Seconds 900'

# ---------- T1: inject + 31/31 + live flush growth ----------
$A = Start-Process powershell -WindowStyle Hidden -PassThru -ArgumentList '-NoProfile','-Command',$payload
Start-Sleep -Seconds 2
"A_pid=$($A.Id)" | Out-File "$rep\run2-T1-inject.txt" -Encoding utf8
$tA = (Get-Process -Id $A.Id).Threads.Count; $hA = (Get-Process -Id $A.Id).HandleCount
"threads_before=$tA handles_before=$hA" | Out-File "$rep\run2-T1-inject.txt" -Append -Encoding utf8
(& $injector -x powershell.exe -p $A.Id | Out-String) | Out-File "$rep\run2-T1-inject.txt" -Append -Encoding utf8
"exit=$LASTEXITCODE" | Out-File "$rep\run2-T1-inject.txt" -Append -Encoding utf8
Start-Sleep -Seconds 4
$ap = "$env:LOCALAPPDATA\CivLink\M0A\logs"
$la = Get-ChildItem $ap -Filter "civtrace_*_pid$($A.Id).log" | Sort-Object LastWriteTime | Select-Object -Last 1
"hookline: $((Select-String -Path $la.FullName -Pattern 'hooks installed').Line)" | Out-File "$rep\run2-T1-inject.txt" -Append -Encoding utf8
$sz0 = $la.Length
Start-Sleep -Seconds 6
$sz1 = (Get-Item $la.FullName).Length
"liveflush size0=$sz0 size1=$sz1 grew=$($sz1 - $sz0) bytes (BUG#1 evidence)" | Out-File "$rep\run2-T1-inject.txt" -Append -Encoding utf8
($la.FullName | Out-String) | Out-File "$rep\run2-T1-inject.txt" -Append -Encoding utf8

# ---------- T2: duplicate injection ----------
(& $injector -x powershell.exe -p $A.Id | Out-String) | Out-File "$rep\run2-T2-duplicate.txt" -Encoding utf8
"exit=$LASTEXITCODE" | Out-File "$rep\run2-T2-duplicate.txt" -Append -Encoding utf8

# ---------- T6: unload attempt with WRONG dll while loaded (identity refusal) ----------
(& $injector -x powershell.exe -p $A.Id -u C:\Windows\System32\ws2_32.dll | Out-String) | Out-File "$rep\run2-T6-wrongdll-refusal.txt" -Encoding utf8
"exit=$LASTEXITCODE (expect 2)" | Out-File "$rep\run2-T6-wrongdll-refusal.txt" -Append -Encoding utf8

# ---------- T3: unload with confirmed shutdown ----------
$tA2 = (Get-Process -Id $A.Id).Threads.Count
(& $injector -x powershell.exe -p $A.Id -u | Out-String) | Out-File "$rep\run2-T3-shutdown-unload.txt" -Encoding utf8
"exit=$LASTEXITCODE" | Out-File "$rep\run2-T3-shutdown-unload.txt" -Append -Encoding utf8
Start-Sleep -Seconds 1
$alive = -not $A.HasExited
$tA3 = if ($alive) { (Get-Process -Id $A.Id).Threads.Count } else { -1 }
$hA3 = if ($alive) { (Get-Process -Id $A.Id).HandleCount } else { -1 }
"target_alive_after_unload=$alive threads_after=$tA3 (before=$tA) handles_after=$hA3 (before=$hA)" | Out-File "$rep\run2-T3-shutdown-unload.txt" -Append -Encoding utf8
"log_tail_after_unload:" | Out-File "$rep\run2-T3-shutdown-unload.txt" -Append -Encoding utf8
Get-Content $la.FullName -Tail 3 | Out-File "$rep\run2-T3-shutdown-unload.txt" -Append -Encoding utf8

# ---------- T5: unload again (expect nothing to unload) ----------
(& $injector -x powershell.exe -p $A.Id -u | Out-String) | Out-File "$rep\run2-T5-unload-notloaded.txt" -Encoding utf8
"exit=$LASTEXITCODE" | Out-File "$rep\run2-T5-unload-notloaded.txt" -Append -Encoding utf8

# ---------- T4: abnormal exit (taskkill /F while injected) ----------
$B = Start-Process powershell -WindowStyle Hidden -PassThru -ArgumentList '-NoProfile','-Command',$payload
Start-Sleep -Seconds 2
"B_pid=$($B.Id)" | Out-File "$rep\run2-T4-abnormal-kill.txt" -Encoding utf8
(& $injector -x powershell.exe -p $B.Id | Out-String) | Out-File "$rep\run2-T4-abnormal-kill.txt" -Append -Encoding utf8
"exit=$LASTEXITCODE" | Out-File "$rep\run2-T4-abnormal-kill.txt" -Append -Encoding utf8
Start-Sleep -Seconds 4
$lb = Get-ChildItem $ap -Filter "civtrace_*_pid$($B.Id).log" | Sort-Object LastWriteTime | Select-Object -Last 1
$szb0 = $lb.Length
Start-Sleep -Seconds 5
$szb1 = (Get-Item $lb.FullName).Length
"log_before_kill size0=$szb0 size1=$szb1" | Out-File "$rep\run2-T4-abnormal-kill.txt" -Append -Encoding utf8
taskkill /F /PID $B.Id 2>&1 | Out-String | Out-File "$rep\run2-T4-abnormal-kill.txt" -Append -Encoding utf8
Start-Sleep -Seconds 1
$szb2 = (Get-Item $lb.FullName).Length
$lastLine = Get-Content $lb.FullName -Tail 1
"log_after_forcekill size=$szb2 lastline=[$lastLine]" | Out-File "$rep\run2-T4-abnormal-kill.txt" -Append -Encoding utf8
"note: force kill = no DLL_PROCESS_DETACH, no session-end line expected; flushed lines must survive intact" | Out-File "$rep\run2-T4-abnormal-kill.txt" -Append -Encoding utf8

# ---------- preserve raw trace logs + hashes ----------
Copy-Item $la.FullName "$rep\run2-log-A.pid$($A.Id).log" -Force
Copy-Item $lb.FullName "$rep\run2-log-B.pid$($B.Id).log" -Force
Get-FileHash $la.FullName, $lb.FullName -Algorithm SHA256 | ForEach-Object {
  "{0} {1}" -f $_.Hash.ToLower(), (Split-Path $_.Path -Leaf)
} | Out-File "$rep\run2-log-sha256.txt" -Encoding utf8
"A_log_lines=$((Get-Content $la.FullName).Count) B_log_lines=$((Get-Content $lb.FullName).Count)" | Out-File "$rep\run2-log-sha256.txt" -Append -Encoding utf8

if (-not $A.HasExited) { Stop-Process -Id $A.Id -Force -ErrorAction SilentlyContinue }
"done $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" | Out-File "$rep\run2-done.txt" -Encoding utf8
