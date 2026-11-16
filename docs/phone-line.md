# Phone line: talk to your agent from your phone

Hold a button on your phone, say what you need, and hear your agent answer out loud. The visualizer
is its face, so you can see it listening, thinking and talking. The work still happens on your
computer, with everything your agent knows.

**Mac only for now.** Works on your home Wi-Fi out of the box, and on cell service too once you add
Tailscale (free, five minutes, see *Away from home* below).

## What you need

- The voice line already working on your Mac (it supplies the hearing and the voice).
- Your phone on the same Wi-Fi as your Mac — or Tailscale on both, to use it anywhere.

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

**You hear two voices, or what sounds like an echo.** It is not an echo and it is not your speaker.
It is one reply being split across two open pages. Each page used to be sent the audio for every
sentence, and a sentence's audio can only be fetched once, so two pages raced: one won and played
sentence 1, the other was refused and skipped ahead to sentence 2. Two voices, slightly apart, reading
different halves of the same answer. **Fixed 2026-11-16** — the reply audio is now addressed to the one
page that asked, and any other open page shows the text silently. If you are on a version before that,
close every phone line tab except the one you are using. iOS Safari keeps a backgrounded tab connected,
so a page you opened yesterday still counts as open.

**The page loads but it never hears you.** The hearing server isn't running. Start the desk voice
line once, or use `autostart.sh`, which starts it for you.

**"No module named uvicorn".** You're on an old copy. Pull the latest: `start.sh` now brings its own.

**It wants your OK for something.** Tool approvals show on the phone as Yes and No. No answer within
90 seconds counts as no.

## Away from home

**This works.** Your phone needs a route to your Mac, and [Tailscale](https://tailscale.com) gives you
one for free: a private network between your own devices, no ports opened on your router.

1. Install Tailscale on your Mac and on your phone, and sign in to the **same account** on both.
2. On the Mac, ask for the link again:

```
bash ~/lefty/lefty-in-a-box/voice-line/phone/url.sh
```

It now prints a `...ts.net` address instead of a `192.168...` one, and a second line telling you which
networks that link works on. **That one link works on cell and at home**, so there is nothing to swap
when you walk out the door.

`url.sh --lan` forces the old local address if you ever want the traffic off the tailnet.

### If it worked at home and does nothing on cell

Two causes, both already handled, both worth knowing because they look identical from the phone:

- **The link was a home-only address.** A `192.168...` address is private to your Wi-Fi and resolves to
  nothing once you leave it. Re-run `url.sh`; if it still prints `192.168...`, Tailscale is not running
  or not signed in on the Mac.
- **The certificate did not cover the Tailscale name.** The page is served over HTTPS because phone
  browsers only allow the microphone on a secure page, and the certificate is self-signed. If it was
  created before you set Tailscale up, it lists only your local addresses, so Safari refuses the
  `ts.net` link — **which looks exactly like a broken connection even though the server is answering
  fine.** `start.sh` now notices this and rebuilds the certificate once, keeping the old pair as
  `.cert.pem.pre-tailscale`. Restart the phone line after installing Tailscale and it sorts itself out.

Safari will ask you to trust the certificate the first time on each address. That is expected for a
self-signed cert on your own machine. Tap through it once, then **Share → Add to Home Screen** and it
opens like an app.
