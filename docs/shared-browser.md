# The shared browser — give your AI eyes and hands

Your AI gets a Chrome window it can **see and drive**, sitting right next to you. You watch it work, you
take over whenever you want, and your everyday browser is never touched.

This is the setup behind the move worth learning: **"put that on a tab for me."** Instead of answering with
a wall of text in the terminal, your AI builds a real page in a tab. It is scannable, it survives the
session, and it pastes clean.

---

## What you are actually building

Two browsers on one machine:

| | Your Chrome | The shared Chrome |
|---|---|---|
| Who uses it | You | You **and** your AI |
| Your logins | All of them | Only what you log into deliberately |
| Debugging port | Off | On, bound to `127.0.0.1` |
| If the AI misbehaves | Untouched | Quit the window, it is over |

**Why it has to be a second one.** Chrome 136 and later refuse `--remote-debugging-port` on your default
profile. That is a deliberate security change and no flag turns it off. Do not fight it — this is the
supported shape and it is also the safer one.

---

## Step 1 — start the shared browser

Get the scripts:

```
cd ~/lefty/lefty-in-a-box && git pull
```

**macOS or Linux:**

```
bash browser/lefty-chrome.sh
```

**Windows:**

```
browser\lefty-chrome.cmd
```

A fresh Chrome window opens. It will look empty — that is correct, it is a brand new profile.

**Now log in, once, to the sites you want your AI to work in.** Those logins persist, so you only do this
the first time. Put in what you need and nothing you do not: this window is drivable by anything running on
this machine, which is exactly why it is separate.

---

## Step 2 — point your AI at it

Register the Chrome DevTools MCP server with Claude Code:

```
claude mcp add chrome-devtools -- npx -y chrome-devtools-mcp@latest --browserUrl=http://127.0.0.1:9222 --redactNetworkHeaders=true --screenshotFormat=webp --screenshotMaxWidth=1400
```

What those flags buy you:

- `--browserUrl` — attach to the browser **you already started and logged into**, rather than launching a
  blank one. This is the whole point. Without it you get a browser with none of your sessions.
- `--redactNetworkHeaders` — strips auth headers out of anything the AI reads. Leave it on.
- `--screenshotFormat=webp` and `--screenshotMaxWidth=1400` — smaller screenshots. Costs less, works fine.

Start `claude`, approve the server when it asks, and check it is alive:

```
claude mcp list
```

`chrome-devtools` should say connected.

---

## Step 3 — the test that proves it

In `claude`, say:

> Look at the shared browser and tell me what tabs are open.

If it reads back your real tabs, you are done. It can now navigate, click, fill forms, read pages and take
screenshots in that window while you watch.

Then try the actual move:

> Put that on a tab for me.

---

## What it genuinely cannot do

Say these out loud before someone discovers them the hard way.

- **Native dialogs need a human.** The macOS "allow camera" bubble, Windows file pickers, print dialogs —
  these are drawn by the operating system, not the page. The AI cannot click them. (`lefty-chrome.sh`
  passes `--use-fake-ui-for-media-stream` purely to dodge the camera one, which otherwise hangs forever.)
- **Some buttons only answer to a real click.** A synthetic click dispatched from page JavaScript does
  nothing on plenty of modern apps — Google surfaces especially. Real input events at real coordinates
  work. If a click "succeeds" and nothing happens, that is this.
- **Cross-origin iframes are their own world.** Page-level scripts cannot reach inside them. They have to
  be attached to directly, as their own target.
- **It is not autonomous.** It drives the browser you started, in the window you are watching. Close the
  window and it stops.

---

## The rule that makes this safe to use

Your AI reads, writes, edits, runs commands and drives this browser without asking every time. **Three
things always stop and wait for a human:**

1. **Outbound messages.** Email, SMS, posts, chat. It drafts, you send. These reach another person
   instantly and cannot be recalled.
2. **Installing software.** Ask, get a yes, then install.
3. **Spending money.** Any purchase, any subscription, any amount.

That is what makes the rest of it fine to leave unsupervised.

---

## When something goes wrong

**"Port 9222 never answered."** Another Chrome is already using that profile folder. Quit every Chrome
window using it and run the script again.

**The AI sees a blank browser with none of your logins.** The MCP server launched its own Chrome instead of
attaching to yours. Check `--browserUrl=http://127.0.0.1:9222` is really in the command, and that the
shared Chrome was running first.

**A click reports success but nothing happens.** See "some buttons only answer to a real click" above.

**You want it to stop, right now.** Quit the shared Chrome window. That is the whole kill switch.
