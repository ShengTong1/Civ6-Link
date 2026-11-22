# CivLink E1 pcapng 抓包（必须管理员）
# 修复：不再使用 $ErrorActionPreference='Stop'（PS5.1 下原生命令写 stderr 会抛
#       NativeCommandError 导致脚本立即中止、窗口闪退）；并在退出前 always pause。
$ErrorActionPreference = 'Continue'

$root = "C:\Users\dd\Desktop\injciv6-v0.3.3\M0A\captures"
$log  = Join-Path $root "E1-pcapng-capture.log"
New-Item -ItemType Directory -Force -Path $root | Out-Null

function Say([string]$m, [string]$color = 'Gray') {
    Write-Host $m -ForegroundColor $color
    try { Add-Content -Path $log -Value ("[{0}] {1}" -f (Get-Date -Format 'HH:mm:ss.fff'), $m) -Encoding UTF8 } catch {}
}

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

Say "=== CivLink E1 pcapng capture ===" 'Cyan'
Say ("Admin: {0}  PID: {1}  Time: {2}" -f $isAdmin, $PID, (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
Say "Log : $log"

if (-not $isAdmin) {
    Say "!! 不是管理员权限，pktmon 无法工作。请右键 -> 以管理员身份运行。" 'Red'
    Read-Host "按回车退出"
    exit 1
}

$ts   = Get-Date -Format 'yyyyMMdd_HHmmss'
$etl  = Join-Path $root "$ts-E1.etl"
$pcap = Join-Path $root "E1-pcapng-$ts.pcapng"
Say "ETL : $etl"
Say "PCAP: $pcap"
Say ""
Say "【准备】请现在把游戏切到：多人游戏 -> 局域网 界面" 'Yellow'
Say "30 秒倒计时期间点【刷新】3 次。" 'Yellow'
Say ""
for ($i = 5; $i -gt 0; $i--) { Say ("5秒后开始抓包: {0}" -f $i) 'Yellow'; Start-Sleep -Seconds 1 }

# --- 开始抓包（原生命令，输出全部吞掉，绝不让 stderr 抛异常）---
Say "[1/4] pktmon stop (清理旧会话)"
& pktmon stop *> $null

Say "[2/4] pktmon start --capture --pkt-size 128"
& pktmon start --capture --pkt-size 128 --file-name $etl *> $null
$rc = $LASTEXITCODE
Say ("     exitcode = {0}" -f $rc)
if ($rc -ne 0) {
    Say "!! pktmon start 失败（exit=$rc）" 'Red'
    Say "---- 现在开始抓包，请点刷新 3 次 ----" 'Green'
}

Say ""
Say "==== 现在开始抓包，请在游戏里点【刷新】3 次 ====" 'Green'
Say ""
for ($i = 30; $i -gt 0; $i--) { Write-Host ("`r剩余 {0,2} 秒 ..." -f $i) -NoNewline; Start-Sleep -Seconds 1 }
Say ""
Say "[3/4] pktmon stop"
& pktmon stop *> $null
Start-Sleep -Seconds 2

$foundEtl = $null
if (Test-Path $etl) { $foundEtl = $etl }
else {
    $cand = Get-ChildItem $root -Filter '*.etl' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($cand) { $foundEtl = $cand.FullName; Say ("    ETL 落在: {0}" -f $foundEtl) }
}

if (-not $foundEtl) {
    Say "!! 没有生成 ETL 文件" 'Red'
    Read-Host "按回车退出"
    exit 2
}

Say ("    ETL size = {0} bytes" -f (Get-Item $foundEtl).Length)

Say "[4/4] pktmon etl2pcap ..."
& pktmon etl2pcap $foundEtl --out $pcap *> $null
Start-Sleep -Seconds 1

if (Test-Path $pcap) {
    $f = Get-Item $pcap
    $hash = (Get-FileHash $pcap -Algorithm SHA256).Hash
    Say ""
    Say ("OK  pcapng = {0}" -f $f.FullName) 'Green'
    Say ("    bytes  = {0}" -f $f.Length) 'Green'
    Say ("    sha256 = {0}" -f $hash) 'Green'
    @(
        "pcapng=$($f.FullName)"
        "bytes=$($f.Length)"
        "sha256=$hash"
        "etl=$foundEtl"
        "finished=$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    ) | Set-Content -Path (Join-Path $root 'E1-pcapng.done') -Encoding UTF8
} else {
    Say "!! etl2pcap 没有产出 pcapng（ETL 仍在，可手工转换）" 'Red'
}
Say ""
Read-Host "完成，按回车关闭窗口"
