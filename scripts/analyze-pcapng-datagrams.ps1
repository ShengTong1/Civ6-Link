# pcapng 发现包逐数据报解析（网络字节序 + 整数 tick + 帧哈希自检）
# 输出：M0A\captures\E1-pcapng-datagrams.csv + 控制台摘要
#
# 版本：v3（2026-11-11，依 REV-002-E1-PCAPNG-REVIEW-2 的 N-1/N-2 修订）
#   N-1：时间戳以 Int64 tick 保存（不再转 double/科学计数法），逐身份导出
#        FirstTick / LastTick / SpanTicks，摘要按 tick 换算 µs；并解析 IDB 的 if_tsresol。
#   N-2：为每条捕获记录计算「捕获帧字节」的 SHA256（不含 EPB 时间戳/块元数据），
#        并对每个数据报身份断言去重后帧哈希唯一值为 1，把判据变成可复现的。
param(
    [string]$Pcap = "C:\Users\dd\Desktop\injciv6-v0.3.3\M0A\captures\E1-pcapng-20261111_201146.pcapng",
    [string]$OutCsv = "C:\Users\dd\Desktop\injciv6-v0.3.3\M0A\captures\E1-pcapng-datagrams.csv"
)
$ErrorActionPreference = 'Continue'
$bytes = [IO.File]::ReadAllBytes($Pcap)

# --- if_tsresol：默认 6 = 微秒（pcapng 规范默认值）；IDB option code 9 可覆盖 ---
$tsresol = 6
$sha = [System.Security.Cryptography.SHA256]::Create()

$recs = New-Object System.Collections.ArrayList
$off = 0
$epb = 0
$idb = 0
while ($off + 12 -le $bytes.Length) {
    $btype = [BitConverter]::ToUInt32($bytes, $off)   # pcapng 块头是小端（文件格式约定）
    $blen  = [BitConverter]::ToUInt32($bytes, $off + 4)
    if ($blen -lt 12 -or ($off + $blen) -gt $bytes.Length) { break }

    if ($btype -eq 1) {
        # IDB：块体 = linktype(2) + reserved(2) + snaplen(4) + options
        $idb++
        $o = $off + 8 + 8
        while ($o + 4 -le $off + $blen - 4) {
            $ocode = [BitConverter]::ToUInt16($bytes, $o)
            $olen  = [BitConverter]::ToUInt16($bytes, $o + 2)
            if ($ocode -eq 0 -or $olen -eq 0) { break }
            if ($ocode -eq 9 -and $olen -ge 1) { $tsresol = [int]$bytes[$o + 4] }
            $pad = 0
            if (($olen % 4) -ne 0) { $pad = 4 - ($olen % 4) }
            $o += 4 + $olen + $pad
        }
    }

    if ($btype -eq 6) {
        $epb++
        $capLen = [BitConverter]::ToUInt32($bytes, $off + 20)
        $tsHigh = [BitConverter]::ToUInt32($bytes, $off + 12)
        $tsLow  = [BitConverter]::ToUInt32($bytes, $off + 16)
        # N-1：Int64 tick，保持原始整数精度
        $tsTicks = ([int64]$tsHigh -shl 32) -bor [int64]$tsLow
        $d = $off + 28
        if ($capLen -ge 42) {
            $et = ([int]$bytes[$d+12] -shl 8) -bor [int]$bytes[$d+13]   # 以太网类型：网络字节序
            if ($et -eq 0x0800) {
                $ipl = ($bytes[$d+14] -band 0x0f) * 4
                if ($bytes[$d+14+9] -eq 17) {
                    $ip  = $d + 14
                    # IPv4 ID：网络字节序（大端）
                    $ipId = ([int]$bytes[$ip+4] -shl 8) -bor [int]$bytes[$ip+5]
                    $frag = ([int]$bytes[$ip+6] -shl 8) -bor [int]$bytes[$ip+7]
                    $ttl  = $bytes[$ip+8]
                    $fragOff = $frag -band 0x1fff
                    $mf = ($frag -band 0x2000) -ne 0
                    $srcIp = "{0}.{1}.{2}.{3}" -f $bytes[$ip+12], $bytes[$ip+13], $bytes[$ip+14], $bytes[$ip+15]
                    $dstIp = "{0}.{1}.{2}.{3}" -f $bytes[$ip+16], $bytes[$ip+17], $bytes[$ip+18], $bytes[$ip+19]
                    $udp = $ip + $ipl
                    $sport = ([int]$bytes[$udp] -shl 8) -bor [int]$bytes[$udp+1]
                    $dport = ([int]$bytes[$udp+2] -shl 8) -bor [int]$bytes[$udp+3]
                    $ulen  = ([int]$bytes[$udp+4] -shl 8) -bor [int]$bytes[$udp+5]
                    $payLen = [math]::Min([math]::Max($ulen - 8, 0), 64)
                    $pay = ""
                    for ($z = 0; $z -lt $payLen; $z++) { $pay += ("{0:x2}" -f $bytes[$udp+8+$z]) }
                    $dstMac = "{0:x2}:{1:x2}:{2:x2}:{3:x2}:{4:x2}:{5:x2}" -f $bytes[$d], $bytes[$d+1], $bytes[$d+2], $bytes[$d+3], $bytes[$d+4], $bytes[$d+5]
                    $srcMac = "{0:x2}:{1:x2}:{2:x2}:{3:x2}:{4:x2}:{5:x2}" -f $bytes[$d+6], $bytes[$d+7], $bytes[$d+8], $bytes[$d+9], $bytes[$d+10], $bytes[$d+11]
                    if ($dport -ge 62900 -and $dport -le 62999 -and $pay -eq "8de8fc70") {
                        # N-2：捕获帧字节（$d .. $d+capLen-1）的 SHA256，不含 EPB 头/时间戳
                        $frameBuf = New-Object byte[] $capLen
                        [Array]::Copy($bytes, $d, $frameBuf, 0, $capLen)
                        $frameHash = ([BitConverter]::ToString($sha.ComputeHash($frameBuf)) -replace '-', '')
                        [void]$recs.Add([pscustomobject]@{
                            Record = $epb; TsTicks = $tsTicks; SrcMac = $srcMac; DstMac = $dstMac
                            SrcIp = $srcIp; DstIp = $dstIp; IpId = $ipId; Ttl = $ttl
                            Frag = $frag; FragOff = $fragOff; MF = $mf
                            SrcPort = $sport; DstPort = $dport; UdpLen = $ulen; Payload = $pay
                            FrameLen = $capLen; FrameSha256 = $frameHash
                        })
                    }
                }
            }
        }
    }
    $off += $blen
}
$tickUs = if ($tsresol -gt 0) { [math]::Pow(10, $tsresol) } else { 1 }
"总 EPB = $epb ; 发现包匹配记录 = $($recs.Count) ; IDB = $idb ; if_tsresol = $tsresol"
if ($tsresol -ne 6) { "  !! if_tsresol=$tsresol（非默认 6），tick->µs 换算已按 10^$tsresol 调整" }

# 逐数据报身份归并：键 = (SrcIp, IpId, SrcPort, DstPort, Payload)
$groups = $recs | Group-Object { "$($_.SrcIp)|$($_.IpId)|$($_.SrcPort)|$($_.DstPort)|$($_.Payload)" }
"数据报身份 = $($groups.Count)"
$dg = $groups | ForEach-Object {
    $g = $_.Group | Sort-Object TsTicks
    $ticks = @($g | ForEach-Object { $_.TsTicks })
    [pscustomobject]@{
        SrcIp = $g[0].SrcIp; IpId = $g[0].IpId; SrcPort = $g[0].SrcPort; DstPort = $g[0].DstPort
        Copies = $g.Count; FirstMac = $g[0].SrcMac
        UniqueIpId = (@($g.IpId | Sort-Object -Unique).Count)
        UniqueFrameHash = (@($g.FrameSha256 | Sort-Object -Unique).Count)
        FirstTick = [int64]($ticks | Measure-Object -Minimum).Minimum
        LastTick  = [int64]($ticks | Measure-Object -Maximum).Maximum
        FrameLen = $g[0].FrameLen
    }
} | Sort-Object FirstTick
$dg = $dg | ForEach-Object {
    $_ | Add-Member -NotePropertyName SpanTicks -NotePropertyValue ([int64]($_.LastTick - $_.FirstTick)) -PassThru
}

# --- N-2 自检：每个身份内帧哈希必须唯一 ---
$badHash = @($dg | Where-Object { $_.UniqueFrameHash -ne 1 })
"=== N-2 帧哈希自检 ==="
if ($badHash.Count -eq 0) {
    "  ✅ 全部 $($dg.Count) 个数据报身份：副本帧 SHA256 去重后 = 1（帧字节完全一致，可复现）"
} else {
    "  ❌ $($badHash.Count) 个身份帧哈希不唯一："
    $badHash | ForEach-Object { "     DstPort={0} SrcIp={1} Copies={2} UniqueFrameHash={3}" -f $_.DstPort, $_.SrcIp, $_.Copies, $_.UniqueFrameHash }
}

# --- N-1 摘要：按 tick 统计副本时间跨度（整数，不用浮点）---
"=== N-1 副本时间跨度（tick，1 tick = {0} µs）===" -f ([math]::Round(1000000.0 / $tickUs, 3))
$dg | Group-Object SpanTicks | Sort-Object { [int64]$_.Name } | ForEach-Object {
    "    {0} tick × {1} 个身份  ({2:N3} µs)" -f $_.Name, $_.Count, ([double]$_.Name * 1000000.0 / $tickUs)
}
"  → 最大跨度 = {0} tick（{1:N3} µs）" -f (($dg | Measure-Object SpanTicks -Maximum).Maximum), ([double](($dg | Measure-Object SpanTicks -Maximum).Maximum) * 1000000.0 / $tickUs)

# 按轮分组（间隔 > 100 ms，用 tick 判断：100 ms = 0.1 * tickUs）
$t0 = $dg[0].FirstTick
$roundGapTicks = [int64](0.1 * $tickUs)
$rounds = @(); $cur = @(); $prev = $null
foreach ($x in $dg) {
    if ($prev -ne $null -and ($x.FirstTick - $prev.FirstTick) -gt $roundGapTicks) { $rounds += ,($cur); $cur = @() }
    $cur += $x; $prev = $x
}
if ($cur.Count) { $rounds += ,($cur) }
"轮数 = $($rounds.Count)"
$ri = 0
foreach ($r in $rounds) {
    $ri++
    $ports = @($r.DstPort | Sort-Object -Unique)
    $miss = @((62900..62999) | Where-Object { $ports -notcontains $_ })
    $bySrc = ($r | Group-Object SrcIp | ForEach-Object { "$($_.Name)=$($_.Count)" }) -join ", "
    $spanTicks = [int64]($r[-1].FirstTick - $r[0].FirstTick)
    "  轮{0}: 数据报={1,3} 端口={2,3} 缺={3} 跨度={4} tick ({5,7:N3}ms) 起始=+{6,8:N3}s 源端口={7} 源IP分布: {8}" -f `
        $ri, $r.Count, $ports.Count, $miss.Count, $spanTicks, ($spanTicks * 1000.0 / $tickUs), (($r[0].FirstTick - $t0) * 1000000.0 / $tickUs / 1e6), $r[0].SrcPort, $bySrc
}

# 逐轮 IP ID 序列（网络字节序）与相邻差值
$ri = 0
foreach ($r in $rounds) {
    $ri++
    $s = $r | Sort-Object DstPort
    $diffs = @()
    for ($k = 1; $k -lt $s.Count; $k++) { $diffs += ($s[$k].IpId - $s[$k-1].IpId) }
    "=== 轮 $ri 的 IP ID（网络字节序，按目的端口排序）前 10 个 ==="
    $s | Select-Object -First 10 | ForEach-Object { "    :{0} IpId={1} SrcIp={2}" -f $_.DstPort, $_.IpId, $_.SrcIp }
    "    差值分布: " + (($diffs | Group-Object | Sort-Object Count -Descending | Select-Object -First 5 | ForEach-Object { "$($_.Name)×$($_.Count)" }) -join ", ")
}

# 为 CSV 补 Round / PortOrder / IpIdDelta
$ri2 = 0
foreach ($r in $rounds) {
    $ri2++
    $s = $r | Sort-Object DstPort
    $prevId = $null
    $po = 0
    foreach ($x in $s) {
        $x | Add-Member -NotePropertyName Round -NotePropertyValue $ri2 -Force
        $x | Add-Member -NotePropertyName PortOrder -NotePropertyValue $po -Force
        if ($prevId -eq $null) {
            $x | Add-Member -NotePropertyName IpIdDelta -NotePropertyValue $null -Force
        } else {
            $x | Add-Member -NotePropertyName IpIdDelta -NotePropertyValue ($x.IpId - $prevId) -Force
        }
        $prevId = $x.IpId
        $po++
    }
}
# 把 SpanTicks 换算成 µs 供阅读（保留 tick 原值）
$dg = $dg | ForEach-Object {
    $_ | Add-Member -NotePropertyName SpanUs -NotePropertyValue ([math]::Round([double]$_.SpanTicks * 1000000.0 / $tickUs, 3)) -PassThru
}

# 每数据报副本数分布
"=== 副本数分布 ==="
$dg | Group-Object Copies | Sort-Object { [int]$_.Name } | ForEach-Object { "    {0} 份 × {1} 个数据报" -f $_.Name, $_.Count }
"=== 源地址计数（数据报身份级）==="
$dg | Group-Object SrcIp | ForEach-Object { "    {0} : {1}" -f $_.Name, $_.Count }
"=== 源地址计数（原始记录级）==="
$recs | Group-Object SrcIp | ForEach-Object { "    {0} : {1}" -f $_.Name, $_.Count }
"=== 源 IP × 源 MAC 交叉（原始记录级）==="
$recs | Group-Object { "$($_.SrcIp) / $($_.SrcMac)" } | ForEach-Object { "    {0} : {1}" -f $_.Name, $_.Count }
"=== 目的地址汇总（原始记录级）==="
$recs | Group-Object DstIp | ForEach-Object { "    DstIp {0} : {1}" -f $_.Name, $_.Count }
$recs | Group-Object DstMac | ForEach-Object { "    DstMac {0} : {1}" -f $_.Name, $_.Count }
"=== IP 分片检查（发现包不应分片）==="
$fragGroups = $recs | Group-Object { "FragOff=$($_.FragOff) MF=$($_.MF)" }
$fragGroups | ForEach-Object { "    {0} : {1}" -f $_.Name, $_.Count }

$dg | Select-Object Round, PortOrder, DstPort, SrcIp, FirstMac, IpId, IpIdDelta, SrcPort, Copies,
    UniqueIpId, UniqueFrameHash, FrameLen, FirstTick, LastTick, SpanTicks, SpanUs |
    Export-Csv -Path $OutCsv -NoTypeInformation -Encoding UTF8
"明细已导出: $OutCsv"
"SHA256(脚本) 由外部计算"
