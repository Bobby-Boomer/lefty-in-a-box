#!/bin/bash
# Turn on scheduled reminders — macOS.
#
# Writes a launchd job that runs telegram/remind.sh once a day, then loads it.
# The path is derived from wherever this folder actually lives, so it works no
# matter where the kit was installed. Run it once; it is safe to re-run.
#
#   bash telegram/install-reminders.sh            # default, 9:00 AM
#   bash telegram/install-reminders.sh 7 30       # 7:30 AM
#
# To turn it off:
#   launchctl unload ~/Library/LaunchAgents/com.agent.remind.plist
#
# Linux: skip this and add a crontab line instead —
#   0 9 * * * /full/path/to/telegram/remind.sh
# Windows: Task Scheduler, daily, running remind.sh through Git Bash or WSL.

set -eu

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/remind.sh"
HOUR="${1:-9}"
MINUTE="${2:-0}"
LABEL="com.agent.remind"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"

if [ "$(uname)" != "Darwin" ]; then
  echo "This installer is macOS-only. On Linux use cron:"
  echo "  0 $HOUR * * * $SCRIPT"
  exit 1
fi

if [ ! -f "$SCRIPT" ]; then
  echo "Cannot find $SCRIPT — run this from inside the kit."
  exit 1
fi

if [ ! -s "$HOME/.agent-telegram/token" ]; then
  echo "No Telegram token yet at ~/.agent-telegram/token."
  echo "Set the bridge up first — see telegram/README.md — then re-run this."
  exit 1
fi

chmod +x "$SCRIPT"
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
    <string>/bin/bash</string>
    <string>$SCRIPT</string>
  </array>
  <key>StartCalendarInterval</key>
  <dict>
    <key>Hour</key>
    <integer>$HOUR</integer>
    <key>Minute</key>
    <integer>$MINUTE</integer>
  </dict>
  <key>RunAtLoad</key>
  <false/>
  <key>StandardOutPath</key>
  <string>$HERE/remind.out.log</string>
  <key>StandardErrorPath</key>
  <string>$HERE/remind.err.log</string>
</dict>
</plist>
PLISTEOF

launchctl unload "$PLIST" 2>/dev/null || true
launchctl load "$PLIST"

printf 'Reminders are on. Checking daily at %02d:%02d.\n' "$HOUR" "$MINUTE"
echo "Queue:  $HERE/reminders.tsv"
echo "Log:    $HERE/remind.log"
echo
echo "Test it now: add a line to the queue dated today, then run"
echo "  bash $SCRIPT"
