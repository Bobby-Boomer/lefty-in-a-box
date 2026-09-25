#!/bin/bash
# Creates the two desktop shortcuts. This is the step that decides whether a
# non-technical person ever opens this again.
#
#   ./shortcuts.sh <install-dir>
#
# Makes:
#   ~/Desktop/Type to <Name>.command    -> opens Claude Code in the install dir
#   ~/Desktop/Talk to <Name>.command    -> starts the voice line (voice only)
#   ~/Desktop/<Name> Screen.command     -> opens the visualizer full screen
#
# The Type icon is the one that always works: memory is the piece everyone
# installs, and until 2026-09-25 there was no icon for it at all — a memory-only
# member got a Talk icon that told them voice was not set up, and no way in.
#
# <Name> comes from lefty.config.json, written by install/personalize.sh. It is
# "Lefty" until someone changes it.
#
# Why .command files: double-clickable in Finder, plain text, no build step, no
# code signing, and the user can read exactly what they do. A .app bundle looks
# nicer but needs signing to avoid a much scarier Gatekeeper warning.
#
# NOTE ON THE NAME: no apostrophe in the filename. "Lefty's Screen" went through
# three layers of shell quoting during the first build and produced a file
# literally called  Lefty'"s . Punctuation in a filename that is written by a
# script, inside a heredoc, is not worth it.

set -uo pipefail

INSTALL_DIR="${1:-$HOME/lefty/lefty-in-a-box}"
DESKTOP="$HOME/Desktop"

# What is this agent called? Falls back to Lefty if the config is missing or
# unreadable, because a shortcut with a default name beats no shortcut.
NAME="Lefty"
CONFIG="$INSTALL_DIR/lefty.config.json"
if [ -f "$CONFIG" ]; then
  FOUND="$(python3 -c '
import json,sys
try:
    print((json.load(open(sys.argv[1])).get("name") or "").strip())
except Exception:
    print("")
' "$CONFIG" 2>/dev/null)"
  [ -n "$FOUND" ] && NAME="$FOUND"
fi

# Old shortcuts under a previous name would otherwise pile up on the desktop
# every time someone renames their agent.
for old in "$DESKTOP"/Talk\ to\ *.command "$DESKTOP"/Type\ to\ *.command "$DESKTOP"/*\ Screen.command; do
  [ -f "$old" ] && grep -q "Created by Lefty in a Box" "$old" 2>/dev/null && rm -f "$old"
done

if [ ! -d "$DESKTOP" ]; then
  echo "No Desktop folder found at $DESKTOP — skipping shortcuts."
  exit 0
fi

finish() {
  chmod +x "$1"
  # Strip the quarantine flag so macOS does not refuse outright. The user may
  # still see one "unidentified developer" prompt; the installer explains it.
  xattr -d com.apple.quarantine "$1" 2>/dev/null || true
  echo "  created: $1"
}

TYPE="$DESKTOP/Type to $NAME.command"
cat > "$TYPE" <<EOF
#!/bin/bash
# Created by Lefty in a Box. Safe to delete; re-run the installer to get it back.
cd "$INSTALL_DIR" || exit 1
clear
if ! command -v claude >/dev/null 2>&1; then
  echo ""
  echo "  Cannot find the 'claude' command, so this icon has nothing to open."
  echo "  Install Claude Code, then double-click this again."
  echo ""
  read -r -p "  Press return to close this window..."
  exit 1
fi
echo ""
echo "  $NAME is reading your memory folder. Say what you need."
echo "  Type /exit when you are done."
echo ""
claude
echo ""
read -r -p "  $NAME closed. Press return to close this window..."
EOF
finish "$TYPE"

# The voice line only gets an icon once it is actually installed. An icon that
# opens a window to say "not set up yet" is worse than no icon.
VOICE_READY=""
for _v in "$HOME/lefty/voice-line" "$INSTALL_DIR/voice-line"; do
  [ -d "$_v/.venv" ] && VOICE_READY=1 && break
done

TALK="$DESKTOP/Talk to $NAME.command"
if [ -n "$VOICE_READY" ]; then
cat > "$TALK" <<EOF
#!/bin/bash
# Created by Lefty in a Box. Safe to delete; re-run the installer to get it back.
cd "$INSTALL_DIR" || exit 1
clear
echo ""
echo "  Starting $NAME. Give it a few seconds the first time."
echo "  Hold the push-to-talk key, say your piece, then let go."
echo ""
./bin/voice-line.sh
echo ""
read -r -p "  $NAME stopped. Press return to close this window..."
EOF
finish "$TALK"
fi

SCREEN="$DESKTOP/$NAME Screen.command"
cat > "$SCREEN" <<EOF
#!/bin/bash
# Created by Lefty in a Box. Safe to delete; re-run the installer to get it back.
cd "$INSTALL_DIR" || exit 1
clear
echo ""
echo "  Opening the $NAME screen. You can close this window."
echo ""
exec ./bin/visualizer.sh
EOF
finish "$SCREEN"

cat <<EOF

Your shortcuts are on the desktop now.

  Type to $NAME     open a normal chat window
  $NAME Screen      the full-screen face
EOF
if [ -n "$VOICE_READY" ]; then
  echo "  Talk to $NAME     hold the key, talk, let go"
else
  echo ""
  echo "No Talk icon yet — the voice piece is not installed. Set it up with"
  echo "voice-line/install.sh and run this again to get the icon."
fi

cat <<EOF

THE FIRST TIME you double-click one, macOS may say it cannot verify the
developer. That is normal for any script that did not come from the App Store.
To get past it, once per shortcut:

  Right-click the icon  ->  Open  ->  Open

After that, a normal double-click works.

EOF
