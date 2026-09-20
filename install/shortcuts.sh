#!/bin/bash
# Creates the two desktop shortcuts. This is the step that decides whether a
# non-technical person ever opens this again.
#
#   ./shortcuts.sh <install-dir>
#
# Makes:
#   ~/Desktop/Talk to Lefty.command     -> starts the voice line
#   ~/Desktop/Lefty Screen.command      -> opens the visualizer full screen
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

TALK="$DESKTOP/Talk to Lefty.command"
cat > "$TALK" <<EOF
#!/bin/bash
# Created by Lefty in a Box. Safe to delete; re-run the installer to get it back.
cd "$INSTALL_DIR" || exit 1
clear
echo ""
echo "  Starting Lefty. Give it a few seconds the first time."
echo "  Hold the push-to-talk key, say your piece, then let go."
echo ""
./bin/voice-line.sh
echo ""
read -r -p "  Lefty stopped. Press return to close this window..."
EOF
finish "$TALK"

SCREEN="$DESKTOP/Lefty Screen.command"
cat > "$SCREEN" <<EOF
#!/bin/bash
# Created by Lefty in a Box. Safe to delete; re-run the installer to get it back.
cd "$INSTALL_DIR" || exit 1
clear
echo ""
echo "  Opening Lefty's screen. You can close this window."
echo ""
exec ./bin/visualizer.sh
EOF
finish "$SCREEN"

cat <<'EOF'

Two shortcuts are on your desktop now.

  Talk to Lefty     hold the key, talk, let go
  Lefty Screen      the full-screen face

THE FIRST TIME you double-click one, macOS may say it cannot verify the
developer. That is normal for any script that did not come from the App Store.
To get past it, once per shortcut:

  Right-click the icon  ->  Open  ->  Open

After that, a normal double-click works.

EOF
