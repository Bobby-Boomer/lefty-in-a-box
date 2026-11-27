# Your folder fills up with files ending in " 2"

## The symptom

- Files and folders appear beside the real ones with a space and a 2 on the end —
  `bus.sh 2`, `README 2.md`, `lesson-1 2.html`, `Cache_a1b2c3 2`.
- `git status` in a synced repo shows a pile of untracked `* 2.*` files you never made.
- iCloud never seems to finish syncing. The Finder progress ring just keeps spinning.
- Upload bandwidth and fan noise for no reason you can point at.

Nothing is broken and nothing is lost. But two of these are genuinely dangerous:

- **A duplicate next to a source file is how the wrong version ships.** A loop over
  `lessons/*.html` picks up both copies. Whichever the glob hits first wins, and it
  looks completely normal on screen.
- **The duplicate is not always the newer file.** Sometimes the ` 2` copy is the one
  with your recent edits, which means the "real" filename is the stale one.

## What is actually happening

These are **iCloud conflict copies**, and they are a different failure mode from
[iCloud offloading](./icloud-offloading.md) — offloading removes the bytes and leaves
a stub, conflicts duplicate the file. Fixing one does nothing about the other.

iCloud makes a conflict copy when it tries to upload a file **while something is still
writing to it**. One quiet write during an upload and iCloud can no longer tell which
version is authoritative, so it keeps both.

Normal documents almost never trigger this, because you save and stop. **Application
state directories trigger it constantly**, because the app rewrites the same files
every few seconds for as long as it runs:

- browser profiles (caches, cookie stores, metrics, SQLite journals)
- any SQLite database that is open
- log files being appended to
- `.git` internals in a repo you are actively using

## Confirm it before you fix it

Ask iCloud directly what it is doing:

```sh
brctl status | head -40
```

Look for `Needs Apply Changes` and `Client Truth Unclean Items`, and read the paths
underneath them. On the install where this was found, both sections were full of
browser cache files with `up:needs-upload` and an `upload{active}` retry counter —
iCloud was fighting a running browser in real time.

Then count what you actually have, and **break it down by folder before you panic**:

```sh
cd ~/your-install-dir
find . \( -name "* 2.*" -o -name "* 2" \) > /tmp/dupes.txt
wc -l < /tmp/dupes.txt
awk -F/ '{print $2}' /tmp/dupes.txt | sort | uniq -c | sort -rn
```

A raw total is a scary and useless number. In the real case it was 14,407 — of which
**14,356 were browser-profile churn** and about 48 were in folders holding real work.
Those 48 are the only ones worth a human looking at.

## The fix: keep app state out of synced folders

**Move the profile or state directory somewhere iCloud does not sync**, and point the
app at the new location. `lefty-chrome.sh` defaults to `$HOME/lefty/chrome-profile`
for this reason; if you override it with `LEFTY_CHROME_PROFILE`, keep the override out
of `~/Documents` and `~/Desktop`. The script warns you if you don't.

If you must leave a directory where it is, **append `.nosync` to its name** — iCloud
skips those — and update the path the app is launched with.

**Close the app first.** Moving a browser profile while the browser is running is how
you corrupt the profile and lose your logged-in sessions.

## Cleaning up what already accumulated

1. **Diff before you assume.** `diff "file 2.md" "file.md"`. In the real case 13 of 14
   were byte-identical and one was an *older* copy — "it's just a duplicate" is a guess
   until diff says so.
2. **Compare modification times too.** If the ` 2` copy is newer, it may hold the work.
3. **Move them aside, do not delete them.** A staging folder you empty yourself, with
   the directory structure preserved so anything can be put back exactly where it was.
4. **Leave `.git` internals alone.** Conflict copies like `.git/HEAD 2` are ignored by
   git and harmless where they sit. Reaching into `.git` to tidy three files is a worse
   risk than the files.

## A trap that will waste your time

Shells vary, and **`timeout` is not always installed** — on the machine where this was
found, `timeout` returned `command not found`. Every command wrapped in it produced
**no output and exited cleanly**, which reads exactly like "this folder has none."

A false zero is indistinguishable from good news. A folder was nearly reported clean
when it held 11,806 duplicates. Check your tools exist before you trust a quiet result,
and prefer writing `find` output to a file over wrapping it in a timeout.
