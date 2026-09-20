#!/bin/bash
# Filled in by the installer once the screen piece is built.
set -uo pipefail
if [ ! -d "$HOME/lefty/visualizer" ]; then
  echo ""
  echo "  The screen piece is not installed yet."
  echo "  Run this from the lefty-in-a-box folder to add it:"
  echo ""
  echo "      claude \"set me up\""
  echo ""
  exit 1
fi
cd "$HOME/lefty/visualizer" && exec ./start.sh
