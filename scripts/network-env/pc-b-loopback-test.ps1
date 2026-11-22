# PC-B 自环广播测试：绑定 62900-62999，用户点 Civ6 刷新后看能否收到自己发出的广播
# 在 PC-B 上以普通 PowerShell 运行：powershell.exe -NoProfile -ExecutionPolicy Bypass -File pc-b-loopback-test.ps1
$ErrorActionPreference = 'Continue'
$socks = @()
$bound = 0
foreach ($p in 62900..62999) {
  try {
    $s = [System.Net.Sockets.UdpClient]::new([System.Net.IPEndPoint]::new([System.Net.IPAddress]::Any, $p))
    $s.Client.ReceiveTimeout = 800
    $socks += $s
    $bound++
  } catch { "bind fail $p : $($_.Exception.Message)" }
}
Write-Host "bound=$bound ports on PC-B; listening 120s"
Write-Host "请现在在 Civ6 局域网大厅点一次「刷新」"
$deadline = (Get-Date).AddSeconds(120)
$found = @()
while ((Get-Date) -lt $deadline) {
  foreach ($s in $socks) {
    try {
      $ep = [System.Net.IPEndPoint]::new([System.Net.IPAddress]::Any, 0)
      $d = $s.Receive([ref]$ep)
      $src = $ep.Address.ToString()
      $found += "$(Get-Date -Format HH:mm:ss.fff) from $src`:$($ep.Port) len=$($d.Length) head=$([BitConverter]::ToString($d[0..3]))"
    } catch { }
  }
}
foreach ($s in $socks) { try { $s.Close() } catch {} }
$result = if ($found.Count -eq 0) { "NO broadcast seen by PC-B itself in 120s (Civ6 refresh did not send, or sent on another interface)" } else { "PC-B self-loopback captured $($found.Count)`n" + ($found -join "`n") }
$result
Set-Content -Path "$env:USERPROFILE\Desktop\pcb-loopback-result.txt" -Value $result -Encoding UTF8
Write-Host "结果已写入 Desktop\pcb-loopback-result.txt"
