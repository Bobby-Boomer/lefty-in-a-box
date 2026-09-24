@echo off
REM Lefty's Voice launcher - Windows.
REM
REM Starts the speech server and the text-to-speech server if they are cold,
REM then runs the voice line. Closing this window stops everything it started.
REM
REM NOT YET RUN ON A REAL WINDOWS MACHINE. Written to match start.sh, which is
REM proven on macOS. Report what actually happens and this line changes.

setlocal enabledelayedexpansion
set DIR=%~dp0
set WHISPER_PORT=2022
set KOKORO_PORT=8880

echo.
echo [voice-line] starting up

REM --- find whisper ----------------------------------------------------------
set WHISPER_BIN=
where whisper-server >nul 2>&1 && set WHISPER_BIN=whisper-server
if exist "%USERPROFILE%\whisper.cpp\build\bin\Release\whisper-server.exe" set WHISPER_BIN=%USERPROFILE%\whisper.cpp\build\bin\Release\whisper-server.exe
if exist "%USERPROFILE%\whisper.cpp\build\bin\whisper-server.exe" set WHISPER_BIN=%USERPROFILE%\whisper.cpp\build\bin\whisper-server.exe

set WHISPER_MODEL=
if exist "%USERPROFILE%\lefty\whisper-models\ggml-base.en.bin" set WHISPER_MODEL=%USERPROFILE%\lefty\whisper-models\ggml-base.en.bin
if exist "%USERPROFILE%\whisper.cpp\models\ggml-base.en.bin" set WHISPER_MODEL=%USERPROFILE%\whisper.cpp\models\ggml-base.en.bin

if "%WHISPER_BIN%"=="" (
  echo.
  echo   whisper-server is not installed, so Lefty cannot hear you.
  echo   Run the installer in this folder:  install.cmd
  echo.
  pause
  exit /b 1
)
if "%WHISPER_MODEL%"=="" (
  echo.
  echo   The speech model is missing, so Lefty cannot hear you.
  echo   Run the installer in this folder:  install.cmd
  echo.
  pause
  exit /b 1
)

REM --- whisper server --------------------------------------------------------
curl -sf "http://localhost:%WHISPER_PORT%/health" >nul 2>&1
if %ERRORLEVEL%==0 (
  echo [voice-line] whisper already running on %WHISPER_PORT%
) else (
  echo [voice-line] starting whisper on %WHISPER_PORT%
  start "lefty-whisper" /min "%WHISPER_BIN%" --model "%WHISPER_MODEL%" --port %WHISPER_PORT% --language en --no-timestamps
  for /l %%i in (1,1,30) do (
    curl -sf "http://localhost:%WHISPER_PORT%/health" >nul 2>&1 && goto :whisper_ok
    timeout /t 1 /nobreak >nul
  )
  echo   whisper did not come up after 30 seconds. Stopping.
  pause
  exit /b 1
)
:whisper_ok

REM --- kokoro ----------------------------------------------------------------
curl -sf "http://localhost:%KOKORO_PORT%/health" >nul 2>&1
if %ERRORLEVEL%==0 (
  echo [voice-line] kokoro already running on %KOKORO_PORT%
) else (
  echo [voice-line] starting kokoro on %KOKORO_PORT%
  start "lefty-kokoro" /min cmd /c "cd /d "%DIR%services\kokoro" && uv run python src\kokoro_server\server.py"
  echo [voice-line] kokoro loads its model in the background, that is normal
)

REM --- the voice line --------------------------------------------------------
cd /d "%DIR%"
echo [voice-line] ready - hold the push-to-talk key and talk
uv run python main.py %*

echo.
echo [voice-line] stopped. Closing the whisper and kokoro windows too.
taskkill /fi "WINDOWTITLE eq lefty-whisper*" >nul 2>&1
taskkill /fi "WINDOWTITLE eq lefty-kokoro*" >nul 2>&1
endlocal
