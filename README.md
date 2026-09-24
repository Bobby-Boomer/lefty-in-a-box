# Lefty in a Box

**An AI chief of staff that actually knows your business — and two icons on your desktop to talk to it.**

Not a chatbot. A chatbot talks. This one works: it remembers your business between conversations, listens
when you hold a key and talk, and answers out loud a second later.

---

## What it costs, up front

**About $40 a month, and most of that is not paid to us.**

This runs on Claude Code, which needs a paid Claude plan — Pro works, and that is roughly $20/mo paid to
Anthropic. **The software here is free and always will be.** If you join the community, that is a separate
$20/mo, and what it buys is the setup preloaded with your business plus a room full of people building
alongside you.

We would rather tell you that in the first paragraph than have you find it in step six.

---

## What you get

- **Memory** — plain text files on your own computer. Your AI reads them at the start of every conversation
  and writes to them as you work, so it stops forgetting your business. Nothing leaves your machine.
  **If it gets something wrong, you open the file and fix it, and it believes the file.**
  The folder is already shaped as an [Obsidian](https://obsidian.md) vault if you want to browse it
  visually, but **Obsidian is optional and we do not install it** — these are text files and any editor
  opens them.
- **Voice** — hold one key, talk, let go. It answers through your speakers in a real voice. **The code ships
  here** (`voice-line/`), and `voice-line/install.sh` walks you through the rest. Speech recognition runs
  **on your machine** — nothing you say is sent anywhere — and the voice it answers in is free and local
  too. **The honest catch:** on a Mac the speech engine is one Homebrew command, but on Windows it has to be
  compiled, which is the hardest step in this whole project. Skipping voice is a perfectly good choice.
- **A face** — a full-screen visualizer so you can see at a glance whether it is listening, thinking, or
  answering. **This one ships in the repo** (`visualizer/`), so there is nothing to build and nothing to
  download. It needs Python 3 and a browser, and it runs with or without the voice piece — without voice it
  simply sits at idle.
- **Hands** *(optional)* — a hand-tracked glass board you control in the air. Needs a camera. No headset.
- **Your name on it, and your look** — the setup asks what you want to call your agent and which of five
  screen looks you want (green rain, amber, ice, violet, or mono). Your answers land in
  `lefty.config.json`, the screen picks up the colour and your desktop icons carry the name. Change either
  one any time with `install/personalize.sh` — nothing is baked in.
- **Two desktop shortcuts** — *Talk to &lt;your name&gt;* and *&lt;your name&gt; Screen*. Double-click. That
  is the whole interface after setup.
- **Skills that do real work on day one** — daily notes, inbox triage into drafts you approve, meeting
  transcripts into owners and next steps, one long piece into a week of content.

You pick which pieces you want. Memory alone is a perfectly good answer.

---

## Install

**Step 1 — get Claude Code.** Not the Claude app and not the website. Claude Code lives in your terminal and
can build things on your computer. Follow Anthropic's installer at
[claude.com/claude-code](https://claude.com/claude-code), then run `claude` once and sign in with your
Claude account.

**Step 2 — paste this.** Pick the one for your machine, because they are genuinely different.

**macOS or Linux** — in Terminal:

```
mkdir -p ~/lefty && cd ~/lefty && git clone https://github.com/bobby-boomer/lefty-in-a-box && cd lefty-in-a-box && claude "set me up"
```

**Windows** — you need [Git for Windows](https://git-scm.com/download/win) first, which gives you Git Bash.
Open **Git Bash** (press the Windows key, type `git bash`) and paste the exact same line above.

> **Do not paste that line into PowerShell.** It chains commands with `&&`, and Windows PowerShell 5.1 — the
> one that ships with Windows — does not support `&&`. It will error out. If you would rather stay in
> PowerShell, run these five lines one at a time instead:
>
> ```
> mkdir "$env:USERPROFILE\lefty" -Force
> cd "$env:USERPROFILE\lefty"
> git clone https://github.com/bobby-boomer/lefty-in-a-box
> cd lefty-in-a-box
> claude "set me up"
> ```
>
> Full click-by-click Windows walkthrough, including how to open Git Bash: **[docs/windows-install.md](docs/windows-install.md)**

That is it. Claude Code opens with the installer already talking to you. It asks your name, asks what you
want to call *it* and which look you want on screen, asks which pieces you want, builds them, puts the
shortcuts on your desktop, and then interviews you about your business so the memory is not empty on day one.

**Already ran this before?** Use this one instead — the install command above will stop with "destination
path already exists" because the folder is already there.

```
cd ~/lefty/lefty-in-a-box && git pull && claude "set me up"
```

It finds what you have, keeps what is yours, and upgrades the rest. It never deletes anything you made.

---

## Who made this, and why it is free

Built by [Bobby Boomer](https://bobbyboomer.com) while running real businesses with it every day. It is
MIT licensed — take it, change it, use it commercially, no permission needed.

Credit where it is due: the one-paste install pattern is inspired by
[Jared Rhodenizer's](https://jaredrhod.com) work, which is excellent and also free. This is a separate
build, written from scratch, not a fork.

- The free course, the book and the audio: [bobbyboomer.com](https://bobbyboomer.com)
- The community: [Compassionate Capitalists](https://www.skool.com/compassionate-capitalists-2939/about)

---

## Honest limits

- **Mac is tested. Windows is written but unverified.** The installer, the
  skills and the memory are plain text and work anywhere. The Windows shortcut
  script and launchers are written and shipped, but **nobody has run them on a
  real Windows machine yet.** When someone does and it works, this line changes.
  Until then we are not going to claim it.
- **Voice needs a microphone**, and the hand-tracked board needs a camera.
- **First install downloads a lot** — the speech models are large, and they are fetched at setup rather
  than shipped in this repo.
- **This is not a product with a support desk.** It is a tool that is given away. The community is where
  help lives.
