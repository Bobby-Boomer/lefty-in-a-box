#!/bin/bash
# Obsidian: install it if they want it, and make memory/ a real vault.
#
#   bash install/obsidian.sh          # ask before installing
#   bash install/obsidian.sh --vault-only   # skip the install, just set the vault up
#
# WHY THIS EXISTS: until 2026-09-28 the installer left Obsidian entirely to the member.
# On the live Windows install with Tijo on 09-24 that meant the vault never got set up,
# and a shared knowledge base nobody opens is not a knowledge base. The memory folder is
# the whole point of this product, so it should open in one click, not after a tutorial.
#
# THE HARD RULE STILL APPLIES: never install anything without asking first, in plain words,
# including what it is and roughly how long it takes.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VAULT="$ROOT/memory"
VAULT_ONLY="${1:-}"

say() { echo "  $1"; }

# ── Is it already here? ─────────────────────────────────────────────────────
have_obsidian() {
  [ -d "/Applications/Obsidian.app" ] && return 0
  command -v obsidian >/dev/null 2>&1 && return 0
  [ -d "$HOME/Applications/Obsidian.app" ] && return 0
  return 1
}

echo ""
if have_obsidian; then
  say "Obsidian is already on this machine. Good."
elif [ "$VAULT_ONLY" = "--vault-only" ]; then
  say "Skipping the install, setting up the vault only."
else
  echo "  Obsidian is a free app for reading and linking plain text notes."
  echo "  Your agent does NOT need it — it reads the files either way. This is for YOU:"
  echo "  clickable links between notes, backlinks, and search across everything."
  echo ""
  echo "  It is about a 150 MB download and takes a minute or two."
  echo ""
  printf "  Install it? [y/N]: "
  read -r ANSWER
  case "$ANSWER" in
    [Yy]*)
      if command -v brew >/dev/null 2>&1; then
        say "Installing with Homebrew..."
        brew install --cask obsidian && say "Installed." || say "That failed. Grab it from obsidian.md instead."
      else
        say "No Homebrew here, so I cannot install it for you."
        say "Download it from https://obsidian.md — it is free, no account needed."
      fi
      ;;
    *) say "Skipped. You can run this again any time: bash install/obsidian.sh" ;;
  esac
fi

# ── Make memory/ a real vault ───────────────────────────────────────────────
# A folder becomes an Obsidian vault the moment it contains .obsidian/. Writing a
# minimal config here means the member opens it and it just works, rather than being
# walked through "open folder as vault" in a setup call.
mkdir -p "$VAULT/.obsidian"

if [ ! -f "$VAULT/.obsidian/app.json" ]; then
  cat > "$VAULT/.obsidian/app.json" <<'JSON'
{
  "alwaysUpdateLinks": true,
  "newLinkFormat": "shortest",
  "useMarkdownLinks": false,
  "attachmentFolderPath": "attachments",
  "showUnsupportedFiles": true
}
JSON
fi

if [ ! -f "$VAULT/.obsidian/core-plugins.json" ]; then
  # Backlinks and graph on by default — they are the reason to use it at all.
  cat > "$VAULT/.obsidian/core-plugins.json" <<'JSON'
[
  "file-explorer", "global-search", "switcher", "graph", "backlink",
  "outgoing-link", "tag-pane", "page-preview", "daily-notes",
  "templates", "note-composer", "command-palette", "outline",
  "word-count", "file-recovery"
]
JSON
fi

if [ ! -f "$VAULT/.obsidian/daily-notes.json" ]; then
  cat > "$VAULT/.obsidian/daily-notes.json" <<'JSON'
{ "folder": "daily", "format": "YYYY-MM-DD" }
JSON
fi

echo ""
say "memory/ is now an Obsidian vault."
say "Open Obsidian, choose 'Open folder as vault', and pick:"
say "    $VAULT"
say "Daily notes are already pointed at memory/daily/."
echo ""
