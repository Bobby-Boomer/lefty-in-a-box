# Phone line: talk to your agent from your phone

Hold a button on your phone, say what you need, and hear your agent answer out loud. The visualizer
is its face, so you can see it listening, thinking and talking. The work still happens on your
computer, with everything your agent knows.

**Mac only for now, and on your home Wi-Fi.** Your phone and your Mac need to be on the same network.

## What you need

- The voice line already working on your Mac (it supplies the hearing and the voice).
- Your phone on the same Wi-Fi as your Mac.

## Start it

In the Terminal:

```
bash ~/lefty/lefty-in-a-box/voice-line/phone/start.sh
```

Then get your link:

```
bash ~/lefty/lefty-in-a-box/voice-line/phone/url.sh
```

Open that link on your phone. **The link has a key in it. Treat it like a password:** don't post it or
paste it into notes. Your phone remembers the key after the first visit.

The first time, your phone warns that the connection isn't private. That's expected: the Mac made its
own certificate, because phones only allow the microphone on secure pages. Tap through once.

Tip: on the phone, "Add to Home Screen" makes it open like an app.

## Make it always on

```
bash ~/lefty/lefty-in-a-box/voice-line/phone/autostart.sh
```

It starts when you log in and restarts itself if it crashes. It also starts the hearing and voice
servers on its own, so it keeps working after you close the desk voice line. To turn it off:
`bash autostart.sh --remove`.

**The repo must not live in Documents, Desktop or Downloads** for this. macOS blocks background jobs
there and the job fails without telling you. `autostart.sh` checks and stops you.

## When something goes wrong

**"Locked. Open the link with the access key."** Open the full link from `url.sh` once on that phone.

**It hears you but answers in clipped, broken-sounding fragments.** A terse-style plugin (we hit this
with "caveman") was shaping the replies. The phone line switches that plugin off for its own
conversations only. If you use a different style plugin, add it to `EXTRA_SETTINGS` in
`voice-line/phone/server.py`.

**The page loads but it never hears you.** The hearing server isn't running. Start the desk voice
line once, or use `autostart.sh`, which starts it for you.

**"No module named uvicorn".** You're on an old copy. Pull the latest: `start.sh` now brings its own.

**It wants your OK for something.** Tool approvals show on the phone as Yes and No. No answer within
90 seconds counts as no.

## Away from home

Not yet. That needs a private network between your phone and your Mac (Tailscale is the plan). This
page will say when it's ready.
