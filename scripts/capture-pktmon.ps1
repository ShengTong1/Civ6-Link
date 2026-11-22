<#
  CivLink M0-A · 抓包封装（pktmon 后端）
  ------------------------------------------------------------
  本机未安装 Wireshark / Npcap，改用 Windows 内置 pktmon：
    pktmon start --capture --pkt-size 0 --file-name <etl>
    pktmon etl2pcap <etl> --out <pcapng>
  产物为 pcapng，可在任意 Wireshark 里分析（Conversations / Follow UDP Stream）。

  用法：
    # 开始抓包（管理员）
    powershell -File scripts\capture-pktmon.ps1 -Start -Label E1-host-inj

    # 结束抓包并转 pcapng（管理员）
    powershell -File scripts\capture-pktmon.ps1 -Stop -Label E1-host-inj

  说明：
  - 采集过滤器留空（完整抓取），符合 README §1.4「第一轮不预设端口白名单」；
  - ETL 与 pcapng 都落在 M0A\captures\ 下；
  - pktmon 需要管理员权限。
#>
[CmdletBinding()]
param(
    [switch]$Start,
    [switch]$Stop,
    [string]$Label = "capture",
    [string]$OutRoot = "",
    [int]$PktSize = 0
)

$ErrorActionPreference = 'Stop'

# PS 5.1 下 param 默认值里 $PSScriptRoot 可能为空，这里在函数体内兜底
if ([string]::IsNullOrWhiteSpace($OutRoot)) {
    $scriptDir = $PSScriptRoot
    if ([string]::IsNullOrWhiteSpace($scriptDir)) { $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition }
    $OutRoot = Join-Path (Join-Path (Split-Path -Parent $scriptDir) '..') 'M0A\captures'
    $OutRoot = [IO.Path]::GetFullPath($OutRoot)
}

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "[!] pktmon requires elevation. Re-launching as administrator..." -ForegroundColor Yellow
    $args = @('-NoProfile','-ExecutionPolicy','Bypass','-File', $PSCommandPath)
    if ($Start) { $args += '-Start' }
    if ($Stop)  { $args += '-Stop' }
    $args += @('-Label', $Label, '-OutRoot', $OutRoot, '-PktSize', $PktSize)
    Start-Process powershell -ArgumentList $args -Verb RunAs
    return
}

New-Item -ItemType Directory -Force -Path $OutRoot | Out-Null
$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$etl = Join-Path $OutRoot "$Label-$stamp.etl"

if ($Start) {
    # 先清掉可能残留的会话
    & pktmon stop 2>$null | Out-Null
    Write-Host "[*] pktmon start -> $etl"
    & pktmon start --capture --pkt-size $PktSize --file-name $etl
    if ($LASTEXITCODE -ne 0) { throw "pktmon start failed (exit=$LASTEXITCODE)" }
    & pktmon status
    $stateFile = Join-Path $OutRoot "current-capture.txt"
    Set-Content -Path $stateFile -Value @(
        "label=$Label"
        "etl=$etl"
        "started=$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    ) -Encoding UTF8
    Write-Host "[+] capture running. Stop with: -Stop -Label $Label" -ForegroundColor Green
    return
}

if ($Stop) {
    Write-Host "[*] pktmon stop"
    & pktmon stop | Out-Null
    Start-Sleep -Milliseconds 800

    $stateFile = Join-Path $OutRoot "current-capture.txt"
    if (Test-Path $stateFile) {
        $etlFromState = (Get-Content $stateFile | Where-Object { $_ -like 'etl=*' }) -replace '^etl=', ''
        if ($etlFromState -and (Test-Path $etlFromState)) { $etl = $etlFromState }
    }
    if (-not (Test-Path $etl)) { throw "ETL not found: $etl (pass -Label matching the -Start call)" }

    $pcap = [IO.Path]::ChangeExtension($etl, '.pcapng')
    Write-Host "[*] converting $etl -> $pcap"
    & pktmon etl2pcap $etl --out $pcap
    if ($LASTEXITCODE -ne 0) { throw "pktmon etl2pcap failed (exit=$LASTEXITCODE)" }

    $etlInfo = Get-Item $etl
    $pcapInfo = Get-Item $pcap
    Write-Host "[+] ETL   : $($etlInfo.FullName) ($($etlInfo.Length) B)" -ForegroundColor Green
    Write-Host "[+] PCAPNG: $($pcapInfo.FullName) ($($pcapInfo.Length) B)" -ForegroundColor Green
    Write-Host "[i] Wireshark display filter: (udp.port >= 62900 and udp.port <= 62999) or udp.port == 62056 or udp.port == 47584"

    Remove-Item $stateFile -ErrorAction SilentlyContinue
    return
}

Write-Host "Usage: -Start | -Stop  [-Label <name>] [-OutRoot <dir>]"
