# gui-key.ps1 - send keystrokes to the Civ6 window (bounded synthetic-host experiment only).
# Keyboard works where synthetic mouse clicks are silently ignored by the game.
param(
    [string]$Keys = "{RIGHT}",
    [int]$WindowHandle = 11012632,
    [int]$Count = 1,
    [int]$DelayMs = 350
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class KeyHelper {
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int c);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
}
"@
try { [KeyHelper]::SetProcessDPIAware() | Out-Null } catch {}
$h = [IntPtr]$WindowHandle
[KeyHelper]::ShowWindow($h, 9) | Out-Null
[KeyHelper]::BringWindowToTop($h) | Out-Null
[KeyHelper]::SetForegroundWindow($h) | Out-Null
Start-Sleep -Milliseconds 500
$fg = [KeyHelper]::GetForegroundWindow()
Write-Host ("foreground={0} target={1} match={2}" -f $fg, $h, ($fg -eq $h))
for ($i = 0; $i -lt $Count; $i++) {
    [System.Windows.Forms.SendKeys]::SendWait($Keys)
    Write-Host ("key {0}: {1}" -f ($i + 1), $Keys)
    Start-Sleep -Milliseconds $DelayMs
}
Write-Host "done"
