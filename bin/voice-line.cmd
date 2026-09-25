@echo off
REM Talk to Lefty launcher - Windows.
REM
REM The voice line ships IN this repo at ..\voice-line. If the installer put a
REM copy at %USERPROFILE%\lefty\voice-line that one wins.

setlocal
set HERE=%~dp0
for %%I in ("%HERE%..") do set ROOT=%%~fI

REM Point the session at this repo - the folder holding agent.md and memory\.
REM An explicit --cwd from the caller still wins.
set ARGS=%*
echo %* | findstr /C:"--cwd" >nul
if errorlevel 1 set ARGS=%* --cwd "%ROOT%"

for %%D in ("%USERPROFILE%\lefty\voice-line" "%HERE%..\voice-line") do (
  if exist "%%~D\start.cmd" (
    if not exist "%%~D\.venv" (
      echo.
      echo   The voice piece is here, but it has not been set up yet.
      echo   It needs a speech engine and a model, about 150 MB, once.
      echo.
      echo   Run this to do it:
      echo.
      echo       cd /d "%%~D" ^&^& install.cmd
      echo.
      pause
      exit /b 1
    )
    cd /d "%%~D"
    call start.cmd %ARGS%
    exit /b 0
  )
)

echo.
echo   Could not find the voice piece.
echo   It should be at %%USERPROFILE%%\lefty\lefty-in-a-box\voice-line.
echo   Run this from the lefty-in-a-box folder to repair it:
echo.
echo       claude "set me up"
echo.
pause
exit /b 1
