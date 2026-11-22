$out = $args[0]
$ctl = 'C:\Users\dd\Desktop\injciv6-v0.3.3\CivLink-M0A-audit\civlink\civlink_ctl.exe'
$sampleLog = Join-Path $out 'samples.csv'
"time,sent,sendfail,rejectoversize,sentnotify,ignored,observed,rawsendto,rawwsasendto,rawbind,rawrecvfrom,rawwsarecvfrom,bind62056,recon62056,wsarecvpending,cvlh2try,cvlh2ok,stateq,wsMB" | Out-File -FilePath $sampleLog -Encoding utf8
$deadline = (Get-Date).AddSeconds(300)  # 5-minute observation window
$i = 0
while ((Get-Date) -lt $deadline) {
  $i++
  $counters = & $ctl counters -x CivilizationVI_DX12.exe -p 12420 2>&1 | Out-String
  $ws = 0
  $proc = Get-Process -Id 12420 -ErrorAction SilentlyContinue
  if ($proc) { $ws = [math]::Round($proc.WorkingSet64/1MB,1) }
  $extract = { param($s,$key)
    $m = [regex]::Match($s, "^\s*$key\s*:\s*([0-9]+)", [Text.RegularExpressions.RegexOptions]::Multiline)
    if ($m.Success) { return $m.Groups[1].Value } else { return 'NA' }
  }
  $row = "{0},{1},{2},{3},{4},{5},{6},{7},{8},{9},{10},{11},{12},{13},{14},{15},{16},{17},{18}" -f `
    (Get-Date -Format 'HH:mm:ss'), (& $extract $counters 'sent'), (& $extract $counters 'send fail'), `
    (& $extract $counters 'reject oversize'), (& $extract $counters 'sent notify'), (& $extract $counters 'ignored'), `
    (& $extract $counters 'observed frames'), (& $extract $counters 'raw sendto'), (& $extract $counters 'raw wsasendto'), `
    (& $extract $counters 'raw bind'), (& $extract $counters 'raw recvfrom'), (& $extract $counters 'raw wsarecvfrom'), `
    (& $extract $counters 'bind 62056'), (& $extract $counters 'recv on 62056'), (& $extract $counters 'wsarecv pending'), `
    (& $extract $counters 'cvlh2 try'), (& $extract $counters 'cvlh2 ok'), (& $extract $counters 'state queries'), $ws
  $row | Out-File -FilePath $sampleLog -Append -Encoding utf8
  Start-Sleep -Seconds 60
}
"done $i samples"