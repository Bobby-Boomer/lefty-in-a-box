#!/bin/bash
# Turn what they told you in the interview into real folders in the vault.
#
#   bash install/make-project-folders.sh "Smugglers Roost" "F5 Theming" "The Podcast"
#
# One folder per project inside memory/projects/, each with an index note named after the
# folder, each linked from memory/projects/Projects.md.
#
# WHY: the interview already asks what they are building. Until 2026-09-28 those answers
# went into a paragraph in Business.md and nothing else, so the vault opened on day one as
# five files and a member with three live projects had nowhere to put anything.
#
# THE CONVENTION THIS KEEPS: every folder gets an index note named after the folder. The
# agent knows that rule, so it always knows where to start looking. Do not break it.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECTS="$ROOT/memory/projects"

if [ $# -eq 0 ]; then
  echo "  Give me the project names:  bash install/make-project-folders.sh \"Name One\" \"Name Two\""
  exit 1
fi

mkdir -p "$PROJECTS"

# Folder-safe, but keep it readable — people have to look at these.
slug() { printf '%s' "$1" | tr -d '/\\:*?"<>|' | sed 's/^ *//; s/ *$//'; }

INDEX="$PROJECTS/Projects.md"
{
  echo "# Projects"
  echo ""
  echo "One folder per thing you are actually building. Each has its own index note."
  echo ""
  echo "**Your agent reads this first when you mention a project by name**, so keep the list true —"
  echo "add a folder when something new starts, and say so when one finishes."
  echo ""
} > "$INDEX"

echo ""
for name in "$@"; do
  clean="$(slug "$name")"
  [ -z "$clean" ] && continue
  dir="$PROJECTS/$clean"
  mkdir -p "$dir"

  note="$dir/$clean.md"
  if [ ! -f "$note" ]; then
    cat > "$note" <<EOF
# $clean

**What it is:**

**Who it is for:**

**What "done" looks like this year:**

## Open right now

-

## Decided, do not re-litigate

-

## Where the actual work lives

*Files, folders, logins, links. Whichever half you open first should tell you where the other half is.*

-
EOF
    echo "  created  projects/$clean/$clean.md"
  else
    echo "  kept     projects/$clean/$clean.md  (already there)"
  fi

  echo "- [[$clean]]" >> "$INDEX"
done

echo "" >> "$INDEX"
echo "  index    projects/Projects.md"
echo ""
echo "  Tell your agent what changes and it keeps these current. That is the whole trick."
echo ""
