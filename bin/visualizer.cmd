@echo off
REM Windows twin of visualizer.sh. Filled in by the installer.
if not exist "%USERPROFILE%\lefty\visualizer" (
  echo.
  echo   The screen piece is not installed yet.
  echo   Run this from the lefty-in-a-box folder to add it:
  echo.
  echo       claude "set me up"
  echo.
  pause
  exit /b 1
)
cd /d "%USERPROFILE%\lefty\visualizer"
call start.cmd
