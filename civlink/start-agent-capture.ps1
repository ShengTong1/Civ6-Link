# start-agent-capture.ps1 - 启动 A 侧 LAN 模拟房主并完整捕获输出
# 用法: powershell -NoProfile -ExecutionPolicy Bypass -File start-agent-capture.ps1 -OutRoot <dir> -ListenSeconds 1800
param(
    [Parameter(Mandatory=$true)][string]$OutRoot,
    [int]$ListenSeconds = 1800
)
$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Path $OutRoot -Force | Out-Null
$agent = 'C:\Users\dd\Desktop\civlink-f5-kit\civlink-agent.exe'
$fixture = 'C:\Users\dd\Desktop\civlink-f5-kit\fixture-reply-set'
$args = "--listen-seconds $ListenSeconds --out-dir `"$OutRoot`" --simulate `"$fixture`" --sim-lan-listen 0.0.0.0 --sim-room-name CivLink-Test-Room-2222"
Set-Content -LiteralPath (Join-Path $OutRoot 'start-cmd.txt') -Value "civlink-agent.exe $args" -Encoding UTF8
$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = $agent
$psi.Arguments = $args
$psi.UseShellExecute = $false
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
$psi.CreateNoWindow = $true
$proc = [System.Diagnostics.Process]::Start($psi)
"AGENT_PID=$($proc.Id)" | Out-File (Join-Path $OutRoot 'agent-pid.txt') -Encoding UTF8
# 持有流引用（防止提前回收），异步读 stdout/stderr 到内存
$outTask = $proc.StandardOutput.ReadToEndAsync()
$errTask = $proc.StandardError.ReadToEndAsync()
# 等窗口自然到期
$proc.WaitForExit()
"AGENT_EXITED_AT=$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" | Out-File (Join-Path $OutRoot 'exit.txt') -Encoding UTF8
# 落盘 console/stderr
$outTask.Wait()
$errTask.Wait()
Set-Content -LiteralPath (Join-Path $OutRoot 'agent-console.txt') -Value $outTask.Result -Encoding UTF8
Set-Content -LiteralPath (Join-Path $OutRoot 'agent-stderr.txt') -Value $errTask.Result -Encoding UTF8
"EXIT_CODE=$($proc.ExitCode)" | Out-File (Join-Path $OutRoot 'exit-code.txt') -Encoding UTF8
# 打印关键值
$s = Join-Path $OutRoot 'summary.txt'
if (Test-Path $s) {
    "--- SUMMARY 关键值 ---"
    Select-String -LiteralPath $s -Pattern 'requests seen|replied sockets|pages sent|send fail|no endpoint|max reached|bind fail|datagrams|received' | ForEach-Object { $_.Line }
} else {
    "NO_SUMMARY"
}
"CAPTURE_COMPLETE"
