@echo off
REM Type to your agent - Windows.
REM
REM Opens Claude Code in the install folder, which is where agent.md and
REM memory\ live, so it boots as their agent and not as a blank assistant.
REM
REM This is the icon that works for everyone. Voice is optional; memory is not.

setlocal
for %%I in ("%~dp0..") do set ROOT=%%~fI
cd /d "%ROOT%" || exit /b 1

where claude >nul 2>&1
if errorlevel 1 (
  echo.
  echo   Cannot find the 'claude' command, so this icon has nothing to open.
  echo   Install Claude Code, then try this again.
  echo.
  pause
  exit /b 1
)

if not exist "%ROOT%\agent.md" (
  echo.
  echo   Setup has not finished yet - there is no agent.md in this folder.
  echo   Run:  claude "set me up"
  echo.
)

cls
echo.
echo   Reading your memory folder. Say what you need.
echo   Type /exit when you are done.
echo.
claude

echo.
pause
endlocal
