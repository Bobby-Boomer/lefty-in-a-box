# Lefty in a Box

**An AI chief of staff that actually knows your business — and icons on your desktop to reach it.**

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
- **Upkeep that runs itself** — the voice line keeps one long conversation going so your agent remembers
  what you just said, and left alone that conversation grows until it hits the model's context limit and
  compacts **mid-sentence** — which reads as your agent suddenly going strange for no reason. Three guards
  now prevent that and keep session transcripts from filling your disk, automatically, on every start.
  Nothing to configure. [How it works and how to tune it](docs/voice-line-upkeep.md).
- **A face** — a full-screen visualizer so you can see at a glance whether it is listening, thinking, or
  answering. **This one ships in the repo** (`visualizer/`), so there is nothing to build and nothing to
  download. It needs Python 3 and a browser, and it runs with or without the voice piece — without voice it
  simply sits at idle.
- **Your phone** — text your agent on Telegram and it answers with everything it knows. **Ships here**
  (`telegram/`), standard-library Python, **nothing to install**. You make a bot with Telegram's own
  @BotFather, hand your agent the token, and the first message you send locks the bridge to your chat and
  nobody else's. `telegram/README.md` is the five-minute walkthrough.
- **Talk to it from your phone** *(Mac, home Wi-Fi)* — hold a button on your phone, speak, and hear it answer,
  with the visualizer as its face. Reuses the voice line's speech, so nothing new to install.
  [Set it up](docs/phone-line.md).
- **More than one agent, actually working together** — a shared inbox on disk (`agent-bus/`) so your
  agents hand work to each other instead of routing everything through you. **The part that matters is
  the watcher:** an agent that reports in and waits looks exactly like an agent that is working, and on
  the machine this came from that cost five hours of a finished job sitting on disk. Now an unworked
  queue pings your manager agent, and reaches you only if the manager ignores it.
  [Set it up](docs/second-agent.md). *(The bus runs anywhere; the watcher is macOS-only.)*
- **It reaches YOU** — the phone line only answers when you open it, so on its own it is not a way for your
  agent to get hold of you. `voice-line/notify.py` is: it pushes a message to your phone and can attach a
  **tap-to-talk link straight into the voice line.** The part worth knowing is why it checks the channel
  before sending — **a revoked bot token still looks perfectly fine on disk**, so the naive version
  reported success while every message was thrown away.
  [How it works, and how to prove it still works](docs/push-notifications.md).
- **Hands** *(not in the box yet)* — a hand-tracked glass board you control in the air, no headset. It is
  real and it works, but no hands code ships here, so setup does not offer it. When it lands, this line
  changes.
- **Your name on it, and your look** — the setup asks what you want to call your agent and which of five
  screen looks you want (green rain, amber, ice, violet, or mono). Your answers land in
  `lefty.config.json`, the screen picks up the colour and your desktop icons carry the name. Change either
  one any time with `install/personalize.sh` — nothing is baked in.
- **Desktop shortcuts** — *Type to &lt;your name&gt;* for a normal chat window, *&lt;your name&gt; Screen* for
  the face, and *Talk to &lt;your name&gt;* once the voice piece is installed. Double-click. That is the whole
  interface after setup. You never have to open a terminal again.
- **Skills that do real work on day one** — daily notes, inbox triage into drafts you approve, meeting
  transcripts into owners and next steps, one long piece into a week of content.

You pick which pieces you want. Memory alone is a perfectly good answer.

---

## Install

**Step 1 — get Claude Code.** Not the Claude app and not the website. **The Claude desktop app has the
same name but does not give your terminal a `claude` command** — that mix-up is the most common install
failure we have seen. Claude Code lives in your terminal and can build things on your computer. On a Mac or
Linux, paste this into Terminal (other options at [claude.com/claude-code](https://claude.com/claude-code)):

```
curl -fsSL https://claude.ai/install.sh | bash
```

Then **close the Terminal window and open a new one** — an open window never sees newly installed
commands — run `claude` once, and sign in with your Claude account. Still "command not found"? Run
`echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc` and open a new window.

**Mac, first time ever using Terminal? Expect one box before anything else.** The first command that
touches `git` makes macOS say *"No developer tools were found, requesting install"* and open an
**Install Command Line Developer Tools** window. Click Install and let it run. **It will claim something
like "About 10 hours, 4 seconds remaining." Ignore that number** — it is wrong every time and it
usually finishes in a few minutes. This is Apple's installer, not ours, and it only happens once.

**Mac, and you want voice? Get Homebrew too.** The voice piece installs its speech engine with it. Paste
the line from [brew.sh](https://brew.sh), type your Mac password when asked (nothing shows while you type,
that is normal), and **run the "Next steps" lines it prints at the end** — skip them and `brew` says
"command not found" even though it is installed. Then open a new window. Copy commands from this page, not
from a chat window: chat apps swap in curly quotes and the line fails.

> **Homebrew has to go in its own Terminal window, not in the chat with your agent.** If you ask your
> agent to install it for you, the command runs but then sits there forever. The reason: Homebrew stops
> to ask for your Mac password, and **the agent's window cannot take a typed password** — that prompt
> needs a real terminal you are sitting in front of. Nothing is broken and nothing is wrong with your
> machine. Press **Cmd + Space**, type **Terminal**, press Enter, paste the brew.sh line into *that*
> window, and type your password there. When it says **"Installation successful!"**, go back to your
> agent and tell it you are done.

**Before you paste, know what it is going to ask you.**

The install ends with a short interview about your business. Six questions, one at a time. That is what
fills the memory so it is not empty on day one, and it is the part that makes this different from a
chatbot. Have rough answers ready and the whole thing takes about five minutes. Go in cold and you will
stall halfway through trying to word it well.

- What is your business, in your own words?
- Who is it for?
- What are you actually trying to build this year?
- Who are the people it will hear about, partners, clients, family in the business?
- What should it never do without asking you first?
- How do you like to be talked to, blunt, gentle, funny?

Nothing here is permanent. Your answers land in plain text files you can open and fix, and you can stop
mid-interview, go think, and come back. Nothing breaks if you walk away.

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

## If something looks wrong

- **Lefty boots with no name, or says your `CLAUDE.md` is missing, or the browser dies with
  `error -11`** → [docs/icloud-offloading.md](docs/icloud-offloading.md). Your files are fine; iCloud
  took them off the disk. There is a guard in `bin/` that fixes it for good.

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
