@echo off
REM Lefty's Voice - installer for Windows.
REM
REM   install.cmd
REM
REM HONEST WARNING, READ IT: this has never been run on a real Windows machine,
REM and the whisper.cpp part is genuinely harder here than on a Mac. There is no
REM ready-built whisper for Windows in the project's own releases, so unless you
REM already have one, it has to be compiled. This script will tell you that
REM plainly rather than dying with a confusing error.
REM
REM Everything else - the Python side, Kokoro, the settings file - is the same
REM on every platform and should just work.

setlocal enabledelayedexpansion
set DIR=%~dp0
set MODEL_DIR=%USERPROFILE%\lefty\whisper-models
set MODEL_FILE=%MODEL_DIR%\ggml-base.en.bin
set MODEL_URL=https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin

echo.
echo === Lefty's Voice - setup ===

REM --- 1. uv -----------------------------------------------------------------
echo.
echo [1] Checking for uv (the Python runner)
where uv >nul 2>&1
if %ERRORLEVEL%==0 (
  echo     uv is here. Good.
) else (
  echo     uv is not installed. It is what builds the Python environment.
  echo     Install it with:
  echo         winget install --id=astral-sh.uv -e
  echo     or see https://docs.astral.sh/uv/
  echo.
  echo     Install uv, then run this again.
  pause
  exit /b 1
)

REM --- 2. whisper ------------------------------------------------------------
echo.
echo [2] Checking for whisper-server (speech to text)
set WHISPER_BIN=
where whisper-server >nul 2>&1 && set WHISPER_BIN=whisper-server
if exist "%USERPROFILE%\whisper.cpp\build\bin\Release\whisper-server.exe" set WHISPER_BIN=%USERPROFILE%\whisper.cpp\build\bin\Release\whisper-server.exe
if exist "%USERPROFILE%\whisper.cpp\build\bin\whisper-server.exe" set WHISPER_BIN=%USERPROFILE%\whisper.cpp\build\bin\whisper-server.exe

if not "%WHISPER_BIN%"=="" (
  echo     Found: %WHISPER_BIN%
) else (
  echo     whisper-server is not on this machine.
  echo     It is what turns your speech into text, and it runs locally --
  echo     nothing you say is sent anywhere.
  echo.
  echo     There is no ready-built copy for Windows, so it has to be compiled.
  echo     You need Git, CMake and Visual Studio Build Tools, then:
  echo.
  echo         git clone https://github.com/ggml-org/whisper.cpp %USERPROFILE%\whisper.cpp
  echo         cd %USERPROFILE%\whisper.cpp
  echo         cmake -B build
  echo         cmake --build build --config Release
  echo.
  echo     This is the hard part of the whole install, and nobody has done it
  echo     on Windows for this project yet. If you get it working, please say
  echo     what you had to do -- it goes straight into the docs.
  echo.
  echo     Everything else below is ready. Run this again once whisper builds.
  pause
  exit /b 1
)

REM --- 2b. ffmpeg ------------------------------------------------------------
echo.
echo [2b] Checking for ffmpeg (audio plumbing)
where ffmpeg >nul 2>&1
if %ERRORLEVEL%==0 (
  echo     ffmpeg is here.
) else (
  echo     ffmpeg is missing. The voice line will not start without it.
  echo     Install it with:
  echo         winget install --id=Gyan.FFmpeg -e
  echo.
  echo     Then run this again.
  pause
  exit /b 1
)

REM --- 3. the model ----------------------------------------------------------
echo.
echo [3] Checking for the speech model
if exist "%MODEL_FILE%" (
  echo     Model already here: %MODEL_FILE%
) else (
  echo     The speech model is about 148 MB and downloads once.
  set /p GO="    Download it now? [y/N] "
  if /i "!GO!"=="y" (
    if not exist "%MODEL_DIR%" mkdir "%MODEL_DIR%"
    curl -L --fail -o "%MODEL_FILE%.part" "%MODEL_URL%"
    if !ERRORLEVEL!==0 (
      move /y "%MODEL_FILE%.part" "%MODEL_FILE%" >nul
      echo     Model saved to %MODEL_FILE%
    ) else (
      echo     Download failed. Nothing was changed.
      del "%MODEL_FILE%.part" 2>nul
      pause
      exit /b 1
    )
  ) else (
    echo     Skipped. Voice cannot work without it. Run this again when ready.
    pause
    exit /b 1
  )
)

REM --- 4. python dependencies ------------------------------------------------
echo.
echo [4] Building the Python environment (this is the long one)
echo     Kokoro, the voice Lefty answers in, comes down as part of this.
cd /d "%DIR%"
uv sync
if not %ERRORLEVEL%==0 (
  echo     uv sync failed. The error above is the real one.
  pause
  exit /b 1
)

REM --- 5. settings -----------------------------------------------------------
echo.
echo [5] Settings
if exist "%DIR%.env" (
  echo     .env already exists, leaving it alone.
) else (
  copy "%DIR%.env.example" "%DIR%.env" >nul
  echo     Created .env from the example. Defaults are fine to start.
)

echo.
echo === Done ===
echo   Start it with:  start.cmd      (or the "Talk to Lefty" icon)
echo   Hold the push-to-talk key, speak, let go.
echo.
pause
endlocal
