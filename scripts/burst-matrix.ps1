param([string]$Base='C:\Users\dd\Desktop\injciv6-v0.3.3')
$probe = Join-Path $Base 'CivLink-M0A-audit\scripts\probe-select-limit.ps1'
$capDir = Join-Path $Base 'M0A\captures'
$selfIp = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -like '192.168.31.*' } | Select-Object -First 1).IPAddress
$magic = [byte[]](0x8d,0xe8,0xfc,0x70)
$results = New-Object System.Collections.Generic.List[string]

function Invoke-Burst([string]$Name,[string]$Dest,[int]$DelayMs,[int]$Ports) {
    $o = Join-Path $capDir ("mx-$Name.out")
    Remove-Item $o -ErrorAction SilentlyContinue
    $winSec = 8 + [int](($Ports * $DelayMs) / 1000) + 10
    $argv = @('-NoProfile','-ExecutionPolicy','Bypass','-File',$probe,'-Seconds',"$winSec")
    $p = Start-Process powershell.exe -ArgumentList $argv -WindowStyle Hidden -RedirectStandardOutput $o -PassThru
    $ready = $false
    for ($i=0; $i -lt 60; $i++) {
        Start-Sleep -Milliseconds 300
        $ep = Get-NetUDPEndpoint -ErrorAction SilentlyContinue | Where-Object { $_.LocalPort -eq 62900 -and $_.OwningProcess -eq $p.Id }
        if ($ep) { $ready = $true; break }
    }
    if (-not $ready) { $results.Add("$Name : PROBE DID NOT BIND"); return }
    Start-Sleep -Milliseconds 400
    $held = @(Get-NetUDPEndpoint -ErrorAction SilentlyContinue | Where-Object {
        $_.LocalPort -ge 62900 -and $_.LocalPort -le 62999 -and $_.LocalAddress -notmatch ':' -and $_.OwningProcess -ne $p.Id } |
        Select-Object -ExpandProperty LocalPort)
    $snd = [System.Net.Sockets.Socket]::new('InterNetwork','Dgram','Udp')
    $snd.SetSocketOption([Net.Sockets.SocketOptionLevel]::Socket,[Net.Sockets.SocketOptionName]::Broadcast,$true)
    $dest = [System.Net.IPAddress]::Parse($Dest)
    $sent = 0
    for ($port=62900; $port -le 62999; $port++) {
        if ($held -contains $port) { continue }
        try {
            [void]$snd.SendTo($magic, [System.Net.IPEndPoint]::new($dest, $port))
            $sent++
            if ($DelayMs -gt 0) { Start-Sleep -Milliseconds $DelayMs }
        } catch { }
    }
    $snd.Dispose()
    Wait-Process -Id $p.Id -Timeout ($winSec + 30) -ErrorAction SilentlyContinue
    $line = (Get-Content $o -ErrorAction SilentlyContinue | Select-String -Pattern 'RESULT').Line
    $results.Add(("{0,-16} dst={1,-16} delay={2,3}ms sent={3,3} :: {4}" -f $Name, $Dest, $DelayMs, $sent, $line))
}

Invoke-Burst 'bcast-0ms'   '255.255.255.255' 0  99
Invoke-Burst 'bcast-5ms'   '255.255.255.255' 5  99
Invoke-Burst 'bcast-20ms'  '255.255.255.255' 20 99
Invoke-Burst 'bcast-60ms'  '255.255.255.255' 60 99
Invoke-Burst 'ucast-own0'  $selfIp          0  99
Invoke-Burst 'ucast-own20' $selfIp          20 99
$results | ForEach-Object { $_ }