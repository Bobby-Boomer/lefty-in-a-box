@echo off
REM Obsidian - Windows twin of obsidian.sh.
REM
REM   install\obsidian.cmd              ask before installing
REM   install\obsidian.cmd --vault-only skip the install, just set the vault up
REM
REM WHY THIS EXISTS: on the live Windows install with Tijo on 2026-09-24 the vault never
REM got set up, because the installer left Obsidian entirely to the member. A shared
REM knowledge base nobody opens is not a knowledge base.
REM
REM THE HARD RULE STILL APPLIES: never install anything without asking first.

setlocal
for %%I in ("%~dp0..") do set ROOT=%%~fI
set VAULT=%ROOT%\memory

echo.

REM --- already installed? ------------------------------------------------------
set HAVE=
where obsidian >nul 2>&1 && set HAVE=1
if exist "%LOCALAPPDATA%\Obsidian\Obsidian.exe" set HAVE=1
if exist "%ProgramFiles%\Obsidian\Obsidian.exe" set HAVE=1

if defined HAVE (
  echo   Obsidian is already on this machine. Good.
  goto :vault
)

if "%~1"=="--vault-only" (
  echo   Skipping the install, setting up the vault only.
  goto :vault
)

echo   Obsidian is a free app for reading and linking plain text notes.
echo   Your agent does NOT need it - it reads the files either way. This is for YOU:
echo   clickable links between notes, backlinks, and search across everything.
echo.
echo   It is about a 150 MB download and takes a minute or two.
echo.
set /p ANSWER="  Install it? [y/N]: "
if /i not "%ANSWER%"=="y" (
  echo   Skipped. You can run this again any time:  install\obsidian.cmd
  goto :vault
)

where winget >nul 2>&1
if errorlevel 1 (
  echo   winget is not available, so I cannot install it for you.
  echo   Download it from https://obsidian.md - it is free, no account needed.
  goto :vault
)
echo   Installing with winget...
winget install --id Obsidian.Obsidian -e --accept-package-agreements --accept-source-agreements
if errorlevel 1 (
  echo   That failed. Grab it from https://obsidian.md instead.
) else (
  echo   Installed.
)

:vault
REM --- make memory\ a real vault ------------------------------------------------
REM A folder becomes an Obsidian vault the moment it contains .obsidian\.
if not exist "%VAULT%\.obsidian" mkdir "%VAULT%\.obsidian"

if not exist "%VAULT%\.obsidian\app.json" (
  > "%VAULT%\.obsidian\app.json" echo {
  >> "%VAULT%\.obsidian\app.json" echo   "alwaysUpdateLinks": true,
  >> "%VAULT%\.obsidian\app.json" echo   "newLinkFormat": "shortest",
  >> "%VAULT%\.obsidian\app.json" echo   "useMarkdownLinks": false,
  >> "%VAULT%\.obsidian\app.json" echo   "attachmentFolderPath": "attachments",
  >> "%VAULT%\.obsidian\app.json" echo   "showUnsupportedFiles": true
  >> "%VAULT%\.obsidian\app.json" echo }
)

if not exist "%VAULT%\.obsidian\daily-notes.json" (
  > "%VAULT%\.obsidian\daily-notes.json" echo { "folder": "daily", "format": "YYYY-MM-DD" }
)

echo.
echo   memory\ is now an Obsidian vault.
echo   Open Obsidian, choose "Open folder as vault", and pick:
echo       %VAULT%
echo   Daily notes are already pointed at memory\daily\.
echo.
endlocal
