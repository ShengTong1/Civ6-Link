<#
  CivLink M0-A · 提权抓包运行器（pktmon 后端，单次提权覆盖整段采集）
  ------------------------------------------------------------
  为什么需要这个：pktmon 必须管理员；而 agent 侧 pwsh 非提权。
  做法：一次性提权启动本脚本，脚本内部：
    pktmon start --capture → 写 ready 文件 → 轮询 stop 文件 → pktmon stop
    → etl2pcap 转 pcapng → 写 done 文件
  外部（非提权）只需创建 stop 文件即可优雅收尾。

  用法：
    # 提权启动（UAC 点"是"）
    Start-Process powershell -Verb RunAs -ArgumentList @(
      '-NoProfile','-ExecutionPolicy','Bypass','-File', $PSScriptRoot+'\capture-run.ps1',
      '-Label','E1-host-inj','-OutRoot','...\M0A\captures')

    # 结束：写 stop 文件
    New-Item -ItemType File "...\M0A\captures\E1-host-inj.stop"
#>
[CmdletBinding()]
param(
    [string]$Label = "capture",
    [string]$OutRoot = "",
    [int]$PktSize = 0,
    [int]$MaxSeconds = 900
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($OutRoot)) {
    $scriptDir = $PSScriptRoot
    if ([string]::IsNullOrWhiteSpace($scriptDir)) { $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition }
    $OutRoot = [IO.Path]::GetFullPath((Join-Path $scriptDir '..\..\M0A\captures'))
}

New-Item -ItemType Directory -Force -Path $OutRoot | Out-Null
$log = Join-Path $OutRoot "$Label-runner.log"
function Log([string]$m) {
    $line = "[{0}] {1}" -f (Get-Date -Format 'HH:mm:ss.fff'), $m
    Add-Content -Path $log -Value $line -Encoding UTF8
}

$ready  = Join-Path $OutRoot "$Label.ready"
$stop   = Join-Path $OutRoot "$Label.stop"
$done   = Join-Path $OutRoot "$Label.done"
$etl    = Join-Path $OutRoot ("{0}-{1}.etl" -f $Label, (Get-Date -Format 'yyyyMMdd_HHmmss'))
Remove-Item $ready,$stop,$done -ErrorAction SilentlyContinue

Log "runner start (elevated=$(([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))) label=$Label"
Log "outroot=$OutRoot"

try {
    & pktmon stop 2>$null | Out-Null
    Log "pktmon start --capture --pkt-size $PktSize --file-name $etl"
    & pktmon start --capture --pkt-size $PktSize --file-name $etl 2>&1 | ForEach-Object { Log "  $_" }
    if ($LASTEXITCODE -ne 0) { throw "pktmon start failed exit=$LASTEXITCODE" }

    Set-Content -Path $ready -Encoding UTF8 -Value @(
        "label=$Label"
        "etl=$etl"
        "started=$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')"
        "pid=$PID"
    )
    Log "READY etl=$etl"

    $sw = [Diagnostics.Stopwatch]::StartNew()
    while (-not (Test-Path $stop)) {
        if ($sw.Elapsed.TotalSeconds -gt $MaxSeconds) { Log "max seconds reached, stopping"; break }
        Start-Sleep -Milliseconds 300
    }
    Log "stop signal received after $([math]::Round($sw.Elapsed.TotalSeconds,1))s"

    & pktmon stop 2>&1 | ForEach-Object { Log "  $_" }
    Start-Sleep -Milliseconds 1000

    if (-not (Test-Path $etl)) {
        # pktmon 可能按默认名落盘，找最新的
        $cand = Get-ChildItem $OutRoot -Filter '*.etl' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($cand) { $etl = $cand.FullName; Log "etl relocated to $etl" }
        else { throw "ETL not found in $OutRoot" }
    }

    $pcap = [IO.Path]::ChangeExtension($etl, '.pcapng')
    Log "etl2pcap $etl -> $pcap"
    & pktmon etl2pcap $etl --out $pcap 2>&1 | ForEach-Object { Log "  $_" }
    if (-not (Test-Path $pcap)) { throw "etl2pcap produced nothing" }

    $ei = Get-Item $etl; $pi = Get-Item $pcap
    Log "DONE etl=$($ei.Length)B pcapng=$($pi.Length)B"
    Set-Content -Path $done -Encoding UTF8 -Value @(
        "label=$Label"
        "etl=$($ei.FullName)"
        "etlBytes=$($ei.Length)"
        "pcapng=$($pi.FullName)"
        "pcapngBytes=$($pi.Length)"
        "finished=$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')"
        "result=OK"
    )
}
catch {
    Log "ERROR $_"
    Set-Content -Path $done -Encoding UTF8 -Value @(
        "label=$Label"
        "result=FAILED"
        "error=$_"
        "finished=$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')"
    )
}
