# gui-sendinput.ps1 - click at absolute screen coords via SendInput (hardware-level injection).
# Civ6 may ignore legacy mouse_event; SendInput with MOUSEEVENTF_ABSOLUTE is closer to a real device.
param(
    [int]$X = 0,
    [int]$Y = 0,
    [int]$WindowHandle = 11012632,
    [int]$Count = 1,
    [int]$DownMs = 120,
    [switch]$Hover
)
$ErrorActionPreference = 'Stop'
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class SI {
  [StructLayout(LayoutKind.Sequential)] public struct MOUSEINPUT { public int dx; public int dy; public uint mouseData; public uint dwFlags; public uint time; public IntPtr dwExtraInfo; }
  [StructLayout(LayoutKind.Sequential)] public struct KEYBDINPUT { public ushort wVk; public ushort wScan; public uint dwFlags; public uint time; public IntPtr dwExtraInfo; }
  [StructLayout(LayoutKind.Explicit)] public struct INPUTUNION { [FieldOffset(0)] public MOUSEINPUT mi; [FieldOffset(0)] public KEYBDINPUT ki; }
  [StructLayout(LayoutKind.Sequential)] public struct INPUT { public uint type; public INPUTUNION u; }
  [DllImport("user32.dll", SetLastError=true)] public static extern uint SendInput(uint n, INPUT[] p, int cb);
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int c);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern int GetSystemMetrics(int i);
  [DllImport("user32.dll")] public static extern bool GetCursorPos(out POINT p);
  public struct POINT { public int X; public int Y; }
  public const uint MOVE=0x0001, LEFTDOWN=0x0002, LEFTUP=0x0004, ABSOLUTE=0x8000, VIRTUALDESK=0x4000;

  static INPUT Mk(uint flags, int nx, int ny) {
    INPUT i = new INPUT();
    i.type = 0;
    i.u.mi.dx = nx; i.u.mi.dy = ny; i.u.mi.mouseData = 0; i.u.mi.dwFlags = flags;
    i.u.mi.time = 0; i.u.mi.dwExtraInfo = IntPtr.Zero;
    return i;
  }
  // Map screen px -> 0..65535 across the whole virtual desktop.
  public static void MoveTo(int x, int y) {
    int vx = GetSystemMetrics(76), vy = GetSystemMetrics(77);
    int vw = GetSystemMetrics(78), vh = GetSystemMetrics(79);
    int nx = (int)Math.Round(((double)(x - vx) * 65535.0) / Math.Max(1, vw - 1));
    int ny = (int)Math.Round(((double)(y - vy) * 65535.0) / Math.Max(1, vh - 1));
    INPUT[] a = new INPUT[1];
    a[0] = Mk(MOVE | ABSOLUTE | VIRTUALDESK, nx, ny);
    SendInput(1, a, Marshal.SizeOf(typeof(INPUT)));
    System.Threading.Thread.Sleep(160);
  }
  public static void Click(int x, int y, int downMs) {
    MoveTo(x, y);
    INPUT[] a = new INPUT[1];
    a[0] = Mk(LEFTDOWN | ABSOLUTE | VIRTUALDESK, 0, 0);
    // dx/dy are ignored for non-MOVE events; recompute not needed
    INPUT[] down = new INPUT[1]; down[0] = Mk(LEFTDOWN, 0, 0);
    INPUT[] up = new INPUT[1]; up[0] = Mk(LEFTUP, 0, 0);
    SendInput(1, down, Marshal.SizeOf(typeof(INPUT)));
    System.Threading.Thread.Sleep(downMs);
    SendInput(1, up, Marshal.SizeOf(typeof(INPUT)));
  }
  public static string Cur() { POINT p; GetCursorPos(out p); return p.X + "," + p.Y; }
}
"@
[SI]::SetProcessDPIAware() | Out-Null
$h = [IntPtr]$WindowHandle
[SI]::ShowWindow($h, 9) | Out-Null
[SI]::BringWindowToTop($h) | Out-Null
[SI]::SetForegroundWindow($h) | Out-Null
Start-Sleep -Milliseconds 500
Write-Host ("foreground={0} target={1} match={2}" -f [SI]::GetForegroundWindow(), $h, ([SI]::GetForegroundWindow() -eq $h))
for ($i = 0; $i -lt $Count; $i++) {
    if ($Hover) {
        [SI]::MoveTo($X, $Y)
        Write-Host ("hover {0}: ({1},{2}) cursor={3}" -f ($i + 1), $X, $Y, [SI]::Cur())
    } else {
        [SI]::Click($X, $Y, $DownMs)
        Write-Host ("sendinput click {0}: ({1},{2}) cursor={3}" -f ($i + 1), $X, $Y, [SI]::Cur())
    }
    Start-Sleep -Milliseconds 500
}
