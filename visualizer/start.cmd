@echo off
REM Lefty's Screen - Windows.
REM
REM Starts server.py if port 8777 is cold, then opens the page full screen in
REM a throwaway Chrome profile. Closing the window leaves the server warm.
REM
REM NOT YET RUN ON A REAL WINDOWS MACHINE. Written to be correct. When someone
REM runs it and reports back, this line changes and not before.

setlocal
set PORT=8777
set URL=http://127.0.0.1:%PORT%/
set DIR=%~dp0
set LOG=%TEMP%\lefty-visualizer.log
set PROFILE=%TEMP%\lefty-visualizer-chrome-profile

REM --- python ---------------------------------------------------------------
set PY=
where python >nul 2>&1 && set PY=python
if "%PY%"=="" where py >nul 2>&1 && set PY=py
if "%PY%"=="" (
  echo.
  echo   Lefty's screen needs Python 3, and this machine does not have it.
  echo   Everything else still works. Install Python 3 and run this again.
  echo.
  pause
  exit /b 1
)

REM --- server ---------------------------------------------------------------
curl -s -o nul --max-time 1 http://127.0.0.1:%PORT%/state
if %ERRORLEVEL%==0 (
  echo screen server already up on %PORT%
) else (
  echo starting the screen -^> %LOG%
  start "" /b %PY% "%DIR%server.py" >> "%LOG%" 2>&1
  REM give it a moment to bind the port
  timeout /t 3 /nobreak >nul
)

curl -s -o nul --max-time 1 http://127.0.0.1:%PORT%/state
if not %ERRORLEVEL%==0 (
  echo The screen server did not start. Last lines of the log:
  type "%LOG%"
  echo.
  pause
  exit /b 1
)

REM --- browser --------------------------------------------------------------
set CHROME=
if exist "%ProgramFiles%\Google\Chrome\Application\chrome.exe" set CHROME=%ProgramFiles%\Google\Chrome\Application\chrome.exe
if exist "%ProgramFiles(x86)%\Google\Chrome\Application\chrome.exe" set CHROME=%ProgramFiles(x86)%\Google\Chrome\Application\chrome.exe

if not "%CHROME%"=="" (
  rmdir /s /q "%PROFILE%" 2>nul
  start "" "%CHROME%" --user-data-dir="%PROFILE%" --no-first-run --no-default-browser-check --disable-session-crashed-bubble --disable-infobars --autoplay-policy=no-user-gesture-required --kiosk "%URL%"
) else (
  echo Chrome not found, opening your default browser instead.
  echo Press F11 for full screen.
  start "" "%URL%"
)

endlocal
