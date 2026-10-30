#!/bin/bash
# Keep the Telegram bridge running — macOS.
#
# THE PROBLEM THIS SOLVES: the bridge is a long-poll loop you start by hand, so
# it dies the moment you close that terminal, log out, or reboot. It does not
# announce this. The phone line just stops answering, and you find out the next
# time you reach for it — usually when you are away from the computer and can do
# nothing about it. Hit for real on 2026-10-30: the bridge went down at 4:08 PM,
# nothing noticed, and the log simply filled with "poll failed: The read
# operation timed out" until someone went looking.
#
# This writes a launchd job with KeepAlive, so the bridge starts at login and
# restarts itself whenever it exits. Run it once; it is safe to re-run.
#
#   bash telegram/install-bridge.sh
#
# To turn it off:
#   launchctl unload ~/Library/LaunchAgents/com.agent.telegram.plist
#
# Linux: run the bridge under systemd --user with Restart=always instead.
# Windows: Task Scheduler, "at log on", with restart-on-failure.

set -eu

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/bridge.py"
LABEL="com.agent.telegram"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
PY="$(command -v python3 || true)"

if [ "$(uname)" != "Darwin" ]; then
  echo "This installer is macOS-only."
  echo "Linux: a systemd --user unit with Restart=always, running:"
  echo "  ${PY:-python3} $SCRIPT"
  exit 1
fi

if [ ! -f "$SCRIPT" ]; then
  echo "Cannot find $SCRIPT — run this from inside the kit."
  exit 1
fi

if [ -z "$PY" ]; then
  echo "No python3 on PATH. Install it, then re-run."
  exit 1
fi

if [ ! -s "$HOME/.agent-telegram/token" ]; then
  echo "No Telegram token yet at ~/.agent-telegram/token."
  echo "Set the bridge up first — see telegram/README.md — then re-run this."
  exit 1
fi

# macOS denies launchd background agents access to ~/Documents, ~/Desktop and
# ~/Downloads unless you grant Full Disk Access by hand. A job pointed at a
# script in one of those folders dies with exit 127 and "can't open input file",
# even though the script is right there and executable. With KeepAlive on, that
# turns into a crash loop instead of a working phone line. Same trap that bit
# install-reminders.sh on 2026-10-15.
case "$HERE" in
  "$HOME/Documents"/*|"$HOME/Desktop"/*|"$HOME/Downloads"/*)
    cat <<WARN
Heads up — this kit is installed under a folder macOS protects:
  $HERE

Background jobs cannot read scripts there, so the bridge would crash-loop and
your phone line would never answer. Two ways forward:

  1. Grant Full Disk Access to python3
     System Settings > Privacy & Security > Full Disk Access > + > press
     Cmd-Shift-G and enter $PY. Then re-run this installer.

  2. Move the kit somewhere unprotected, for example ~/agent, and re-run.

Option 2 is the cleaner one. Full Disk Access is broad.
WARN
    exit 1
    ;;
esac

# A path with a space breaks a launchd argument vector that was built as one
# string. We pass argv as separate <string> elements below, which handles
# spaces correctly — do not "simplify" this into a single shell command string.
mkdir -p "$HOME/Library/LaunchAgents"

cat > "$PLIST" <<PLISTEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>$PY</string>
    <string>$SCRIPT</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <!-- KeepAlive is the whole point. Without it the bridge dies with the
       terminal that started it and says nothing. -->
  <key>KeepAlive</key>
  <true/>
  <key>ProcessType</key>
  <string>Background</string>
  <key>StandardOutPath</key>
  <string>$HERE/bridge.out.log</string>
  <key>StandardErrorPath</key>
  <string>$HERE/bridge.err.log</string>
</dict>
</plist>
PLISTEOF

launchctl unload "$PLIST" 2>/dev/null || true
launchctl load "$PLIST"

sleep 3

echo "Bridge installed and loaded."
echo
if launchctl list | grep -q "$LABEL"; then
  echo "  launchd job: $LABEL  (running)"
else
  echo "  launchd job: $LABEL  (NOT running — check the error log below)"
fi
echo "  out log:     $HERE/bridge.out.log"
echo "  err log:     $HERE/bridge.err.log"
echo
echo "A healthy start prints a line like:"
echo "  bridge up, offset 0, workdir $(dirname "$HERE")"
echo
echo "Check it any time with:"
echo "  launchctl list | grep $LABEL"
echo
echo "Now message your bot from your phone. The first message you send pairs the"
echo "bridge to that chat and locks out every other one."
