# Windows twin of shortcuts.sh — creates the two desktop shortcuts.
#
#   powershell -ExecutionPolicy Bypass -File install\shortcuts.ps1 -InstallDir "C:\Users\you\lefty\lefty-in-a-box"
#
# Makes:
#   Desktop\Talk to Lefty.lnk    -> runs bin\voice-line.cmd
#   Desktop\Lefty Screen.lnk     -> runs bin\visualizer.cmd
#
# Real .lnk shortcuts, so they get a proper icon and a normal double-click,
# rather than a .bat sitting naked on the desktop.
#
# NOT YET TESTED ON A REAL WINDOWS MACHINE. Written to be correct, but until
# someone runs it on Windows and reports back, the README says Windows is
# untested. Do not claim otherwise.

param(
  [string]$InstallDir = "$env:USERPROFILE\lefty\lefty-in-a-box"
)

$ErrorActionPreference = "Stop"
$desktop = [Environment]::GetFolderPath("Desktop")

if (-not (Test-Path $desktop)) {
  Write-Host "No Desktop folder found - skipping shortcuts."
  exit 0
}

function New-LeftyShortcut {
  param($LinkName, $Target, $Description)

  $linkPath = Join-Path $desktop $LinkName
  $shell = New-Object -ComObject WScript.Shell
  $sc = $shell.CreateShortcut($linkPath)
  $sc.TargetPath       = "cmd.exe"
  $sc.Arguments        = "/c `"$Target`""
  $sc.WorkingDirectory = $InstallDir
  $sc.Description      = $Description
  # Use the repo icon if the installer put one there; otherwise Windows picks.
  $icon = Join-Path $InstallDir "assets\lefty.ico"
  if (Test-Path $icon) { $sc.IconLocation = $icon }
  $sc.Save()
  Write-Host "  created: $linkPath"
}

New-LeftyShortcut `
  -LinkName "Talk to Lefty.lnk" `
  -Target (Join-Path $InstallDir "bin\voice-line.cmd") `
  -Description "Hold the key, talk, let go."

New-LeftyShortcut `
  -LinkName "Lefty Screen.lnk" `
  -Target (Join-Path $InstallDir "bin\visualizer.cmd") `
  -Description "Lefty's full-screen face."

Write-Host ""
Write-Host "Two shortcuts are on your desktop now."
Write-Host ""
Write-Host "  Talk to Lefty     hold the key, talk, let go"
Write-Host "  Lefty Screen      the full-screen face"
Write-Host ""
Write-Host "THE FIRST TIME you open one, Windows SmartScreen may show a blue"
Write-Host "'Windows protected your PC' box. That is normal for anything without"
Write-Host "a paid code-signing certificate. To get past it once:"
Write-Host ""
Write-Host "  Click 'More info'  ->  'Run anyway'"
Write-Host ""
