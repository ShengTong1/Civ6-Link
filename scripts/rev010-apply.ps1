$ErrorActionPreference = 'Continue'
# netsh 在本机输出 GBK；不显式指定解码会把字节按 UTF-8 解成乱码
try { [Console]::OutputEncoding = [Text.Encoding]::GetEncoding(936) } catch { }
$out = Join-Path $PSScriptRoot 'rev010-result.txt'
$L = New-Object System.Collections.Generic.List[string]
function Say($s){ $L.Add([string]$s) }

Say ("# REV-010 targeted destination-cache delete")
Say ("time  : " + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
Say ("admin : " + ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))

Add-Type -TypeDefinition @"
using System; using System.Net; using System.Runtime.InteropServices;
[StructLayout(LayoutKind.Sequential)] public struct ROWX { public uint a,b,c,n,ifIdx,e,f,g,h,m1,m2,m3,m4,m5; }
public class RQ {
 [DllImport("iphlpapi.dll")] public static extern int GetBestRoute(uint d,uint s,out ROWX p);
 [DllImport("iphlpapi.dll")] public static extern int GetBestInterface(uint d, out uint i);
 public static string R(string dst){ uint dd=BitConverter.ToUInt32(IPAddress.Parse(dst).GetAddressBytes(),0); ROWX r; int rc=GetBestRoute(dd,0,out r);
  if(rc!=0) return "err="+rc; return string.Format("if={0} nextHop={1} metric1={2}", r.ifIdx, new IPAddress(BitConverter.GetBytes(r.n)), r.m1); }
 public static int I(string dst){ uint dd=BitConverter.ToUInt32(IPAddress.Parse(dst).GetAddressBytes(),0); uint i; return GetBestInterface(dd,out i)==0?(int)i:-1; }
}
"@ 2>$null

function Snap($tag){
  Say ""
  Say "--- $tag ---"
  Say ("  GetBestInterface 26.187.101.177 = if" + [RQ]::I('26.187.101.177'))
  Say ("  GetBestRoute     26.187.101.177 = " + [RQ]::R('26.187.101.177'))
  $c = (netsh interface ipv4 show destinationcache) -split "`r?`n" | Where-Object { $_ -match '26\.187\.101\.177' }
  if ($c) { foreach ($x in $c) { Say ("  cache: " + $x.Trim()) } } else { Say "  cache: (none for .177)" }
}

Snap 'before'
Say ""
Say "--- netsh interface ipv4 delete destinationcache interface=10 address=26.187.101.177 ---"
$o = & netsh interface ipv4 delete destinationcache interface=10 address=26.187.101.177 2>&1 | Out-String
Say ("  rc = " + $LASTEXITCODE)
foreach ($l in ($o.Trim() -split "`r?`n")) { if ($l.Trim()) { Say ("  " + $l.Trim()) } }
Snap 'after'
Say ""
Say "--- interfaces untouched (no Set-NetIPInterface called) ---"
foreach ($i in 10,18,15) { $r = Get-NetIPInterface -AddressFamily IPv4 -InterfaceIndex $i -ErrorAction SilentlyContinue
  if ($r) { Say ("  if={0,-3} metric={1,-6} auto={2}" -f $i,$r.InterfaceMetric,$r.AutomaticMetric) } }
[IO.File]::WriteAllText($out, ($L -join "`r`n"), [Text.UTF8Encoding]::new($true))