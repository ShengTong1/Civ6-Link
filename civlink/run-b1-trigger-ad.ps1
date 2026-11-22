# run-b1-trigger-ad.ps1 -- 本机模拟客户端: 发 100 个 4B magic 广播触发 A 机 Civ6 真房主回广告页
# 目的: 补全 B1 R-1 前置取证缺失的「广告页发送形态」(广播 vs 单播到请求者临时端口)
# 前置: A 机 Civ6 已建房 (pid 已知), civtrace 已注入 (日志持续增长)
# 用法: powershell -NoProfile -ExecutionPolicy Bypass -File .\run-b1-trigger-ad.ps1

param(
    [int]$GamePid = 0,
    [string]$Tag = 'host',
    [string]$OutDir = "C:\Users\dd\Desktop\injciv6-v0.3.3\M0A\captures\B1-triggerad-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
)

$ErrorActionPreference = 'Stop'
$logDir = Join-Path $env:LOCALAPPDATA 'CivLink\M0A\logs'
$magic = [byte[]](0x8d, 0xe8, 0xfc, 0x70)

New-Item -ItemType Directory -Path $OutDir -Force | Out-Null

# 0) 找 civtrace 日志 (tag 匹配, 兜底最新)
$log = Get-ChildItem -Path $logDir -Filter "civtrace_*_${tag}.log" -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (-not $log) { $log = Get-ChildItem -Path $logDir -Filter 'civtrace_*.log' | Sort-Object LastWriteTime -Descending | Select-Object -First 1 }
if (-not $log) { Write-Error '未找到 civtrace 日志' }
"日志: $($log.Name)  size=$($log.Length)"
$marker = $log.Length

# 1) 绑定客户端临时端口 54322 (故意非 62900, 验证单播到临时端口的场景)
$client = New-Object System.Net.Sockets.UdpClient(54322)
try {
    # 2) 发 100 个 magic 到 255.255.255.255:62900..62999 (模拟 B 机一次刷新)
    Write-Host "[1/3] 发送 100 个 4B magic 广播 (模拟客户端刷新) ..."
    $sent = 0
    for ($p = 62900; $p -le 62999; $p++) {
        $bytes = $client.Send($magic, 4, '255.255.255.255', $p)
        $sent += $bytes
    }
    "发送字节: $sent / 400"

    # 3) 收 5s: 记录收到的包 (广告页应为 1104B)
    Write-Host "[2/3] 接收 5 秒 ..."
    $client.Client.ReceiveTimeout = 5000
    $received = @()
    $deadline = (Get-Date).AddSeconds(5)
    while ((Get-Date) -lt $deadline) {
        try {
            $ep = New-Object System.Net.IPEndPoint([System.Net.IPAddress]::Any, 0)
            $data = $client.Receive([ref]$ep)
            $received += [pscustomobject]@{ Len = $data.Length; From = $ep.ToString(); Hex = (($data[0..([Math]::Min(7, $data.Length-1))] | ForEach-Object { $_.ToString('x2') }) -join ' ') }
        } catch { break }
    }
    "收到包数: $($received.Count)"
    $received | ForEach-Object { "   len={0} from={1} head={2}" -f $_.Len, $_.From, $_.Hex }
    "广告页(1104B)数: $(($received | Where-Object { $_.Len -eq 1104 }).Count)"
    $received | Export-Csv (Join-Path $OutDir 'client-received.csv') -NoTypeInformation -Encoding UTF8
} finally {
    $client.Close()
}

# 4) 等 civtrace 记录房主 sendto
Start-Sleep -Seconds 3

# 5) 从 civtrace 日志提取 len=1104 sendto 目标 (触发后新增部分)
Write-Host "[3/3] 从 civtrace 日志提取房主广告页 sendto ..."
$newLines = Get-Content $log.FullName | Where-Object { $_ -match '^09:4[3-9]|^09:5[0-9]' }
$adSends = Get-Content $log.FullName | Select-String -Pattern 'sendto .*len=1104'
"len=1104 sendto 记录: $($adSends.Count)"
$adSends | Select-Object -First 10 | ForEach-Object { $_.Line.Substring(0, [Math]::Min(170, $_.Line.Length)) }
$adSends | ForEach-Object { $_.Line } | Out-File (Join-Path $OutDir 'ad-sendto-slice.txt') -Encoding utf8

# 6) 结论: 广告页目标形态
$report = Join-Path $OutDir 'ad-form-report.txt'
"=== B1 R-1 广告页发送形态 (本机模拟客户端触发) ===" | Out-File $report -Encoding utf8
"时间: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  日志: $($log.Name)" | Out-File $report -Append -Encoding utf8
"客户端源: 0.0.0.0:54322 (临时端口, 非 62900)" | Out-File $report -Append -Encoding utf8
"" | Out-File $report -Append -Encoding utf8
"客户端收到: $($received.Count) 包, 广告页(1104B): $(($received | Where-Object { $_.Len -eq 1104 }).Count) 页" | Out-File $report -Append -Encoding utf8
"" | Out-File $report -Append -Encoding utf8
$verdict = ''
if ($adSends.Count -eq 0) {
    $verdict = '未观测到房主广告页 sendto (len=1104=0): 可能 (a) magic 未到达房主 (b) 房主未回广告页 (c) 应答走 UDP 其它 API 未被捕获'
} else {
    $uni = $adSends | Where-Object { $_.Line -match 'dst=255\.255\.255\.255' }
    if ($uni.Count -eq 0) { $verdict = '房主广告页为 单播 (非广播)' }
    else { $verdict = '房主广告页为 广播 255.255.255.255' }
}
"结论: $verdict" | Out-File $report -Append -Encoding utf8
Write-Host "`n===== 结论 ====="
Get-Content $report
Write-Host "`n产物: $OutDir"
