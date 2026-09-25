# Windows twin of shortcuts.sh — creates the desktop shortcuts.
#
#   powershell -ExecutionPolicy Bypass -File install\shortcuts.ps1 -InstallDir "C:\Users\you\lefty\lefty-in-a-box"
#
# Makes:
#   Desktop\Type to <Name>.lnk   -> runs bin\type-to.cmd      (always)
#   Desktop\<Name> Screen.lnk    -> runs bin\visualizer.cmd   (always)
#   Desktop\Talk to <Name>.lnk   -> runs bin\voice-line.cmd   (only once voice is installed)
#
# <Name> comes from lefty.config.json, written by install\personalize.cmd. It is
# "Lefty" until someone changes it.
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

# What is this agent called? Falls back to Lefty if the config is missing or
# unreadable, because a shortcut with a default name beats no shortcut.
$name = "Lefty"
$config = Join-Path $InstallDir "lefty.config.json"
if (Test-Path $config) {
  try {
    $found = (Get-Content -Raw -LiteralPath $config | ConvertFrom-Json).name
    if ($found) { $name = $found.Trim() }
  } catch { }
}

# Old shortcuts under a previous name would otherwise pile up on the desktop
# every time someone renames their agent. Only ours are removed: the
# description is the marker.
foreach ($old in Get-ChildItem -LiteralPath $desktop -Filter *.lnk -ErrorAction SilentlyContinue) {
  try {
    $sh = New-Object -ComObject WScript.Shell
    if ($sh.CreateShortcut($old.FullName).Description -like "*Lefty in a Box*") {
      Remove-Item -LiteralPath $old.FullName -Force
    }
  } catch { }
}

function New-LeftyShortcut {
  param($LinkName, $Target, $Description)

  $linkPath = Join-Path $desktop $LinkName
  $shell = New-Object -ComObject WScript.Shell
  $sc = $shell.CreateShortcut($linkPath)
  $sc.TargetPath       = "cmd.exe"
  $sc.Arguments        = "/c `"$Target`""
  $sc.WorkingDirectory = $InstallDir
  $sc.Description      = "$Description (Lefty in a Box)"
  # Use the repo icon if the installer put one there; otherwise Windows picks.
  $icon = Join-Path $InstallDir "assets\lefty.ico"
  if (Test-Path $icon) { $sc.IconLocation = $icon }
  $sc.Save()
  Write-Host "  created: $linkPath"
}

New-LeftyShortcut `
  -LinkName "Type to $name.lnk" `
  -Target (Join-Path $InstallDir "bin\type-to.cmd") `
  -Description "Open a normal chat window."

New-LeftyShortcut `
  -LinkName "$name Screen.lnk" `
  -Target (Join-Path $InstallDir "bin\visualizer.cmd") `
  -Description "The full-screen face."

# The voice line only gets an icon once it is actually installed. An icon that
# opens a window to say "not set up yet" is worse than no icon.
$voiceReady = $false
foreach ($v in @("$env:USERPROFILE\lefty\voice-line", (Join-Path $InstallDir "voice-line"))) {
  if (Test-Path (Join-Path $v ".venv")) { $voiceReady = $true; break }
}

if ($voiceReady) {
  New-LeftyShortcut `
    -LinkName "Talk to $name.lnk" `
    -Target (Join-Path $InstallDir "bin\voice-line.cmd") `
    -Description "Hold the key, talk, let go."
}

Write-Host ""
Write-Host "Your shortcuts are on the desktop now."
Write-Host ""
Write-Host "  Type to $name     open a normal chat window"
Write-Host "  $name Screen      the full-screen face"
if ($voiceReady) {
  Write-Host "  Talk to $name     hold the key, talk, let go"
} else {
  Write-Host ""
  Write-Host "No Talk icon yet - the voice piece is not installed. Set it up with"
  Write-Host "voice-line\install.cmd and run this again to get the icon."
}
Write-Host ""
Write-Host "THE FIRST TIME you open one, Windows SmartScreen may show a blue"
Write-Host "'Windows protected your PC' box. That is normal for anything without"
Write-Host "a paid code-signing certificate. To get past it once:"
Write-Host ""
Write-Host "  Click 'More info'  ->  'Run anyway'"
Write-Host ""
