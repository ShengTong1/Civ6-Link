# analyze-room-advert.ps1  (v2, 2026-11-13)
# Decode Civ6 LAN room advertisement (the 1104-byte reply to a discovery request).
#
# WHY v2: v1 assumed the 1104-byte datagram was "164 B header + 940 B content".
# That framing made every declared record length disagree with the measured one
# (EnabledMods declared 17984 / measured 18022, off by 22*2=44... actually 38),
# and every JSON blob failed ConvertFrom-Json with "' : ' or '}' expected".
# Root cause: each page carries a 2-byte zero FOOTER at offset 1102..1103, so the
# real content payload is 938 B, not 940 B. Stripping the footer makes the record
# framing exact (13 records consume exactly 19990 B of 22*938=20636 B, tail all 0)
# and all four JSON blobs parse.
#
# Page layout (all integers little-endian, verified against 22 captured pages):
#   [0]    u32  magic            0x9B696059
#   [4]    u32  appid            289070  (Civ6 Steam AppID)
#   [8]    u32  (0)              constant in this capture, semantics unverified
#   [12]   u32  3                constant in this capture, semantics unverified
#   [16]   u32  1                constant in this capture, semantics unverified
#   [20]   u32  6                constant in this capture, semantics unverified
#   [24]   22 B UTF-8 room/player name, zero padded  -> "dingzihan2022的游戏"
#   [46]   106 B zero padding
#   [152]  u32  record count     13
#   [156]  u32  page count       22
#   [160]  u32  page index       0..21
#   [164]  938 B content (record stream, byte-identical semantics across pages)
#   [1102] 2 B  zero footer
#
# Record stream: repeated { u32 nameLen; ASCII name; u32 valueLen; value bytes }
# terminated by nameLen == 0; remaining bytes are zero padding.
#
# Usage:
#   .\analyze-room-advert.ps1 -ReplyDir <dir with reply-NN.bin> [-OutFile <txt>]
#
# Read-only. No admin. No network access.

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$ReplyDir,
    [string]$OutFile = '',
    [int]$PageSize = 1104,
    [int]$HeaderSize = 164,
    [int]$FooterSize = 2
)

$ErrorActionPreference = 'Stop'

function U32($b, $o) { return ([uint32]$b[$o]) -bor ([uint32]$b[$o+1] -shl 8) -bor ([uint32]$b[$o+2] -shl 16) -bor ([uint32]$b[$o+3] -shl 24) }

$lines = New-Object System.Collections.Generic.List[string]
function Say([string]$s) { $lines.Add($s); Write-Host $s }

Say "=== Civ6 LAN room advertisement analysis (v2) ==="
Say ("analyzer run at {0}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
Say ("reply dir  : {0}" -f $ReplyDir)

$files = @(Get-ChildItem -Path $ReplyDir -Filter 'reply-*.bin' | Sort-Object Name)
if ($files.Count -eq 0) { throw "no reply-*.bin under $ReplyDir" }
$pages = @()
foreach ($f in $files) { $pages += ,([IO.File]::ReadAllBytes($f.FullName)) }
Say ("pages found: {0}" -f $pages.Count)

# ---- layout assertions -------------------------------------------------------
$contentLen = $PageSize - $HeaderSize - $FooterSize
$bad = @()
for ($i = 0; $i -lt $pages.Count; $i++) {
    $p = $pages[$i]
    if ($p.Length -ne $PageSize) { $bad += "page $i length=$($p.Length) expected $PageSize" }
    for ($k = 0; $k -lt $HeaderSize; $k++) { if ($i -gt 0 -and $p[$k] -ne $pages[0][$k] -and -not ($k -ge 160 -and $k -lt 164)) { $bad += "page $i header byte $k differs" ; break } }
    for ($k = $HeaderSize + $contentLen; $k -lt $PageSize; $k++) { if ($p[$k] -ne 0) { $bad += "page $i footer byte $k nonzero"; break } }
    if ((U32 $p 156) -ne $pages.Count) { $bad += "page $i pageCount=$(U32 $p 156) != $($pages.Count)" }
}

Say "`n--- page header (page 01) ---"
$h = $pages[0]
Say ("  [0]   magic   = 0x{0:X8}" -f (U32 $h 0))
Say ("  [4]   appid   = {0}" -f (U32 $h 4))
Say ("  [8]   u32     = {0}" -f (U32 $h 8))
Say ("  [12]  u32     = {0}" -f (U32 $h 12))
Say ("  [16]  u32     = {0}" -f (U32 $h 16))
Say ("  [20]  u32     = {0}" -f (U32 $h 20))
Say ("  [24]  name    = '{0}' (22 B UTF-8, zero padded)" -f ([Text.Encoding]::UTF8.GetString($h,24,22)))
Say ("  [46]  zero pad 106 B : {0}" -f ((($h[46..151] | Where-Object {$_ -ne 0}).Count) -eq 0))
Say ("  [152] recordCnt = {0}" -f (U32 $h 152))
Say ("  [156] pageCount = {0}" -f (U32 $h 156))
Say ("  [160] pageIndex = {0}" -f (U32 $h 160))
Say ("  [1102] footer    = 00 00 (2 B)")
Say ("  content per page = {0} B (1104 - 164 header - 2 footer)" -f $contentLen)

$idx = @(); foreach ($p in $pages) { $idx += (U32 $p 160) }
Say ("`n  page indexes            : {0}" -f ($idx -join ','))
Say ("  indexes are exactly 0..N-1 : {0}" -f ((($idx -join ',') -eq ((0..($pages.Count-1)) -join ','))))

# ---- reassemble content ------------------------------------------------------
$ms = New-Object System.IO.MemoryStream
foreach ($p in $pages) { $ms.Write($p, $HeaderSize, $contentLen) }
$c = $ms.ToArray()
$ms.Dispose()
$streamPath = Join-Path $ReplyDir 'room-advert-content.bin'
[IO.File]::WriteAllBytes($streamPath, $c)
$sha = (Get-FileHash -LiteralPath $streamPath -Algorithm SHA256).Hash
Say ("`n--- reassembled content ---")
Say ("  content length = {0} B  ({1} pages x {2} B)" -f $c.Length, $pages.Count, $contentLen)
Say ("  written to     = {0}" -f $streamPath)
Say ("  SHA256         = {0}" -f $sha)

# ---- record stream -----------------------------------------------------------
Say "`n--- records ---"
$recs = New-Object System.Collections.Generic.List[object]
$off = 0; $framingOk = $true
while ($off + 4 -le $c.Length) {
    $nl = U32 $c $off
    if ($nl -eq 0) { break }
    if ($nl -gt 64 -or ($off + 4 + $nl + 4) -gt $c.Length) { $framingOk = $false; break }
    $name = [Text.Encoding]::ASCII.GetString($c, $off + 4, $nl)
    $off = $off + 4 + $nl
    $vl = U32 $c $off; $off += 4
    if ($off + $vl -gt $c.Length) { $framingOk = $false; break }
    $raw = New-Object byte[] $vl
    [Array]::Copy($c, $off, $raw, 0, $vl)
    $off += $vl
    $txt = [Text.Encoding]::UTF8.GetString($raw)
    $recs.Add([pscustomobject]@{ Name = $name; VLen = $vl; Text = $txt; Raw = $raw })
}
$tailLen = $c.Length - $off
$tailZero = $true
if ($tailLen -gt 0) { for ($k = $off; $k -lt $c.Length; $k++) { if ($c[$k] -ne 0) { $tailZero = $false; break } } }

$i = 0
foreach ($r in $recs) {
    $disp = $r.Text
    if ($disp.Length -gt 60) { $disp = $disp.Substring(0,57) + '...' }
    $disp = ($disp -replace "[`r`n`t]", ' ') -replace '[^\x20-\x7e]', '.'
    Say ("  {0,2}  {1,-22} {2,6} B  {3}" -f $i, $r.Name, $r.VLen, $disp)
    $i++
}
Say ("`n  records decoded   : {0}" -f $recs.Count)
Say ("  framing exact     : {0}" -f $framingOk)
Say ("  consumed          : {0} / {1} B" -f $off, $c.Length)
Say ("  trailing bytes    : {0} B  all zero = {1}" -f $tailLen, $tailZero)
Say ("  header recordCnt matches decoded count : {0}" -f ((U32 $h 152) -eq $recs.Count))

# ---- JSON values -------------------------------------------------------------
Say "`n--- JSON values ---"
$jdir = Join-Path $ReplyDir 'json'
New-Item -ItemType Directory -Force -Path $jdir | Out-Null
$jsonOk = 0; $jsonBad = 0
foreach ($r in $recs) {
    $t = $r.Text.TrimStart()
    if (-not ($t.StartsWith('{') -or $t.StartsWith('['))) { continue }
    $valid = $false; $msg = ''
    try { $null = ($r.Text | ConvertFrom-Json); $valid = $true } catch { $msg = $_.Exception.Message }
    if ($valid) { $jsonOk++ } else { $jsonBad++ }
    $p = Join-Path $jdir ($r.Name + '.json')
    [IO.File]::WriteAllText($p, $r.Text, [Text.UTF8Encoding]::new($false))
    Say ("  {0,-18} {1,6} B  valid = {2}  -> {3}" -f $r.Name, $r.VLen, $valid, $p)
    if (-not $valid) { Say ("      ! {0}" -f $msg) }
    if ($valid) {
        $o = $r.Text | ConvertFrom-Json
        if ($r.Name -eq 'EnabledMods') { Say ("      mods = {0}" -f $o.mods.Count) }
        else { Say ("      keys = {0}" -f (($o.PSObject.Properties.Name) -join ',')) }
    }
}
Say ("  JSON blobs valid  : {0}   invalid : {1}" -f $jsonOk, $jsonBad)

# ---- IPv4 scan ---------------------------------------------------------------
Say "`n--- IPv4 scan over the whole reassembled content ---"
# Only dotted-quad text is defensible inside a UTF-8 region: any 4 bytes can
# look like an address, so a binary scan produces pure noise.
$ascii = [Text.Encoding]::GetEncoding(28591).GetString($c)
$hits = [regex]::Matches($ascii, '(?<![\d.])(?:\d{1,3}\.){3}\d{1,3}(?![\d.])')
Say ("  dotted-quad strings found: {0}" -f $hits.Count)
foreach ($m in $hits) { Say ("    offset {0,5} : {1}" -f $m.Index, $m.Value) }
Say ("  binary 4-byte IPv4 fields: not asserted (would be noise in a UTF-8 region)")

# ---- summary -----------------------------------------------------------------
Say "`n--- summary ---"
Say ("  advertisement size : {0} B, carried in {1} datagrams of {2} B" -f (($pages.Count)*$contentLen), $pages.Count, $PageSize)
Say ("  per-page framing   : {0} B header + {1} B content + {2} B zero footer" -f $HeaderSize, $contentLen, $FooterSize)
Say ("  records            : {0}" -f $recs.Count)
Say ("  content SHA256     : {0}" -f $sha)

$warn = New-Object System.Collections.Generic.List[string]
foreach ($b in $bad) { $warn.Add("layout: $b") }
if (-not $framingOk) { $warn.Add("record framing did not terminate cleanly") }
if (-not $tailZero) { $warn.Add("trailing bytes are not all zero") }
if ($jsonBad -gt 0) { $warn.Add("$jsonBad JSON blob(s) failed to parse") }
if ($warn.Count -eq 0) {
    Say "`n--- warnings ---`n  none: layout, framing, padding and all JSON blobs verified"
} else {
    Say "`n--- warnings ---"
    foreach ($w in $warn) { Say ("  ! {0}" -f $w) }
}

if ($OutFile -ne '') {
    [IO.File]::WriteAllText($OutFile, ($lines -join "`r`n") + "`r`n", [Text.UTF8Encoding]::new($true))
    Write-Host "`nwritten: $OutFile"
}
