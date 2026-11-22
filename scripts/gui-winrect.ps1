# gui-winrect.ps1 - report the Civ6 window/client rectangles in physical screen pixels.
param([int]$WindowHandle = 11012632)
$ErrorActionPreference = 'Stop'
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class WR {
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
  [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool ClientToScreen(IntPtr h, ref POINT p);
  [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr c);
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [DllImport("user32.dll")] public static extern int GetSystemMetrics(int i);
}
"@
try { [WR]::SetProcessDpiAwarenessContext([IntPtr](-4)) | Out-Null } catch { [WR]::SetProcessDPIAware() | Out-Null }
$h = [IntPtr]$WindowHandle
$r = New-Object WR+RECT
[WR]::GetWindowRect($h, [ref]$r) | Out-Null
$c = New-Object WR+RECT
[WR]::GetClientRect($h, [ref]$c) | Out-Null
$p = New-Object WR+POINT
[WR]::ClientToScreen($h, [ref]$p) | Out-Null
Write-Host ("window rect = L={0} T={1} R={2} B={3}  ({4}x{5})" -f $r.Left, $r.Top, $r.Right, $r.Bottom, ($r.Right - $r.Left), ($r.Bottom - $r.Top))
Write-Host ("client rect = {0}x{1}  clientOrigin=({2},{3})" -f $c.Right, $c.Bottom, $p.X, $p.Y)
Write-Host ("virtual screen = {0}x{1} origin=({2},{3})" -f [WR]::GetSystemMetrics(78), [WR]::GetSystemMetrics(79), [WR]::GetSystemMetrics(76), [WR]::GetSystemMetrics(77))
