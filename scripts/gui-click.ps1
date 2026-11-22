# gui-click.ps1 - activate the Civ6 window and click at absolute screen coordinates.
# Used only for the bounded synthetic-host experiment (REV-013 §4): it drives the
# game's own LAN lobby "refresh" button. It sends no network traffic itself.
param(
    [int]$X = 0,
    [int]$Y = 0,
    [int]$WindowHandle = 11012632,
    [int]$Count = 1,
    [int]$DelayMs = 400
)
$ErrorActionPreference = 'Stop'
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class GuiHelper {
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr ctx);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int c);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint dx, uint dy, uint d, UIntPtr e);
  [DllImport("user32.dll")] public static extern bool GetCursorPos(out POINT p);
  public struct POINT { public int X; public int Y; }
  public const uint LEFTDOWN = 0x0002;
  public const uint LEFTUP = 0x0004;
  public static void ClickAt(int x, int y) {
    SetCursorPos(x, y);
    System.Threading.Thread.Sleep(150);
    mouse_event(LEFTDOWN, 0, 0, 0, UIntPtr.Zero);
    System.Threading.Thread.Sleep(80);
    mouse_event(LEFTUP, 0, 0, 0, UIntPtr.Zero);
  }
  public static string CursorPos() {
    POINT p; GetCursorPos(out p);
    return p.X + "," + p.Y;
  }
}
"@
# powershell.exe is DPI-unaware: without this, SetCursorPos coordinates are
# virtualised (/1.5 on this 150% display) and every click lands off-screen.
try { [GuiHelper]::SetProcessDpiAwarenessContext([IntPtr](-4)) | Out-Null } catch { [GuiHelper]::SetProcessDPIAware() | Out-Null }
Write-Host ("dpi-aware set; cursor before = {0}" -f [GuiHelper]::CursorPos())
$h = [IntPtr]$WindowHandle
[GuiHelper]::ShowWindow($h, 9) | Out-Null
[GuiHelper]::BringWindowToTop($h) | Out-Null
[GuiHelper]::SetForegroundWindow($h) | Out-Null
Start-Sleep -Milliseconds 400
$fg = [GuiHelper]::GetForegroundWindow()
Write-Host ("foreground={0} target={1} match={2}" -f $fg, $h, ($fg -eq $h))
for ($i = 0; $i -lt $Count; $i++) {
    [GuiHelper]::ClickAt($X, $Y)
    Write-Host ("click {0}: ({1},{2})" -f ($i + 1), $X, $Y)
    Start-Sleep -Milliseconds $DelayMs
}
$p = New-Object GuiHelper+POINT
[GuiHelper]::GetCursorPos([ref]$p) | Out-Null
Write-Host ("cursor now ({0},{1})" -f $p.X, $p.Y)
