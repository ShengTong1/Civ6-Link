# run-b1-sendform-capture.ps1 -- B1 R-1 前置：实测 A 机 Civ6 广告页发送形态
# Usage (A 机, 需要 UAC 提权, Defender 已排除 civtrace/civinject):
#   powershell -NoProfile -ExecutionPolicy Bypass -File .\run-b1-sendform-capture.ps1
#
# 流程: 设 CIVTRACE_TAG=b1sendform -> 经 steam.exe 启动 Civ6 -> 注入 civtrace.dll
#       -> 提示用户建房 + 刷新大厅 -> 提取发现 sendto 目标集合 -> 写出取证结论
# 产物: <out>\send-form-report.txt (结论) + <out>\sendto-discovery-slice.txt (日志切片)
#       <out>\civtrace 日志副本 (含 tag 的完整日志)

param(
    [string]$OutDir = "C:\Users\dd\Desktop\injciv6-v0.3.3\M0A\captures\B1-sendform-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
)

$ErrorActionPreference = 'Stop'
$root = 'C:\Users\dd\Desktop\injciv6-v0.3.3\CivLink-M0A-audit'
$inject = Join-Path $root 'civtrace\civinject.exe'
$dll    = Join-Path $root 'civtrace\civtrace.dll'
$steam  = 'D:\steam\steam.exe'
$logDir = Join-Path $env:LOCALAPPDATA 'CivLink\M0A\logs'
$tag    = 'host'

New-Item -ItemType Directory -Path $OutDir -Force | Out-Null

# 0) 前置检查
if (-not (Test-Path $inject)) { Write-Error "civinject.exe 不存在: $inject" }
if (-not (Test-Path $dll))    { Write-Error "civtrace.dll 不存在: $dll" }
if (-not (Test-Path $steam))  { Write-Error "steam.exe 不存在: $steam (请改 \$steam)" }

# 1) 验证 tag 已就位 (用户已确认当前 Steam 带 CIVTRACE_TAG; 不再重启 Steam/自动注入)
$env:CIVTRACE_TAG = $tag
Write-Host "[1/5] 沿用当前运行中的 Steam (用户确认已带 CIVTRACE_TAG=$tag, 已实测验证)"
Write-Host "      请在**当前 Steam** 中启动 Civilization VI (游戏将继承 tag)"

# 3) 等游戏进程出现
Write-Host "[2/5] 等待 CivilizationVI_DX12.exe 进程 ..."
$gpid = $null
for ($i = 0; $i -lt 120; $i++) {
    $procs = Get-Process -Name 'CivilizationVI_DX12' -ErrorAction SilentlyContinue
    if ($procs -and $procs.Count -gt 0) { $gpid = $procs[0].Id; break }
    Start-Sleep -Seconds 2
}
if (-not $gpid) { Write-Error "120s 内未看到 CivilizationVI_DX12.exe -- 请手动从 Steam 启动游戏后重跑" }
Write-Host "      游戏 pid=$gpid"

# 4) 引导手动注入 civtrace.dll (脚本不自动注入)
Write-Host "[3/5] 请手动注入 civtrace.dll (管理员 PowerShell):"
Write-Host "      cd $root"
Write-Host "      .\civtrace\civinject.exe -x CivilizationVI_DX12.exe -p $gpid .\civtrace\civtrace.dll"
Read-Host "      注入完成后按回车继续"

# 5) 提示建房 + 刷新
Write-Host "`n[4/5] 请操作 A 机 Civ6: 主菜单 -> 多人游戏 -> 建局域网房间 (真实房名)"
Write-Host "      然后让 B 机 (或本机第二窗口) 大厅刷新 1-2 次"
Read-Host "      完成后按回车继续"

# 6) 提取发现 sendto 目标集合
Write-Host "[5/5] 提取 civtrace 日志 sendto 目标 ..."
Start-Sleep -Seconds 2
$log = Get-ChildItem -Path $logDir -Filter "civtrace_*_${tag}.log" -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (-not $log) {
    Write-Warning "未找到 tag=$tag 的 civtrace 日志 (最近日志如下):"
    Get-ChildItem -Path $logDir -Filter 'civtrace_*.log' | Sort-Object LastWriteTime -Descending |
        Select-Object -First 5 | ForEach-Object { $_.Name }
    # 兜底: 取最新任意日志
    $log = Get-ChildItem -Path $logDir -Filter 'civtrace_*.log' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
}
Write-Host "      日志: $($log.FullName)"
Copy-Item $log.FullName (Join-Path $OutDir $log.Name)

# sendto 目标: 发现 socket (dst 端口 62900-62999 或 255.255.255.255) 全集合
$slice = Join-Path $OutDir 'sendto-discovery-slice.txt'
"=== sendto discovery targets (from $($log.Name)) ===" | Out-File $slice -Encoding utf8
$targets = @{}
Get-Content $log.FullName | Select-String -Pattern 'sendto .*dst=(\S+):(\d+)' | ForEach-Object {
    $dst = $_.Matches[0].Groups[1].Value
    $port = $_.Matches[0].Groups[2].Value
    $key = "$dst`:$port"
    if ($targets.ContainsKey($key)) { $targets[$key]++ } else { $targets[$key] = 1 }
    $_.Line | Out-File $slice -Append -Encoding utf8
}

# 结论
$report = Join-Path $OutDir 'send-form-report.txt'
"=== B1 R-1 发送形态取证结论 ===" | Out-File $report -Encoding utf8
"时间: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" | Out-File $report -Append -Encoding utf8
"游戏 pid: $gpid  日志: $($log.Name)" | Out-File $report -Append -Encoding utf8
"" | Out-File $report -Append -Encoding utf8
$broadcast = 0; $discPortUni = 0; $tmpPortUni = 0
foreach ($k in ($targets.Keys | Sort-Object)) {
    $dst = ($k -split ':')[0]; $port = [int](($k -split ':')[1])
    if ($dst -eq '255.255.255.255') { $broadcast += $targets[$k] }
    elseif ($port -ge 62900 -and $port -le 62999) { $discPortUni += $targets[$k] }
    else { $tmpPortUni += $targets[$k] }
    "  $k  x$($targets[$k])" | Out-File $report -Append -Encoding utf8
}
"" | Out-File $report -Append -Encoding utf8
"广播 255.255.255.255: $broadcast 次" | Out-File $report -Append -Encoding utf8
"发现端口单播 (62900-62999): $discPortUni 次" | Out-File $report -Append -Encoding utf8
"临时端口单播 (其他): $tmpPortUni 次" | Out-File $report -Append -Encoding utf8
"" | Out-File $report -Append -Encoding utf8
$verdict = ''
if ($broadcast -gt 0) { $verdict = 'P2 直收可用 (广播形态)' }
elseif ($discPortUni -gt 0) { $verdict = 'P2 直收可用 (发现端口单播形态)' }
else { $verdict = '仅临时端口单播 (或未捕获 sendto) -> P1/P2 均不可捕获 (R-1), 须调整方案如实登记' }
"结论: $verdict" | Out-File $report -Append -Encoding utf8

Write-Host "`n===== 取证结论 ====="
Get-Content $report
Write-Host "`n产物目录: $OutDir"
