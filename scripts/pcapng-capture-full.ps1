# CivLink pcapng FULL-PAYLOAD capture (relocatable, admin required)
#
# Same as pcapng-capture.ps1 but records the WHOLE packet and filters to IPv4+UDP.
# Reason: pktmon defaults to --pkt-size 128, which truncates the 1146-byte host
# reply frame to 128 bytes -> only 86 of 1104 UDP payload bytes survive, so H4
# (is the host address in the source address or in the payload?) cannot be
# settled. --pkt-size 0 is documented as "record the whole packet".
#
#   pktmon start --capture --pkt-size 0 --file-name <etl>
#   pktmon filter add civlink -d IPv4 -t UDP
#
# Filtering to IPv4+UDP keeps the file small: the 181.9 s E2-A window held only
# 1.19 MB of UDP bytes, versus 72 MB dominated by non-UDP traffic at size 128.
#
# PS 5.1 notes baked in:
#   - this file is UTF-8 WITH BOM (mandatory for non-ASCII comments)
#   - $ErrorActionPreference='Continue' so native stderr never aborts the script
#   - every pktmon call is wrapped with *> $null
#   - always pauses before exit so the window never vanishes
$ErrorActionPreference = 'Continue'

$root = Join-Path $PSScriptRoot 'captures'
$log  = Join-Path $root 'capture-full.log'
New-Item -ItemType Directory -Force -Path $root | Out-Null

function Say([string]$m, [string]$color = 'Gray') {
    Write-Host $m -ForegroundColor $color
    try { Add-Content -Path $log -Value ("[{0}] {1}" -f (Get-Date -Format 'HH:mm:ss.fff'), $m) -Encoding UTF8 } catch {}
}

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'

Say "=== CivLink pcapng FULL-PAYLOAD capture ===" 'Cyan'
Say ("Host : {0}" -f $env:COMPUTERNAME)
Say ("Admin: {0}   PID: {1}" -f $isAdmin, $PID)
Say ("Time : {0}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
Say ("Out  : {0}" -f $root)
Say ""

if (-not $isAdmin) {
    Say "!! NOT administrator - pktmon cannot work." 'Red'
    Say "!! Right-click the .cmd -> Run as administrator." 'Red'
    Read-Host "Press Enter to exit"
    exit 1
}

$etl  = Join-Path $root "full-$stamp.etl"
$pcap = Join-Path $root "pcapng-full-$stamp.pcapng"
$lead = 15
$dur  = 60

Say "ETL : $etl"
Say "PCAP: $pcap"
Say "MODE: --pkt-size 0 (whole packet) + filter IPv4/UDP only"
Say ""
Say "== BEFORE you continue ==" 'Yellow'
Say " 1. Civilization VI is running and already on: Multiplayer -> LAN" 'Yellow'
Say (" 2. This window counts down {0}s, then captures {1}s." -f $lead, $dur) 'Yellow'
Say " 3. Click [Refresh] in the game AFTER the capture starts." 'Yellow'
Say " 4. Do NOT click refresh before the capture starts." 'Yellow'
Say ""
for ($i = $lead; $i -gt 0; $i--) { Say ("Starting in {0} ..." -f $i) 'Yellow'; Start-Sleep -Seconds 1 }

Say "[1/5] pktmon stop (clear old session)"
& pktmon stop *> $null
& pktmon filter remove *> $null

Say "[2/5] pktmon filter add civlink -d IPv4 -t UDP"
& pktmon filter add civlink -d IPv4 -t UDP *> $null
Say ("      exitcode = {0}" -f $LASTEXITCODE)

Say "[3/5] pktmon start --capture --pkt-size 0"
& pktmon start --capture --pkt-size 0 --file-name $etl *> $null
$rc = $LASTEXITCODE
Say ("      exitcode = {0}" -f $rc)
if ($rc -ne 0) {
    Say "!! pktmon start FAILED (exit=$rc)" 'Red'
    Say "!! Check: are you really elevated? Is the PktMon driver available?" 'Red'
    Read-Host "Press Enter to exit"
    exit 2
}

Say ("[3/5] pktmon filter list")
$flt = (& pktmon filter list) 2>&1 | Out-String
Say $flt

Say ""
Say "==== CAPTURING (WHOLE PACKET) - click [Refresh] in the game NOW ====" 'Green'
Say ""
for ($i = $dur; $i -gt 0; $i--) { Write-Host ("`rCapturing... {0,2}s left" -f $i) -NoNewline; Start-Sleep -Seconds 1 }
Say ""

Say "[4/5] pktmon stop"
& pktmon stop *> $null
Start-Sleep -Seconds 2

$foundEtl = $null
if (Test-Path $etl) { $foundEtl = $etl }
else {
    $cand = Get-ChildItem $root -Filter 'full-*.etl' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($cand) { $foundEtl = $cand.FullName; Say ("      ETL found at: {0}" -f $foundEtl) }
}

if (-not $foundEtl) {
    Say "!! no ETL produced" 'Red'
    Read-Host "Press Enter to exit"
    exit 3
}
Say ("      ETL size = {0} bytes" -f (Get-Item $foundEtl).Length)

Say "[5/5] pktmon etl2pcap ..."
& pktmon etl2pcap $foundEtl --out $pcap *> $null
Start-Sleep -Seconds 1

if (Test-Path $pcap) {
    $f = Get-Item $pcap
    $hash = (Get-FileHash $pcap -Algorithm SHA256).Hash
    Say ""
    Say ("OK   pcapng = {0}" -f $f.FullName) 'Green'
    Say ("     bytes  = {0}" -f $f.Length) 'Green'
    Say ("     sha256 = {0}" -f $hash) 'Green'
    @(
        "pcapng=$($f.FullName)"
        "bytes=$($f.Length)"
        "sha256=$hash"
        "etl=$foundEtl"
        "host=$env:COMPUTERNAME"
        "pktSize=0"
        "filter=IPv4+UDP"
        "finished=$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    ) | Set-Content -Path (Join-Path $root 'capture-full.done') -Encoding UTF8
    Say ""
    Say "Send back: the .pcapng file AND capture-full.done" 'Cyan'
} else {
    Say "!! etl2pcap produced no pcapng (ETL kept, can be converted manually)" 'Red'
}
Say ""
Read-Host "Done. Press Enter to close"