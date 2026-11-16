#!/usr/bin/env bash
# Make the phone line always on: starts at login, restarts itself if it crashes.
#   bash autostart.sh          install and start
#   bash autostart.sh --remove stop and uninstall
#
# WHY: started by hand, the phone line dies with its Terminal window and leaves no trace.
# Mac only (launchd). Keep this repo OUTSIDE ~/Documents, ~/Desktop and ~/Downloads:
# macOS blocks background jobs from those folders, and the job fails silently.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
LABEL="com.lefty.phoneline"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
LOGS="$HOME/Library/Logs/Lefty"
if [ "${1:-}" = "--remove" ]; then
  launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
  rm -f "$PLIST"; echo "Phone line auto-start removed."; exit 0
fi
case "$HERE" in "$HOME/Documents"*|"$HOME/Desktop"*|"$HOME/Downloads"*)
  echo "This folder is inside Documents, Desktop or Downloads, where macOS blocks background jobs."
  echo "Move the repo (the default install is ~/lefty/lefty-in-a-box) and run this again."; exit 1;;
esac
mkdir -p "$LOGS" "$HOME/Library/LaunchAgents"
cat > "$PLIST" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key><array><string>/bin/bash</string><string>$HERE/always-on.sh</string></array>
  <key>WorkingDirectory</key><string>$HERE</string>
  <key>StandardOutPath</key><string>$LOGS/phoneline.out</string>
  <key>StandardErrorPath</key><string>$LOGS/phoneline.err</string>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>ThrottleInterval</key><integer>20</integer>
  <key>AbandonProcessGroup</key><true/>
  <key>ProcessType</key><string>Interactive</string>
</dict></plist>
PL
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"
echo "Phone line is always on now. Logs: $LOGS/phoneline.{out,err}"
echo "Your phone link: $(bash "$HERE/url.sh")"
