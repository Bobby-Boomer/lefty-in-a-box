@echo off
REM Lefty's Screen launcher - Windows.
REM
REM The screen ships IN this repo, at ..\visualizer, so it works straight after
REM a clone with nothing to build. If the installer put a copy at
REM %USERPROFILE%\lefty\visualizer that one wins.

setlocal
set HERE=%~dp0

if exist "%USERPROFILE%\lefty\visualizer\start.cmd" (
  cd /d "%USERPROFILE%\lefty\visualizer"
  call start.cmd
  exit /b 0
)

if exist "%HERE%..\visualizer\start.cmd" (
  cd /d "%HERE%..\visualizer"
  call start.cmd
  exit /b 0
)

echo.
echo   Could not find the screen.
echo   It should be at %%USERPROFILE%%\lefty\lefty-in-a-box\visualizer.
echo   Run this from the lefty-in-a-box folder to repair it:
echo.
echo       claude "set me up"
echo.
pause
exit /b 1
