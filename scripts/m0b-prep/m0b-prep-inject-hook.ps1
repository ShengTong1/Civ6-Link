$out = 'C:\Users\dd\Desktop\injciv6-v0.3.3\M0A\captures\M0B-prep-stability-20261115'
New-Item -ItemType Directory -Path $out -Force | Out-Null
$ctl = 'C:\Users\dd\Desktop\injciv6-v0.3.3\CivLink-M0A-audit\civlink\civlink_ctl.exe'
$hook = 'C:\Users\dd\Desktop\injciv6-v0.3.3\CivLink-M0A-audit\civlink\civlink_hook.dll'
$log = Join-Path $out 'inject-hook.txt'
"=== inject-hook $(Get-Date -Format 'HH:mm:ss') ===" | Out-File -FilePath $log -Encoding utf8
& $ctl inject -x CivilizationVI_DX12.exe -p 12420 -d $hook 2>&1 | Out-File -FilePath $log -Append -Encoding utf8
"INJECT_EXIT=$LASTEXITCODE" | Out-File -FilePath $log -Append -Encoding utf8
Start-Sleep -Seconds 3
& $ctl status -x CivilizationVI_DX12.exe -p 12420 2>&1 | Out-File -FilePath $log -Append -Encoding utf8
& $ctl counters -x CivilizationVI_DX12.exe -p 12420 2>&1 | Out-File -FilePath $log -Append -Encoding utf8