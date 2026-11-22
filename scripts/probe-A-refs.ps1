param([string]$Ports='62900-62999',[int]$Seconds=30,[int]$SelectUs=500000,[switch]$Drain,[switch]$NonBlocking)
$portList=@()
foreach($part in $Ports.Split(',')){ $part=$part.Trim(); if($part -match '^(\d+)-(\d+)$'){ $portList += ([int]$Matches[1])..([int]$Matches[2]) } elseif($part -match '^\d+$'){ $portList += [int]$part } }
$skip=@(Get-NetUDPEndpoint | Where-Object { $_.LocalPort -ge $portList[0] -and $_.LocalPort -le $portList[-1] -and $_.LocalAddress -notmatch ':' } | Select-Object -ExpandProperty LocalPort)
$socks=New-Object System.Collections.Generic.List[object]
foreach($p in $portList){
  if($skip -contains $p){ continue }
  $s=[System.Net.Sockets.Socket]::new('InterNetwork','Dgram','Udp')
  $s.SetSocketOption([Net.Sockets.SocketOptionLevel]::Socket,[Net.Sockets.SocketOptionName]::ReuseAddress,[int]1)
  try { $s.Bind([System.Net.IPEndPoint]::new([System.Net.IPAddress]::Any,$p)); if($NonBlocking){ $s.Blocking=$false }; $s.ReceiveBufferSize=65536 } catch { $s.Dispose(); continue }
  $socks.Add([pscustomobject]@{Port=$p;Sock=$s})
}
"bound=$($socks.Count) skipped=$($skip -join ',') drain=$Drain selectUs=$SelectUs"
$recvBuf=[byte[]]::new(2048)
$flags=[System.Net.Sockets.SocketFlags]::None
$remoteEp=[System.Net.EndPoint][System.Net.IPEndPoint]::new([System.Net.IPAddress]::Any,0)
$pinfo=[System.Net.Sockets.IPPacketInformation]::new()
$sw=[Diagnostics.Stopwatch]::StartNew(); $hits=New-Object System.Collections.Generic.List[int]
while($sw.Elapsed.TotalSeconds -lt $Seconds){
  $rl=New-Object System.Collections.ArrayList
  foreach($e in $socks){ [void]$rl.Add($e.Sock) }
  try { $null=[System.Net.Sockets.Socket]::Select($rl,$null,$null,$SelectUs) } catch { continue }
  if($rl.Count -eq 0){ continue }
  foreach($rs in $rl){
    $entry=$null; foreach($e in $socks){ if([object]::ReferenceEquals($e.Sock,$rs)){ $entry=$e; break } }
    if(-not $entry){ continue }
    $port=$entry.Port
    while($true){
      $re=[System.Net.EndPoint][System.Net.IPEndPoint]::new([System.Net.IPAddress]::Any,0)
      $fl=[System.Net.Sockets.SocketFlags]::None
      $pi=[System.Net.Sockets.IPPacketInformation]::new()
      try { $n=$entry.Sock.ReceiveMessageFrom($recvBuf,0,$recvBuf.Length,[ref]$fl,[ref]$re,[ref]$pi) } catch { break }
      if($n -lt 1){ break }
      if(-not $hits.Contains($port)){ $hits.Add($port) }
      if($entry.Sock.Available -le 0){ break }
    }
  }
}
$sw.Stop()
"RESULT datagrams_ports=$($hits.Count) window=$([math]::Round($sw.Elapsed.TotalSeconds,1))s"
"ports: $(($hits | Sort-Object) -join ',')"
foreach($e in $socks){ $e.Sock.Dispose() }