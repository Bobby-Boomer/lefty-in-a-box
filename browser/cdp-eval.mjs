#!/usr/bin/env node
// Read a page in the shared browser — run JavaScript inside a tab and print what
// it returns.
//
// This is how your AI *looks* at a page. A screenshot costs a lot and tells you
// how things look; this tells you what the page actually says, which is usually
// what you need.
//
//   node browser/cdp-eval.mjs <urlSubstring> "<expression>"
//   node browser/cdp-eval.mjs <urlSubstring> --file <path/to/expr.js>
//
// Examples:
//   node browser/cdp-eval.mjs github.com "document.title"
//   node browser/cdp-eval.mjs mail.google "document.body.innerText.slice(0,2000)"
//
// Port follows the shared browser: LEFTY_CHROME_PORT, default 9222.
//
// Two gotchas are already handled here, both found the hard way:
//
// 1. IFRAMES. Ad and tracker iframes often carry the page URL inside their own
//    URL, so a plain substring match attaches to the tracker instead of the
//    page — and every expression comes back empty. The symptom is
//    `document.body.innerText` with length 0 on a page that plainly has text.
//    This prefers a real page target. Set CDP_IFRAME=1 when you genuinely want
//    the iframe: some app builders render their editor in one, and that content
//    is unreachable from the top page.
//
// 2. LONG EXPRESSIONS. Anything with quotes in it fights the shell. Use --file.

import { readFileSync } from 'node:fs';

const PORT = process.env.LEFTY_CHROME_PORT || '9222';
const [, , match, arg, argFile] = process.argv;

if (!match || !arg) {
  console.error('usage: cdp-eval.mjs <urlSubstring> "<expr>" | <urlSubstring> --file <path>');
  console.error('       LEFTY_CHROME_PORT overrides the port (default 9222)');
  process.exit(1);
}
const expression = arg === '--file' ? readFileSync(argFile, 'utf8') : arg;

let targets;
try {
  targets = await (await fetch(`http://127.0.0.1:${PORT}/json`)).json();
} catch {
  console.error(`No shared browser answering on port ${PORT}. Start it with browser/lefty-chrome.sh`);
  process.exit(2);
}

const hits = targets.filter((t) => (t.url || '').includes(match) && t.webSocketDebuggerUrl);
const target = process.env.CDP_IFRAME === '1'
  ? hits[0]
  : hits.find((t) => t.type === 'page') || hits[0];

if (!target) {
  console.error(`No tab matching "${match}". Open tabs:`);
  console.error(targets.filter((t) => t.type === 'page').map((t) => `  ${t.url?.slice(0, 100)}`).join('\n') || '  (none)');
  process.exit(3);
}
console.error(`[attached] ${target.type} ${target.url.slice(0, 90)}`);

const ws = new WebSocket(target.webSocketDebuggerUrl);
let id = 0;
const pending = new Map();
const send = (method, params = {}) =>
  new Promise((resolve, reject) => {
    const msgId = ++id;
    pending.set(msgId, { resolve, reject });
    ws.send(JSON.stringify({ id: msgId, method, params }));
  });

ws.addEventListener('message', (ev) => {
  const msg = JSON.parse(ev.data);
  if (msg.id && pending.has(msg.id)) {
    const { resolve, reject } = pending.get(msg.id);
    pending.delete(msg.id);
    msg.error ? reject(new Error(JSON.stringify(msg.error))) : resolve(msg.result);
  }
});

ws.addEventListener('open', async () => {
  try {
    const res = await send('Runtime.evaluate', {
      expression,
      returnByValue: true,
      awaitPromise: true,
      userGesture: true,
    });
    if (res.exceptionDetails) {
      console.error('EXCEPTION:', res.exceptionDetails.exception?.description || JSON.stringify(res.exceptionDetails));
      process.exit(4);
    }
    const v = res.result?.value;
    console.log(typeof v === 'string' ? v : JSON.stringify(v, null, 2));
    ws.close();
    process.exit(0);
  } catch (e) {
    console.error('ERR:', e.message);
    process.exit(5);
  }
});

ws.addEventListener('error', (e) => {
  console.error('WS ERROR', e.message || e);
  process.exit(6);
});
