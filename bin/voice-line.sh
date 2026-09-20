#!/bin/bash
# Filled in by the installer once the voice piece is built.
# Kept in the repo so the desktop shortcut always has something to call and
# fails with an explanation instead of "No such file or directory".
set -uo pipefail
if [ ! -d "$HOME/lefty/voice-line" ]; then
  echo ""
  echo "  The voice piece is not installed yet."
  echo "  Run this from the lefty-in-a-box folder to add it:"
  echo ""
  echo "      claude \"set me up\""
  echo ""
  exit 1
fi
cd "$HOME/lefty/voice-line" && exec ./run-voice-line.sh
