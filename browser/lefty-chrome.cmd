@echo off
REM The shared browser - Windows.
REM
REM Starts a SECOND Chrome that your AI can see and drive. Your everyday Chrome
REM is never touched.
REM
REM Why a second one: Chrome 136 and later refuse --remote-debugging-port on the
REM default profile. Deliberate security change, no flag turns it off.
REM
REM The debugging port is bound to 127.0.0.1 only, so nothing outside this
REM machine can reach it.
REM
REM NOT YET RUN ON A REAL WINDOWS MACHINE. Written to match the macOS version,
REM which is proven. Tell us what happens and this line changes.

setlocal
if "%LEFTY_CHROME_PORT%"=="" (set PORT=9222) else (set PORT=%LEFTY_CHROME_PORT%)
if "%LEFTY_CHROME_PROFILE%"=="" (set PROFILE=%USERPROFILE%\lefty\chrome-profile) else (set PROFILE=%LEFTY_CHROME_PROFILE%)

set CHROME=
if exist "%ProgramFiles%\Google\Chrome\Application\chrome.exe" set CHROME=%ProgramFiles%\Google\Chrome\Application\chrome.exe
if exist "%ProgramFiles(x86)%\Google\Chrome\Application\chrome.exe" set CHROME=%ProgramFiles(x86)%\Google\Chrome\Application\chrome.exe
if exist "%LOCALAPPDATA%\Google\Chrome\Application\chrome.exe" set CHROME=%LOCALAPPDATA%\Google\Chrome\Application\chrome.exe

if "%CHROME%"=="" (
  echo Google Chrome not found. Install Chrome, then run this again.
  pause
  exit /b 1
)

curl -s -o nul --max-time 2 "http://127.0.0.1:%PORT%/json/version"
if %ERRORLEVEL%==0 (
  echo Already running on port %PORT%. Nothing to do.
  echo Profile: %PROFILE%
  exit /b 0
)

if not exist "%PROFILE%" mkdir "%PROFILE%"

start "" "%CHROME%" --remote-debugging-port=%PORT% --remote-allow-origins=http://127.0.0.1:%PORT% --user-data-dir="%PROFILE%" --use-fake-ui-for-media-stream --no-first-run --no-default-browser-check

for /l %%i in (1,1,30) do (
  curl -s -o nul --max-time 1 "http://127.0.0.1:%PORT%/json/version"
  if !ERRORLEVEL!==0 goto :up
  timeout /t 1 /nobreak >nul
)

echo Chrome started but port %PORT% never answered.
echo Usually that means another Chrome is already using this profile folder.
pause
exit /b 1

:up
echo Chrome is up. Your AI can attach to it now.
echo Port:    %PORT%
echo Profile: %PROFILE%
echo.
echo Log into whatever sites you want it to work in, once, in THIS window.
echo The profile persists, so those logins survive a restart.
endlocal
