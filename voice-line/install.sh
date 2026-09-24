#!/bin/bash
# Lefty's Voice — installer for macOS and Linux.
#
#   ./install.sh
#
# Three things have to be in place before Lefty can hear you and answer:
#
#   1. uv          — the Python runner that builds the environment
#   2. whisper.cpp — turns your speech into text, on your machine
#   3. a model     — the speech model whisper reads (about 148 MB, downloaded once)
#
# Kokoro (the voice Lefty answers in) installs itself with the Python
# dependencies, so there is nothing separate to do for it.
#
# This script NEVER installs anything without asking first. If it cannot do
# something it says so in plain words and tells you the one command to run.

set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODEL_DIR="$HOME/lefty/whisper-models"
MODEL_FILE="$MODEL_DIR/ggml-base.en.bin"
MODEL_URL="https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin"

say()  { printf "\n  %s\n" "$1"; }
step() { printf "\n[%s] %s\n" "$1" "$2"; }

ask() {
  # ask "question" -> 0 for yes, 1 for no. Defaults to no.
  printf "\n  %s [y/N] " "$1"
  read -r a
  case "$a" in [yY]*) return 0 ;; *) return 1 ;; esac
}

printf "\n=== Lefty's Voice — setup ===\n"

# ── 1. uv ───────────────────────────────────────────────────────────────────
step 1 "Checking for uv (the Python runner)"
if command -v uv >/dev/null 2>&1; then
  say "uv is here. Good."
else
  say "uv is not installed. It is what builds the Python environment."
  say "The official installer is:  curl -LsSf https://astral.sh/uv/install.sh | sh"
  if ask "Install uv now?"; then
    curl -LsSf https://astral.sh/uv/install.sh | sh || { say "uv install failed. Stopping."; exit 1; }
    export PATH="$HOME/.local/bin:$PATH"
  else
    say "Fine. Install uv yourself, then run this again."
    exit 1
  fi
fi

# ── 2. whisper ──────────────────────────────────────────────────────────────
step 2 "Checking for whisper-server (speech to text)"
WHISPER_BIN=""
for c in \
  "$(command -v whisper-server 2>/dev/null)" \
  "$HOME/whisper.cpp/build/bin/whisper-server" \
  "/opt/homebrew/bin/whisper-server" \
  "/usr/local/bin/whisper-server"; do
  if [ -n "$c" ] && [ -x "$c" ]; then WHISPER_BIN="$c"; break; fi
done

if [ -n "$WHISPER_BIN" ]; then
  say "Found whisper-server at: $WHISPER_BIN"
else
  say "whisper-server is not on this machine."
  say "It is what turns your speech into text, and it runs locally --"
  say "nothing you say is sent anywhere."
  if [ "$(uname -s)" = "Darwin" ] && command -v brew >/dev/null 2>&1; then
    say "Homebrew is here, and it has a ready-built copy. One command:"
    say "    brew install whisper.cpp"
    if ask "Run that now? (a few minutes)"; then
      brew install whisper.cpp || { say "brew install failed. Stopping."; exit 1; }
      WHISPER_BIN="$(command -v whisper-server || true)"
    else
      say "Skipped. Install it when you are ready, then run this again."
      exit 1
    fi
  else
    say "There is no ready-built copy for this system, so it has to be"
    say "compiled from source. That needs cmake and a C++ compiler:"
    say "    git clone https://github.com/ggml-org/whisper.cpp ~/whisper.cpp"
    say "    cd ~/whisper.cpp && cmake -B build && cmake --build build --config Release"
    say ""
    say "Do that, then run this script again. Everything else is ready."
    exit 1
  fi
fi

# ── 2b. ffmpeg ──────────────────────────────────────────────────────────────
step 2b "Checking for ffmpeg (audio plumbing)"
if command -v ffmpeg >/dev/null 2>&1; then
  say "ffmpeg is here."
else
  say "ffmpeg is missing. The voice line will not start without it."
  if [ "$(uname -s)" = "Darwin" ] && command -v brew >/dev/null 2>&1; then
    if ask "Install it with brew now?"; then
      brew install ffmpeg || { say "brew install ffmpeg failed. Stopping."; exit 1; }
    else
      say "Skipped. Install ffmpeg, then run this again."
      exit 1
    fi
  else
    say "Install ffmpeg for your system, then run this again."
    say "Linux, usually:  sudo apt install ffmpeg"
    exit 1
  fi
fi

# ── 3. the model ────────────────────────────────────────────────────────────
step 3 "Checking for the speech model"
if [ -f "$MODEL_FILE" ]; then
  say "Model already here: $MODEL_FILE"
else
  say "The speech model is about 148 MB and downloads once."
  if ask "Download it now?"; then
    mkdir -p "$MODEL_DIR"
    curl -L --fail --progress-bar -o "$MODEL_FILE.part" "$MODEL_URL" \
      && mv "$MODEL_FILE.part" "$MODEL_FILE" \
      || { say "Download failed. Nothing was changed."; rm -f "$MODEL_FILE.part"; exit 1; }
    say "Model saved to $MODEL_FILE"
  else
    say "Skipped. Voice cannot work without it. Run this again when ready."
    exit 1
  fi
fi

# ── 4. python dependencies ──────────────────────────────────────────────────
step 4 "Building the Python environment (this is the long one)"
say "Kokoro, the voice Lefty answers in, comes down as part of this."
cd "$DIR" || exit 1
uv sync || { say "uv sync failed. The error above is the real one."; exit 1; }

# ── 5. settings file ────────────────────────────────────────────────────────
step 5 "Settings"
if [ -f "$DIR/.env" ]; then
  say ".env already exists, leaving it alone."
else
  cp "$DIR/.env.example" "$DIR/.env"
  say "Created .env from the example. Defaults are fine to start."
fi

printf "\n=== Done ===\n"
say "Start it with:   ./start.sh      (or the 'Talk to Lefty' icon)"
say "Hold the push-to-talk key, speak, let go."
say ""
say "On macOS the first run will ask for Microphone and Input Monitoring"
say "permission. Input Monitoring is the one people miss -- without it the"
say "push-to-talk key does nothing and it looks frozen."
printf "\n"
