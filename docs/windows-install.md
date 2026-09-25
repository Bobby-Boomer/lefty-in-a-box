# Lefty in a Box — the Windows install, step by step

> **Read this first. Windows is not proven yet.**
> Mac is tested end to end. **Windows is written and shipped but has never been run on a real Windows
> machine.** The README says exactly that, and it will keep saying it until someone runs it and reports
> back. If something breaks here, that is the useful outcome, not a failure. Tell us what you saw.

---

## Step 0 — what it costs, said up front

**About $40 a month, and most of it is not paid to us.**

The software here is free and always will be. It runs on Claude Code, which needs a paid Claude plan,
roughly $20 a month paid to Anthropic. The community is a separate $20 a month if you want it.

You need a Claude account before anything below works.

---

## Step 1 — install Claude Code

**Not the Claude app. Not the website.** Claude Code lives in your terminal and can build things on your
computer.

1. Get it from [claude.com/claude-code](https://claude.com/claude-code) and follow Anthropic's Windows installer.
2. Open a terminal, run `claude` once, and sign in with your Claude account.
3. If it asks you to authorize in a browser, do that.

**Stop here until `claude` opens and talks to you.**

---

## Step 2 — pick your shell. This is the part the Mac instructions get wrong on Windows.

> **The defect, and why this page exists.**
> The one-paste install command in the README is written for Mac. It chains commands with `&&` and uses
> `mkdir -p` and `~`. **Windows PowerShell 5.1, which is what ships on Windows by default, does not support
> `&&`.** Pasted there it will error out. Use one of the two versions below instead.

**Option A — Git Bash. Recommended, and the closest thing to the tested Mac path.**

If you install Git for Windows you get Git Bash, a terminal that speaks the same language as the Mac. You
need Git anyway for the clone. In Git Bash the original one-liner works exactly as written.

---

## Step 2a — how to actually get Git Bash open. Click by click.

Git Bash is a terminal window. Windows does not come with it, so you install it first. About three minutes,
and you only ever do it once.

### a. Download Git for Windows

Go to [git-scm.com/download/win](https://git-scm.com/download/win). The download starts on its own. If it
does not, click the **64-bit Git for Windows Setup** link.

### b. Run the installer and click Next through everything

Open the file you just downloaded. It asks a lot of questions about editors, line endings and branch names.
**Do not change any of them.** The defaults are correct for this. Next, Next, Next, Install.

When it finishes, untick "View Release Notes" if it offers, and click Finish.

### c. Open Git Bash

Press the **Windows key**, type **git bash**, press **Enter**.

A black window opens with a line ending in a `$` and a blinking cursor. That `$` is the prompt. That is the
whole thing. You are in.

Second way, if you prefer: in File Explorer, right-click empty space in any folder and choose **Git Bash Here**.

> **Pasting into Git Bash is not Ctrl+V. This trips up everybody once.**
> Copy the command, then in the Git Bash window either **right-click and choose Paste**, or press
> **Shift + Insert**. Ctrl+V does nothing in some builds. Then press **Enter**.

### d. Sanity check before the big command

```
git --version
```

```
claude --version
```

If the second says command not found, go back to Step 1 and finish the Claude Code install. **Do not run
the big command until both of these answer.**

---

## Step 2b — run the install

**In Git Bash** — right-click Paste or Shift+Insert, then Enter:

```
mkdir -p ~/lefty && cd ~/lefty && git clone https://github.com/bobby-boomer/lefty-in-a-box && cd lefty-in-a-box && claude "set me up"
```

**Option B — if you would rather stay in PowerShell**, run these five lines one at a time:

```
mkdir "$env:USERPROFILE\lefty" -Force
cd "$env:USERPROFILE\lefty"
git clone https://github.com/bobby-boomer/lefty-in-a-box
cd lefty-in-a-box
claude "set me up"
```

**Already ran it once?** Use this instead, or the clone fails with "destination path already exists":

```
cd ~/lefty/lefty-in-a-box && git pull && claude "set me up"
```

---

## Step 3 — the setup conversation, beat by beat

It is a conversation, not a progress bar. Here is exactly what it does, in order, so nothing on screen is a
surprise.

**1. It says hello and asks your name.** *"Hi, I'm Lefty. Before I set anything up: what should I call
you?"* It uses that name from there on.

**1b. Then it asks what you want to call IT, and how the screen should look.** Most people keep Lefty, but
it is your agent — Jarvis, Friday, your grandmother's name, whatever you will enjoy saying out loud. The
screen comes in five looks: **rain**, **amber**, **ice**, **violet** and **mono**. Both answers are saved
in `lefty.config.json`, both are optional, and you can change either one later by running
`install\personalize.cmd` again. Your desktop icons get rebuilt under the new name automatically.

**2. It checks your machine and tells you in one line.** No raw output, no stack traces. If Python is
missing or older than 3.10, voice is out and it says so. No microphone, no voice. Under 5 GB free, it warns
you before downloading the speech models.

**3. It asks which of the three pieces you want.** One question at a time.

| Piece | What it does for you |
|---|---|
| **Memory** | It remembers your business between conversations instead of starting from zero. Plain text files on your own computer, which you can open and fix. |
| **Voice** | Hold a key, talk, it answers out loud. |
| **Screen** | A full-screen face so you can see when it is listening or thinking. |

The hand-tracked glass board exists, but it is not in the box yet. The wizard is told not to offer it, and
an icon for something that will not open is worse than no icon.

**Memory alone is a completely valid answer.** It is the piece that does the most work, and the wizard is
told not to upsell you.

**4. It builds only what you picked.** If you took voice, the speech models are large — a few minutes, once.

**5. It puts your shortcuts on the desktop**, then warns you about the blue box *before* you click.
Everyone gets **Type to \<Name\>** and **\<Name\> Screen**. **Talk to \<Name\>** only appears once the voice
piece is actually installed. If you took memory only, the Type icon is your way in and nothing is missing.

**6. The business interview. This is the part that matters.** Six or seven questions, one at a time, a real
conversation rather than a form:

- What is your business, in your own words?
- Who is it for?
- What are you actually trying to build this year?
- Who are the people I'll hear about — partners, clients, family in the business?
- What should I never do without asking you first?
- How do you like to be talked to — blunt, gentle, funny?

Your answers go into `memory/Business.md`, `People.md`, `Rules.md` and `Goals.md`. Your files, on your
computer. Nothing leaves the machine, and if it gets something wrong you open the file and fix it.

**7. It hands the folder over.** The last thing it runs is `install\finish-setup.cmd`, which writes
`agent.md` at the root of the folder. That file is the switch: before it exists, opening the folder starts
the setup wizard; after it exists, opening the folder starts **your agent**, which reads `memory\` first and
answers to the name you chose. It is a plain text file and it is yours to edit.

**8. It does not say "installation complete."** It ends the way you will use it: *"All set. Your icons are
on the desktop. What are we working on today?"*

> **The hard rule the wizard runs under.**
> It never installs anything on your computer without asking first, in plain words, including what it is
> and roughly how long it takes. You pasted one command into a terminal on trust. It is told not to spend
> that trust.

---

## Step 4 — your desktop shortcuts

The installer runs this for you. Here it is so you know what it did:

```
powershell -ExecutionPolicy Bypass -File install\shortcuts.ps1 -InstallDir "%CD%"
```

It creates real `.lnk` shortcuts, so they get a proper icon and a normal double-click rather than a bare
batch file on your desktop. They are named after whatever you called your agent:

| Icon | What it opens | When you get it |
|---|---|---|
| **Type to \<Name\>** | A normal chat window, already pointed at your memory folder | Always |
| **\<Name\> Screen** | The full-screen face | Always |
| **Talk to \<Name\>** | Hold the key, talk, let go | Only once the voice piece is installed |

Run that command again any time — after installing voice, or after renaming your agent — and the icons are
rebuilt to match. Old ones under a previous name are cleaned up rather than left to pile up.

> **Expect a blue box the first time. It is not a virus warning.**
> Windows may show a SmartScreen panel saying it protected your PC. Click **More info**, then **Run
> anyway**. It appears because the shortcut is new and unsigned, not because anything is wrong. We are
> telling you before it happens rather than after.

---

## Known gaps on Windows, so you are not surprised

1. **No `preflight.ps1`.** The wizard's machine check is written to run `./install/preflight.sh --json`, and
   only the Mac shell script exists. In PowerShell that call fails; in Git Bash it may run. If the wizard
   stumbles at the machine check, this is why. Tell it to continue and check things conversationally.
2. **The README one-liner is Mac-shaped.** Covered in Step 2 above.
3. **The `.lnk` shortcuts and the `.cmd` launchers have never run on real Windows.** They are written to
   explain themselves rather than throw a file-not-found, but that is untested too.

---

## What to report back

These four answers are what flip this page and the README from "unverified" to "tested":

1. Did the **clone** work, and which shell did you use — Git Bash or PowerShell?
2. Did the **wizard talk to you** — did it ask your name and which pieces you wanted?
3. Did the **icons appear** on your desktop under the name you chose, and did double-clicking them do
   something sensible? The **Type to \<Name\>** one is the important test — it should open a chat that
   already knows your business.
4. Did the **SmartScreen prompt** look like what we described, or did it say something different?

If a launcher failed before install finished, tell us which message you saw.

---

*The rule that does not move, on any platform: it reads, writes, edits, runs commands and drives the
browser without asking. Three things always stop and wait for a human — **outbound messages, installing
software, and spending money.** It drafts. You send.*
