# Lefty boots as a stranger, or the browser dies with error -11

## The symptom

One or more of these, usually together:

- Lefty has **no name and no rules**. Ask who it is and you get a generic assistant.
- Claude Code says your `CLAUDE.md` is **missing** — but you can see the file sitting right there.
- Browser control fails with **`Unknown system error -11`**.
- Memory files read as **empty**, or a script exits `0` and writes nothing.

Nothing is deleted. Nothing is corrupted. Your files are fine.

## What is actually happening

If your install lives in **iCloud Drive** and macOS has **Optimize Mac Storage** turned on, iCloud
takes the bytes off your disk when space gets tight and leaves a stub in place. The file still shows
in Finder with its real size. It just is not there.

Trying to read a stub while iCloud is slow or unreachable fails with `EDEADLK`,
*"Resource deadlock avoided"* — which bubbles up as **error -11**.

Check it yourself:

```bash
find ~/lefty -type f -flags +dataless | wc -l     # how many are offloaded
ls -lO ~/lefty/CLAUDE.md | awk '{print $5}'       # "compressed,dataless" = offloaded
```

## The fix, in two parts

**1. Pin the small stuff.** In Finder, right-click your Lefty folder and your memory folder and choose
**Keep Downloaded**. The files that matter are tiny — identity, scripts, notes — so this costs almost
no disk. Do **not** pin a folder full of `node_modules`, media or renders: that fills the drive, which
is what triggered the offloading in the first place.

Leaving iCloud Drive entirely also works, but you lose your offsite copy of Lefty's memory. Pinning
keeps it.

**2. Run the guard.** Keep Downloaded is manual and per-item, so it drifts. `bin/icloud-guard.sh`
checks the critical set on every session start, pulls back anything offloaded, **verifies it landed**,
and logs which files it had to rescue. Wire it into `~/.claude/settings.json`:

```json
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          { "type": "command", "command": "bash /path/to/lefty/bin/icloud-guard.sh", "timeout": 120 }
        ]
      }
    ]
  }
}
```

Run it by hand any time:

```bash
bash bin/icloud-guard.sh        # prints what it restored; writes logs/icloud-guard.log
```

Exit `0` means everything in the critical set is on disk. Exit `1` means something could not be
restored — usually iCloud signed out or offline. Check **System Settings → Apple Account → iCloud**.

## Two traps if you do this by hand

1. **`brctl download <folder>` does nothing for the files inside it.** It only takes single files:
   ```bash
   find <dir> -type f -flags +dataless -print0 | xargs -0 -n1 brctl download
   ```
2. **The `dataless` flag can linger after `brctl download` returns.** Force a real read
   (`head -c 1 <file>`) and then check the flag again. The fact that `brctl` ran is not proof the
   file came back.

## Why it runs every session

On the machine this was found on, six agent boot files, 32 scripts and 315 notes were offloaded at
once. They were restored by hand — and **four of the boot files were offloaded again the same day**.
A one-time repair does not hold. A check that runs before every boot does.
