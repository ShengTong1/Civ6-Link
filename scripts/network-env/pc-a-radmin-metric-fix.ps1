# PC-A Radmin VPN metric fix (elevated): 1 -> 200 so broadcast uses WLAN (45)
# Backup of original value saved separately; restore = Set-NetIPInterface -InterfaceMetric 1
$ErrorActionPreference = 'Stop'
try {
  $before = Get-NetIPInterface -AddressFamily IPv4 -InterfaceAlias 'Radmin VPN' | Select-Object InterfaceMetric
  Write-Host "BEFORE: Radmin VPN InterfaceMetric = $($before.InterfaceMetric)"
  Set-NetIPInterface -InterfaceAlias 'Radmin VPN' -InterfaceMetric 200
  Start-Sleep -Milliseconds 500
  $after = Get-NetIPInterface -AddressFamily IPv4 -InterfaceAlias 'Radmin VPN' | Select-Object InterfaceMetric
  Write-Host "AFTER: Radmin VPN InterfaceMetric = $($after.InterfaceMetric)"
  if ($after.InterfaceMetric -eq 200) {
    Write-Host "OK: metric changed 1 -> 200; broadcast should now use WLAN (metric 45)"
    Set-Content -Path 'C:\Users\dd\Desktop\pc-a-radmin-metric-fix-result.txt' -Value "OK metric=200 $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -Encoding UTF8
  } else {
    Write-Host "FAIL: metric is $($after.InterfaceMetric), expected 200"
    Set-Content -Path 'C:\Users\dd\Desktop\pc-a-radmin-metric-fix-result.txt' -Value "FAIL metric=$($after.InterfaceMetric)" -Encoding UTF8
  }
} catch {
  Write-Host "ERROR: $($_.Exception.Message)"
  Set-Content -Path 'C:\Users\dd\Desktop\pc-a-radmin-metric-fix-result.txt' -Value "ERROR $($_.Exception.Message)" -Encoding UTF8
}
