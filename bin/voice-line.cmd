@echo off
REM Windows twin of voice-line.sh. Filled in by the installer.
if not exist "%USERPROFILE%\lefty\voice-line" (
  echo.
  echo   The voice piece is not installed yet.
  echo   Run this from the lefty-in-a-box folder to add it:
  echo.
  echo       claude "set me up"
  echo.
  pause
  exit /b 1
)
cd /d "%USERPROFILE%\lefty\voice-line"
call run-voice-line.cmd
echo.
pause
