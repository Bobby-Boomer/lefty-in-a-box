@echo off
REM Name your agent and pick how it looks - Windows.
REM
REM   install\personalize.cmd
REM
REM Writes lefty.config.json at the repo root. The screen reads the look from
REM it, the desktop shortcut takes the name, and the agent introduces itself by
REM it. Safe to run again any time.
REM
REM NOT YET RUN ON A REAL WINDOWS MACHINE. Written to match personalize.sh.

setlocal enabledelayedexpansion
set ROOT=%~dp0..
set CONFIG=%ROOT%\lefty.config.json

set CUR_NAME=Lefty
set CUR_LOOK=rain
if exist "%CONFIG%" (
  for /f "tokens=1,2" %%a in ('python -c "import json;d=json.load(open(r'%CONFIG%'));print(d.get('name') or 'Lefty', d.get('look') or 'rain')" 2^>nul') do (
    set CUR_NAME=%%a
    set CUR_LOOK=%%b
  )
)

echo.
echo === Make it yours ===
echo.
echo   What do you want to call your agent?
echo   This is the name it answers to and the name on your desktop icons.
echo.
set /p NAME="  Name [%CUR_NAME%]: "
if "%NAME%"=="" set NAME=%CUR_NAME%

echo.
echo   How should the screen look?
echo.
echo     1) rain    green rain, the original
echo     2) amber   warm amber, like an old terminal
echo     3) ice     cold blue, quieter in a dark room
echo     4) violet  violet
echo     5) mono    no colour at all, if the rest is distracting
echo.
echo   You can see any of them first. With the screen running:
echo       http://127.0.0.1:8777/?look=amber
echo.
echo   Currently: %CUR_LOOK%
set /p PICK="  Pick 1-5 [%CUR_LOOK%]: "

set LOOK=%CUR_LOOK%
if "%PICK%"=="1" set LOOK=rain
if "%PICK%"=="2" set LOOK=amber
if "%PICK%"=="3" set LOOK=ice
if "%PICK%"=="4" set LOOK=violet
if "%PICK%"=="5" set LOOK=mono

python -c "import json,os,sys;c=r'%CONFIG%';d={};                     \
(os.path.exists(c) and (lambda: d.update(json.load(open(c))))());      \
d.update({'name':sys.argv[1],'look':sys.argv[2]});                     \
json.dump(d,open(c,'w'),indent=2)" "%NAME%" "%LOOK%"

if not %ERRORLEVEL%==0 (
  echo   Could not write %CONFIG%. Is Python installed?
  pause
  exit /b 1
)

echo.
echo   Saved.
echo     Name: %NAME%
echo     Look: %LOOK%
echo.

if exist "%ROOT%\install\shortcuts.ps1" (
  echo   Rebuilding your desktop shortcuts with the new name...
  powershell -ExecutionPolicy Bypass -File "%ROOT%\install\shortcuts.ps1" -InstallDir "%ROOT%" >nul 2>&1
  if !ERRORLEVEL!==0 (echo   Done.) else (echo   Could not rebuild shortcuts. Run install\shortcuts.ps1 yourself.)
)

echo.
echo   The screen picks up the new look on its next reload.
echo   Run this again any time to change either one.
echo.
pause
endlocal
