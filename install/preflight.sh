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

# Why these extra checks exist (first live Mac install with a new member, 2026-11-13):
# 1. She installed the Claude DESKTOP app from claude.com, typed `claude`, got
#    "command not found", and 20 minutes went to the wrong fix. Same name on the box,
#    different product: only Claude Code puts `claude` in the terminal.
# 2. Claude Code's native installer drops the binary in ~/.local/bin, which a fresh
#    Mac does not have on PATH. Installed, but invisible until the PATH line + new window.
# 3. Homebrew installed fine, but its "Next steps" shellenv lines were not run, so
#    `brew` said "command not found". The voice installer then had no brew to use.
claude_hint=""
if [ "$claude_ok" = no ]; then
  if [ -x "$HOME/.local/bin/claude" ]; then
    claude_hint="not_on_path"
  elif [ -d "/Applications/Claude.app" ]; then
    claude_hint="desktop_app_only"
  fi
fi

brew_ok=na
if [ "$(uname -s)" = "Darwin" ]; then
  if have brew; then
    brew_ok=yes
  elif [ -x /opt/homebrew/bin/brew ] || [ -x /usr/local/bin/brew ]; then
    brew_ok=not_on_path
  else
    brew_ok=no
  fi
fi
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
  printf '{"os":"%s","claude":"%s","claude_hint":"%s","git":"%s","brew":"%s","python":"%s","python_version":"%s","mic":"%s","camera":"%s","free_gb":%s}\n' \
    "$os" "$claude_ok" "$claude_hint" "$git_ok" "$brew_ok" "$python_ok" "$python_ver" "$mic" "$camera" "$disk_gb"
  exit 0
fi

say() { printf '  %-26s %s\n' "$1" "$2"; }
echo ""
echo "What this computer already has:"
echo ""
say "This computer" "$os"
say "Claude Code" "$([ "$claude_ok" = yes ] && echo "installed" || echo "MISSING — nothing works without it")"
say "Git" "$([ "$git_ok" = yes ] && echo "installed" || echo "MISSING")"
case "$brew_ok" in
  yes) say "Homebrew" "installed" ;;
  not_on_path) say "Homebrew" "installed but this window cannot see it — see below" ;;
  no) say "Homebrew" "MISSING — needed for the voice (speech + audio tools)" ;;
esac
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
  case "$claude_hint" in
    not_on_path) cat <<'EOF'
Claude Code IS installed, but this Terminal window cannot find it. Paste this,
then close this window and open a new one:

    echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc

EOF
    ;;
    desktop_app_only) cat <<'EOF'
You have the Claude DESKTOP app, not Claude Code. Same name, different product,
and only Claude Code puts a `claude` command in the terminal. Keep the app.
Also paste this, then close this window and open a new one:

    curl -fsSL https://claude.ai/install.sh | bash

EOF
    ;;
    *) cat <<'EOF'
Claude Code is the one piece that is not optional, and it is not installed.
Paste this, then close this window and open a new one, run `claude` once and
sign in, then paste the install command again. Nothing here is lost.

    curl -fsSL https://claude.ai/install.sh | bash

EOF
    ;;
  esac
fi

if [ "$brew_ok" = not_on_path ]; then
  cat <<'EOF'
Homebrew is installed, but its "Next steps" lines were never run, so this
window cannot see it. Paste these, then open a new Terminal window:

    echo >> ~/.zprofile
    echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
    eval "$(/opt/homebrew/bin/brew shellenv)"

(On an older Intel Mac, swap /opt/homebrew for /usr/local.)

EOF
fi
exit 0
