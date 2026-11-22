# analyze-trace.ps1 -- civtrace log quick analysis (CivLink M0-A)
# Usage:
#   powershell -File scripts\analyze-trace.ps1 -Log <logfile> [-H3] [-Discovery] [-Socket 0x1a4] [-Tail 50]

param(
    [Parameter(Mandatory = $true)][string]$Log,
    [switch]$H3,
    [switch]$Discovery,
    [string]$Socket,
    [int]$Tail = 50
)

$ErrorActionPreference = "Stop"
if (-not (Test-Path $Log)) { Write-Error "Log not found: $Log" }

function Banner($t) { Write-Host "`n===== $t =====" }

if ($Discovery) {
    Banner "DISCOVERY: sendto 255.255.255.255 count (expect 100 x refresh-count)"
    (Select-String -Path $Log -Pattern "sendto .*dst=255\.255\.255\.255").Count
    Banner "DISCOVERY: target port histogram"
    Select-String -Path $Log -Pattern "sendto .*dst=255\.255\.255\.255:(\d+)" |
        ForEach-Object { $_.Matches[0].Groups[1].Value } |
        Group-Object | Sort-Object { [int]$_.Name } |
        Format-Table @{L = 'port'; E = { [int]$_.Name } }, Count -AutoSize
    Banner "DISCOVERY: recvfrom / select on discovery phase"
    Select-String -Path $Log -Pattern "select |recvfrom " | Select-Object -First 40
}

if ($H3) {
    Banner "H3-1: OVERLAPPED passed in (ov=yes) -- presence alone is NOT proof of async"
    (Select-String -Path $Log -Pattern "ov=yes").Count
    Banner "H3-2: real pending state [WSA_IO_PENDING]"
    Select-String -Path $Log -Pattern "WSA_IO_PENDING" | Select-Object -First 20
    Banner "H3-3: completion path: WSAWaitForMultipleEvents / WSAGetOverlappedResult / WSAEnumNetworkEvents"
    Select-String -Path $Log -Pattern "WSAWaitForMultipleEvents|WSAGetOverlappedResult|WSAEnumNetworkEvents|WSACreateEvent" | Select-Object -First 20
    Banner "H3-4: extension functions via WSAIoctl SIO_GET_EXTENSION_FUNCTION_POINTER (ConnectEx/WSARecvMsg bypass exports)"
    Select-String -Path $Log -Pattern "SIO_GET_EXTENSION" | Select-Object -First 20
    Banner "H3-5: IOCP path: CreateIoCompletionPort / GQCS (rate-limited entries)"
    Select-String -Path $Log -Pattern "CreateIoCompletionPort|GetQueuedCompletionStatus" | Select-Object -First 20
    Banner "H3-verdict hint"
    $async = (Select-String -Path $Log -Pattern "WSA_IO_PENDING|WSAWaitForMultipleEvents|WSAGetOverlappedResult|SIO_GET_EXTENSION|CreateIoCompletionPort").Count
    if ($async -eq 0) { Write-Host "no async evidence found -> polling model (select/WSAPoll/WSAEWOULDBLOCK) likely" }
    else { Write-Host "ASYNC evidence found ($async lines) -> inspect sections above" }
}

if ($Socket) {
    Banner "SOCKET LIFECYCLE: $Socket (use the value from 'socket' line, e.g. 0x1a4)"
    Select-String -Path $Log -Pattern ("s=0x" + $Socket.Replace('0x','').TrimStart('0') + "\b|s=" + $Socket + "\b") |
        ForEach-Object { $_.Line }
}

Banner "SESSION: last $Tail lines"
Get-Content $Log -Tail $Tail
