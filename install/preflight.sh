#!/bin/bash
# Checks what this machine already has, and says plainly what is missing and
# what it costs to fix. Never installs anything on its own -- the wizard asks
# first, because silently installing software on someone's computer is not a
# thing we do.
#
#   ./preflight.sh            human-readable
#   ./preflight.sh --json     machine-readable, for the wizard
#
# Exit code is always 0. A missing piece is information, not a failure.

set -uo pipefail
JSON=0
[ "${1:-}" = "--json" ] && JSON=1

have() { command -v "$1" >/dev/null 2>&1; }

os="unknown"
case "$(uname -s)" in
  Darwin) os="macos" ;;
  Linux)  os="linux" ;;
  MINGW*|MSYS*|CYGWIN*) os="windows" ;;
esac

claude_ok=$(have claude && echo yes || echo no)
git_ok=$(have git && echo yes || echo no)
python_ok=no
python_ver=""
if have python3; then
  python_ver=$(python3 -c 'import sys;print("%d.%d"%sys.version_info[:2])' 2>/dev/null)
  # 3.10+ is what the voice line needs.
  if python3 -c 'import sys;sys.exit(0 if sys.version_info>=(3,10) else 1)' 2>/dev/null; then
    python_ok=yes
  else
    python_ok=old
  fi
fi

mic=no
camera=no
if [ "$os" = "macos" ]; then
  system_profiler SPAudioDataType 2>/dev/null | grep -qi "input" && mic=yes
  system_profiler SPCameraDataType 2>/dev/null | grep -qi "camera\|model id" && camera=yes
fi

disk_gb=$(df -g "$HOME" 2>/dev/null | awk 'NR==2{print $4}')
[ -z "$disk_gb" ] && disk_gb=0

if [ "$JSON" -eq 1 ]; then
  printf '{"os":"%s","claude":"%s","git":"%s","python":"%s","python_version":"%s","mic":"%s","camera":"%s","free_gb":%s}\n' \
    "$os" "$claude_ok" "$git_ok" "$python_ok" "$python_ver" "$mic" "$camera" "$disk_gb"
  exit 0
fi

say() { printf '  %-26s %s\n' "$1" "$2"; }
echo ""
echo "What this computer already has:"
echo ""
say "This computer" "$os"
say "Claude Code" "$([ "$claude_ok" = yes ] && echo "installed" || echo "MISSING — nothing works without it")"
say "Git" "$([ "$git_ok" = yes ] && echo "installed" || echo "MISSING")"
case "$python_ok" in
  yes) say "Python" "$python_ver, good" ;;
  old) say "Python" "$python_ver — too old for the voice, needs 3.10 or newer" ;;
  no)  say "Python" "MISSING — only needed for the voice" ;;
esac
say "Microphone" "$([ "$mic" = yes ] && echo "found" || echo "none — the voice will not work")"
say "Camera" "$([ "$camera" = yes ] && echo "found" || echo "none — the hand board will not work")"
say "Free disk space" "${disk_gb} GB $([ "${disk_gb:-0}" -lt 5 ] 2>/dev/null && echo "— tight. The speech models need a few GB." || echo "")"
echo ""

if [ "$claude_ok" = no ]; then
  cat <<'EOF'
Claude Code is the one piece that is not optional, and it is not installed.
Get it from https://claude.com/claude-code, run `claude` once and sign in,
then come back and paste the install command again. Nothing here is lost.

EOF
fi
exit 0
