#!/bin/bash
# Lefty's Screen launcher — macOS and Linux.
#
# The screen ships IN this repo, at ../visualizer, so it works straight after a
# clone with nothing to build. If the installer put a copy at ~/lefty/visualizer
# that one wins, because it may have been customised.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

for candidate in "$HOME/lefty/visualizer" "$HERE/../visualizer"; do
  if [ -f "$candidate/start.sh" ]; then
    cd "$candidate" || exit 1
    exec bash ./start.sh
  fi
done

echo ""
echo "  Could not find the screen."
echo "  It should be at ~/lefty/lefty-in-a-box/visualizer."
echo "  Run this from the lefty-in-a-box folder to repair it:"
echo ""
echo "      claude \"set me up\""
echo ""
exit 1
