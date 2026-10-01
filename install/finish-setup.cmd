@echo off
REM The last step of setup - Windows twin of finish-setup.sh.
REM
REM   install\finish-setup.cmd [--force]
REM
REM Writes agent.md at the repo root from install\agent-boot.md. While agent.md
REM is missing, CLAUDE.md sends Claude to the setup wizard; once it exists,
REM Claude boots as their agent instead.
REM
REM agent.md is gitignored on purpose, so `git pull` never fights with it.
REM
REM NOT YET RUN ON A REAL WINDOWS MACHINE. Written to match finish-setup.sh.

setlocal
for %%I in ("%~dp0..") do set ROOT=%%~fI
set TEMPLATE=%ROOT%\install\agent-boot.md
set AGENT=%ROOT%\agent.md

if not exist "%TEMPLATE%" (
  echo   Missing "%TEMPLATE%" - cannot write the agent boot file.
  exit /b 1
)

if exist "%AGENT%" if not "%~1"=="--force" (
  echo   agent.md is already here, leaving it alone ^(it may have your edits^).
  echo   To replace it with a fresh copy:  install\finish-setup.cmd --force
  exit /b 0
)

REM Drop the template's explanatory header: everything up to and including the
REM first bare --- line.
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$lines = Get-Content -LiteralPath $env:TEMPLATE;" ^
  "$i = 0; $cut = -1;" ^
  "foreach ($l in $lines) { if ($l.Trim() -eq '---') { $cut = $i; break }; $i++ };" ^
  "if ($cut -lt 0) { Write-Host '  The template has no --- divider. Not safe.'; exit 1 };" ^
  "$body = $lines[($cut+1)..($lines.Count-1)];" ^
  "while ($body.Count -gt 0 -and $body[0].Trim() -eq '') { $body = $body[1..($body.Count-1)] };" ^
  "if ($body.Count -eq 0) { Write-Host '  Nothing left after the divider. Not safe.'; exit 1 };" ^
  "Set-Content -LiteralPath $env:AGENT -Value $body"

if errorlevel 1 (
  echo   Could not write "%AGENT%".
  exit /b 1
)

set NAME=Lefty
if exist "%ROOT%\lefty.config.json" (
  for /f "usebackq delims=" %%N in (`powershell -NoProfile -Command ^
    "try { (Get-Content -Raw -LiteralPath $env:ROOT'\lefty.config.json' ^| ConvertFrom-Json).name } catch { '' }"`) do (
    if not "%%N"=="" set NAME=%%N
  )
)

REM Make memory\ a real Obsidian vault, every time, no questions asked.
REM
REM WHY THIS IS HERE AND NOT ONLY IN THE WIZARD: step 6c of setup-wizard.md tells
REM the installer to run install\obsidian.cmd. It got skipped on the live Windows
REM install with Tijo on 2026-09-24, and skipped AGAIN with Leigh Anne on
REM 2026-10-01. Twice is not bad luck, it is a design fault: the vault depended on
REM a conversation remembering a step. Now the script that must run anyway does it.
REM
REM --vault-only installs NOTHING. It writes .obsidian config inside a folder the
REM member already owns, so the hard rule is untouched. The app itself stays an
REM explicit, asked-for choice back in step 6c.
if exist "%ROOT%\install\obsidian.cmd" (
  call "%ROOT%\install\obsidian.cmd" --vault-only >nul 2>&1
  if errorlevel 1 (
    echo   Could not set up the Obsidian vault. Run:  install\obsidian.cmd --vault-only
  ) else (
    echo   memory\ is set up as an Obsidian vault.
  )
)

echo.
echo   Setup is finished. This folder is %NAME% now, not an installer.
echo   agent.md is the file they read at boot - it is yours, edit it any time.
echo.
endlocal
