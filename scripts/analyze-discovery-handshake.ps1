# analyze-discovery-handshake.ps1 -- civ6 LAN discovery handshake extractor (CivLink M0-A)
#
# WHY THIS EXISTS
#   analyze-pcapng-datagrams.ps1 only selects packets whose DESTINATION port is
#   62900-62999. That selects the client's discovery REQUEST but structurally
#   cannot select the host's REPLY, which is sent FROM port 62900 (or another
#   port in 62900-62999) TO the client's ephemeral source port. As a result the
#   E2-A capture was reported as "0 host responses" even though 22 replies of
#   1104 payload bytes are present in it.
#
# WHAT IT DOES (read-only, no network access)
#   1. Walks every EPB in the pcapng.
#   2. Classifies IPv4/UDP packets by the discovery signature:
#        REQ : dst port in [62900,62999] and 4-byte payload 8d e8 fc 70
#        REP : src port in [62900,62999] and dst port == a REQ src port
#   3. Deduplicates by (direction, src ip, dst ip, src port, dst port, IPv4 ID)
#      because pktmon records the same frame at several NDIS capture points.
#   4. For each deduped identity records: tick, copies, frame length, captured
#      bytes, payload bytes, payload hex (truncated to capLen), and a best-effort
#      UTF-8 string scan of the captured payload.
#   5. Emits a summary plus a CSV. Never writes to the pcapng.
#
# NOTE ON TRUNCATION
#   pktmon start --pkt-size N truncates the captured frame to N bytes. With
#   --pkt-size 128 a 1146-byte reply frame keeps only 86 payload bytes. pass
#   --pkt-size 0 (documented as "record the whole packet") to capture 1104.
#
# USAGE
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts\analyze-discovery-handshake.ps1 `
#       -Pcap <file.pcapng> [-OutCsv <file.csv>]
param(
    [Parameter(Mandatory = $true)][string]$Pcap,
    [string]$OutCsv = ''
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path $Pcap)) { throw "pcapng not found: $Pcap" }
if ([string]::IsNullOrWhiteSpace($OutCsv)) {
    $OutCsv = [IO.Path]::ChangeExtension($Pcap, '.handshake.csv')
}

$bytes = [IO.File]::ReadAllBytes($Pcap)

# pcapng block header is little endian (file format); IPv4/UDP header fields are
# network byte order (big endian). Both facts are load bearing here.
$off = 0
$epb = 0
$truncated = 0
$records = New-Object System.Collections.ArrayList
$firstTick = $null
$lastTick = $null

while ($off + 12 -le $bytes.Length) {
    $btype = [BitConverter]::ToUInt32($bytes, $off)
    $blen  = [BitConverter]::ToUInt32($bytes, $off + 4)
    if ($blen -lt 12 -or ($off + $blen) -gt $bytes.Length) { break }

    if ($btype -eq 6) {
        $epb++
        $tick    = (([int64][BitConverter]::ToUInt32($bytes, $off + 12)) -shl 32) -bor [int64][BitConverter]::ToUInt32($bytes, $off + 16)
        $capLen  = [BitConverter]::ToUInt32($bytes, $off + 20)
        $origLen = [BitConverter]::ToUInt32($bytes, $off + 24)
        if ($null -eq $firstTick) { $firstTick = $tick }
        $lastTick = $tick
        if ($capLen -ne $origLen) { $truncated++ }

        $frame = $off + 28
        if ($capLen -ge 42) {
            $etype = ([int]$bytes[$frame + 12] -shl 8) -bor [int]$bytes[$frame + 13]
            if ($etype -eq 0x0800) {
                $ip = $frame + 14
                $ihl = ([int]$bytes[$ip] -band 0x0f) * 4
                $proto = $bytes[$ip + 9]
                if ($proto -eq 17 -and $ihl -ge 20) {
                    $udp = $ip + $ihl
                    if (($udp + 8) -le ($frame + $capLen)) {
                        $sp   = ([int]$bytes[$udp]     -shl 8) -bor [int]$bytes[$udp + 1]
                        $dp   = ([int]$bytes[$udp + 2] -shl 8) -bor [int]$bytes[$udp + 3]
                        $ulen = ([int]$bytes[$udp + 4] -shl 8) -bor [int]$bytes[$udp + 5]
                        $ipid = ([int]$bytes[$ip + 4]  -shl 8) -bor [int]$bytes[$ip + 5]
                        $ttl  = $bytes[$ip + 8]
                        $srcIp = '{0}.{1}.{2}.{3}' -f $bytes[$ip + 12], $bytes[$ip + 13], $bytes[$ip + 14], $bytes[$ip + 15]
                        $dstIp = '{0}.{1}.{2}.{3}' -f $bytes[$ip + 16], $bytes[$ip + 17], $bytes[$ip + 18], $bytes[$ip + 19]
                        $srcMac = -join (6..11 | ForEach-Object { $bytes[$frame + $_].ToString('x2') })
                        $dstMac = -join (0..5  | ForEach-Object { $bytes[$frame + $_].ToString('x2') })

                        $payStart = $udp + 8
                        $avail = [Math]::Min([int]($frame + $capLen - $payStart), [Math]::Max(0, $ulen - 8))
                        $payload = New-Object byte[] 0
                        if ($avail -gt 0) {
                            $payload = New-Object byte[] $avail
                            [Array]::Copy($bytes, $payStart, $payload, 0, $avail)
                        }

                        $kind = ''
                        if ($dp -ge 62900 -and $dp -le 62999) {
                            # discovery request signature: 4-byte magic 8d e8 fc 70
                            if ($avail -ge 4 -and $payload[0] -eq 0x8d -and $payload[1] -eq 0xe8 -and $payload[2] -eq 0xfc -and $payload[3] -eq 0x70) {
                                $kind = 'REQ'
                            }
                        }
                        elseif ($sp -ge 62900 -and $sp -le 62999) {
                            # candidate reply; the multicast/unicast check happens after
                            # the REQ source ports are known (see the second pass).
                            $kind = 'REPCAND'
                        }

                        if ($kind -ne '') {
                            $hex = -join ($payload | ForEach-Object { $_.ToString('x2') })
                            # best-effort UTF-8 scan: printable runs of >=4 bytes
                            $sb = New-Object System.Text.StringBuilder
                            $run = New-Object System.Text.StringBuilder
                            foreach ($bv in $payload) {
                                if ($bv -ge 32 -and $bv -lt 127) { [void]$run.Append([char]$bv) }
                                else {
                                    if ($run.Length -ge 4) { [void]$sb.Append($run.ToString()); [void]$sb.Append('|') }
                                    [void]$run.Clear()
                                }
                            }
                            if ($run.Length -ge 4) { [void]$sb.Append($run.ToString()); [void]$sb.Append('|') }
                            $ascii = $sb.ToString()

                            [void]$records.Add([pscustomobject]@{
                                Kind     = $kind
                                Tick     = $tick
                                SrcMac   = $srcMac
                                DstMac   = $dstMac
                                SrcIp    = $srcIp
                                DstIp    = $dstIp
                                SrcPort  = $sp
                                DstPort  = $dp
                                Ttl      = $ttl
                                IpId     = $ipid
                                UdpLen   = $ulen
                                PayLen   = [Math]::Max(0, $ulen - 8)
                                CapPay   = $avail
                                FrameLen = $origLen
                                CapLen   = $capLen
                                Hex      = $hex
                                Ascii    = $ascii
                            })
                        }
                    }
                }
            }
        }
    }
    $off += $blen
}

if ($records.Count -eq 0) {
    Write-Host "no discovery request/reply packets found in $Pcap"
    exit 3
}

# second pass: a reply must go back to an actual request's source port. Port range
# 62900-62999 is shared with unrelated traffic (SSDP replies come from ephemeral
# ports that can land in that window, e.g. 62984 -> 239.255.255.250:2200), so range
# membership alone is not enough.
$reqPorts = @($records | Where-Object { $_.Kind -eq 'REQ' } | ForEach-Object { $_.SrcPort } | Sort-Object -Unique)
$dropped = 0
$kept = New-Object System.Collections.ArrayList
foreach ($r in $records) {
    if ($r.Kind -eq 'REPCAND') {
        $isMulticast = ($r.DstIp -match '^224\.') -or ($r.DstIp -match '^239\.') -or ($r.DstIp -eq '255.255.255.255')
        if ($isMulticast -or ($reqPorts -notcontains $r.DstPort)) { $dropped++; continue }
        $r.Kind = 'REP'
    }
    [void]$kept.Add($r)
}
$records = $kept

# dedup: pktmon records one frame at multiple NDIS points
$groups = $records | Group-Object { '{0}|{1}|{2}|{3}|{4}|{5}' -f $_.Kind, $_.SrcIp, $_.DstIp, $_.SrcPort, $_.DstPort, $_.IpId }

$identities = foreach ($g in $groups) {
    $f = $g.Group | Sort-Object Tick | Select-Object -First 1
    [pscustomobject]@{
        Kind     = $f.Kind
        Copies   = $g.Count
        FirstTick = ($g.Group | Measure-Object Tick -Minimum).Minimum
        LastTick  = ($g.Group | Measure-Object Tick -Maximum).Maximum
        SrcMac   = $f.SrcMac
        DstMac   = $f.DstMac
        SrcIp    = $f.SrcIp
        DstIp    = $f.DstIp
        SrcPort  = $f.SrcPort
        DstPort  = $f.DstPort
        Ttl      = $f.Ttl
        IpId     = $f.IpId
        UdpLen   = $f.UdpLen
        PayLen   = $f.PayLen
        CapPay   = $f.CapPay
        FrameLen = $f.FrameLen
        Hex      = $f.Hex
        Ascii    = $f.Ascii
    }
}
$identities = @($identities | Sort-Object Kind, FirstTick)

$reqIds = @($identities | Where-Object { $_.Kind -eq 'REQ' })
$repIds = @($identities | Where-Object { $_.Kind -eq 'REP' })

$spanSec = if ($lastTick -and $firstTick) { ($lastTick - $firstTick) / 1000000.0 } else { 0 }

Write-Host ''
Write-Host '=== pcapng discovery handshake ===' -ForegroundColor Cyan
Write-Host ("file            : {0}" -f (Resolve-Path $Pcap))
Write-Host ("bytes           : {0}" -f $bytes.Length)
Write-Host ("EPB total       : {0}" -f $epb)
Write-Host ("truncated frames: {0}  (capLen != origLen)" -f $truncated)
Write-Host ("window span     : {0:N3} s" -f $spanSec)
Write-Host ("raw records     : {0}  (REQ {1} / REP {2})" -f $records.Count, @($records | Where-Object Kind -eq 'REQ').Count, @($records | Where-Object Kind -eq 'REP').Count)
Write-Host ("identities      : {0}  (REQ {1} / REP {2})" -f $identities.Count, $reqIds.Count, $repIds.Count)
Write-Host ''

if ($reqIds.Count -gt 0) {
    $r = $reqIds[0]
    Write-Host '--- REQ (client -> broadcast) ---'
    Write-Host ("src {0}:{1} -> {2}:{3}  mac {4} -> {5}  ipid={6} payLen={7} copies={8}" -f $r.SrcIp, $r.SrcPort, $r.DstIp, $r.DstPort, $r.SrcMac, $r.DstMac, $r.IpId, $r.PayLen, $r.Copies)
    Write-Host ("payload hex : {0}" -f $r.Hex)
}

if ($repIds.Count -gt 0) {
    Write-Host ''
    Write-Host '--- REP (host -> client, unicast) ---'
    $g0 = $repIds | Group-Object { '{0}|{1}|{2}|{3}' -f $_.SrcIp, $_.SrcPort, $_.DstIp, $_.DstPort }
    foreach ($gg in $g0) {
        $one = $gg.Group[0]
        Write-Host ("src {0}:{1} -> {2}:{3}  mac {4} -> {5}  ttl={6}" -f $one.SrcIp, $one.SrcPort, $one.DstIp, $one.DstPort, $one.SrcMac, $one.DstMac, $one.Ttl)
        Write-Host ("  identities={0}  udpLen={1}  payloadBytes={2}  capturedPayload={3}  frameLen={4}" -f $gg.Count, $one.UdpLen, $one.PayLen, $one.CapPay, $one.FrameLen)
    }
    $ipids = $repIds | Sort-Object IpId
    Write-Host ("  ipid range  : {0} .. {1}   (unique {2})" -f $ipids[0].IpId, $ipids[-1].IpId, $ipids.Count)
    $copies = $repIds | Group-Object Copies
    Write-Host ("  copies dist : {0}" -f (($copies | ForEach-Object { "x$($_.Name)->$($_.Count) identities" }) -join ' ; '))
    $firstRep = ($repIds | Measure-Object FirstTick -Minimum).Minimum
    $lastRep  = ($repIds | Measure-Object LastTick -Maximum).Maximum
    Write-Host ("  burst span  : {0:N3} ms" -f (($lastRep - $firstRep) / 1000.0))
    if ($reqIds.Count -gt 0) {
        $tReq = ($reqIds | Measure-Object FirstTick -Minimum).Minimum
        Write-Host ("  T_response  : {0:N3} ms   (first REQ -> first REP, same capture clock)" -f (($firstRep - $tReq) / 1000.0))
    }
    $trunc = $repIds | Where-Object { $_.CapPay -lt $_.PayLen }
    if ($trunc.Count -gt 0) {
        Write-Host ("  TRUNCATED   : {0}/{1} reply identities carry fewer captured bytes than the UDP payload" -f $trunc.Count, $repIds.Count) -ForegroundColor Yellow
        Write-Host ("                captured {0} of {1} payload bytes -- recapture with --pkt-size 0 for the whole payload" -f $trunc[0].CapPay, $trunc[0].PayLen) -ForegroundColor Yellow
    }
    Write-Host ''
    Write-Host '--- REP payload (first captured bytes) ---'
    Write-Host ("hex   : {0}" -f $repIds[0].Hex)
    Write-Host ("ascii : {0}" -f $repIds[0].Ascii)
    $uniqHex = @($repIds | Group-Object Hex).Count
    Write-Host ("distinct captured payloads across all replies: {0}" -f $uniqHex)
}

$out = $identities | Select-Object Kind, Copies, FirstTick, LastTick,
    @{n = 'SpanTicks'; e = { $_.LastTick - $_.FirstTick } },
    SrcMac, DstMac, SrcIp, DstIp, SrcPort, DstPort, Ttl, IpId, UdpLen, PayLen, CapPay, FrameLen, Hex, Ascii
$out | Export-Csv -Path $OutCsv -NoTypeInformation -Encoding UTF8
Write-Host ''
Write-Host ("CSV: {0}" -f $OutCsv) -ForegroundColor Green
Write-Host ("CSV sha256: {0}" -f (Get-FileHash $OutCsv -Algorithm SHA256).Hash)
