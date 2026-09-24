#!/bin/bash
# Talk to Lefty launcher — macOS and Linux.
#
# The voice line ships IN this repo at ../voice-line. If the installer put a
# copy at ~/lefty/voice-line that one wins, because it may have been customised.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

for candidate in "$HOME/lefty/voice-line" "$HERE/../voice-line"; do
  if [ -f "$candidate/start.sh" ]; then
    # Not set up yet? Say that instead of throwing an error at them.
    if [ ! -d "$candidate/.venv" ]; then
      echo ""
      echo "  The voice piece is here, but it has not been set up yet."
      echo "  It needs a speech engine and a model, about 150 MB, once."
      echo ""
      echo "  Run this to do it:"
      echo ""
      echo "      cd $candidate && ./install.sh"
      echo ""
      read -r -p "press return to close..."
      exit 1
    fi
    cd "$candidate" || exit 1
    exec bash ./start.sh "$@"
  fi
done

echo ""
echo "  Could not find the voice piece."
echo "  It should be at ~/lefty/lefty-in-a-box/voice-line."
echo "  Run this from the lefty-in-a-box folder to repair it:"
echo ""
echo "      claude \"set me up\""
echo ""
exit 1
