#!/usr/bin/env node
// Click and type in the shared browser — at the INPUT layer, like a real person.
//
// Why this exists, and why you should not skip it:
//
// The obvious way to click something is `element.click()` from cdp-eval.mjs. On
// a plain web page that works. On anything built with React, Angular or Vue —
// which is most of the apps you actually want your AI to drive — it silently
// does nothing. Those frameworks listen for *trusted* pointer events, and a
// scripted click is not one. The worst part is that it reports success. Your AI
// says "clicked" and the page never moved.
//
// This sends events through Chrome's Input domain instead, which the page cannot
// tell apart from your mouse and keyboard.
//
//   node browser/cdp-click.mjs <urlSubstring> click    "<visible text>"
//   node browser/cdp-click.mjs <urlSubstring> clicksel "<css selector>"
//   node browser/cdp-click.mjs <urlSubstring> clickjs  "<js returning an element>"
//   node browser/cdp-click.mjs <urlSubstring> type     "<text>"
//   node browser/cdp-click.mjs <urlSubstring> key      "Enter|Tab|Escape|Backspace"
//   node browser/cdp-click.mjs <urlSubstring> clear    [howManyCharacters]
//
// `click` matches the SMALLEST element whose text matches, exact before partial.
// Smallest matters: big apps wrap every button in several nested divs that all
// contain the same words, and clicking the outer one lands on empty padding.
//
// `clickjs` is the escape hatch for when text matching is not enough — for
// example a dropdown you must hit by its role, identified only by the text of a
// child. Pass an expression that evaluates to the element itself.
//
// Port follows the shared browser: LEFTY_CHROME_PORT, default 9222.

const PORT = process.env.LEFTY_CHROME_PORT || '9222';
const [, , match, action, arg] = process.argv;

if (!match || !action) {
  console.error('usage: cdp-click.mjs <urlSubstring> click|clicksel|clickjs|type|key|clear "<arg>"');
  process.exit(1);
}

let targets;
try {
  targets = await (await fetch(`http://127.0.0.1:${PORT}/json`)).json();
} catch {
  console.error(`No shared browser answering on port ${PORT}. Start it with browser/lefty-chrome.sh`);
  process.exit(2);
}

const hits = targets.filter((t) => (t.url || '').includes(match) && t.webSocketDebuggerUrl);
const target = hits.find((t) => t.type === 'page') || hits[0];
if (!target) { console.error(`No tab matching "${match}"`); process.exit(3); }

const ws = new WebSocket(target.webSocketDebuggerUrl);
let id = 0;
const pending = new Map();
const send = (m, p = {}) => new Promise((res, rej) => {
  const i = ++id; pending.set(i, { res, rej });
  ws.send(JSON.stringify({ id: i, method: m, params: p }));
});
ws.addEventListener('message', (e) => {
  const d = JSON.parse(e.data);
  if (d.id && pending.has(d.id)) {
    const { res, rej } = pending.get(d.id);
    pending.delete(d.id);
    d.error ? rej(new Error(JSON.stringify(d.error))) : res(d.result);
  }
});
await new Promise((r, j) => { ws.addEventListener('open', r); ws.addEventListener('error', j); });

const ev = async (expr) => {
  const r = await send('Runtime.evaluate', { expression: expr, returnByValue: true, awaitPromise: true });
  if (r.exceptionDetails) throw new Error(r.exceptionDetails.exception?.description || 'eval threw');
  return r.result?.value;
};
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

const byText = (txt) => `(() => {
  const want = ${JSON.stringify(txt)};
  const all = [...document.querySelectorAll('button,a,div[role=button],span,div,[role=menuitem],[role=option],label')]
    .filter(e => e.offsetParent !== null);
  const area = e => { const r = e.getBoundingClientRect(); return r.width * r.height; };
  const exact = all.filter(e => (e.innerText||'').trim() === want).sort((a,b) => area(a)-area(b));
  if (exact.length) return exact[0];
  return all.filter(e => (e.innerText||'').trim().includes(want)).sort((a,b) => area(a)-area(b))[0] || null;
})()`;

// Input events are coordinate-based, so an off-screen element would otherwise be
// "clicked" wherever those coordinates happen to land. Scroll it in, let the
// scroll settle, then measure again.
async function pointAt(findExpr) {
  return ev(`(() => {
    const el = ${findExpr};
    if (!el || !el.getBoundingClientRect) return null;
    el.scrollIntoView({block:'center', inline:'center'});
    const r = el.getBoundingClientRect();
    if (!r.width || !r.height) return null;
    return {x: r.x + r.width/2, y: r.y + r.height/2,
            text: (el.innerText||el.value||'').trim().slice(0,60), tag: el.tagName};
  })()`);
}

async function clickAt(x, y) {
  await send('Input.dispatchMouseEvent', { type: 'mouseMoved', x, y, buttons: 0 });
  await sleep(60);
  await send('Input.dispatchMouseEvent', { type: 'mousePressed', x, y, button: 'left', buttons: 1, clickCount: 1 });
  await sleep(45);
  await send('Input.dispatchMouseEvent', { type: 'mouseReleased', x, y, button: 'left', buttons: 0, clickCount: 1 });
}

try {
  if (action === 'click' || action === 'clicksel' || action === 'clickjs') {
    const finder = action === 'click' ? byText(arg)
      : action === 'clicksel' ? `document.querySelector(${JSON.stringify(arg)})`
      : `(${arg})`;
    const first = await pointAt(finder);
    if (!first) { console.log(JSON.stringify({ ok: false, error: 'not found or not visible', arg })); process.exit(4); }
    await sleep(250);
    const p = (await pointAt(finder)) || first;
    await clickAt(p.x, p.y);
    console.log(JSON.stringify({ ok: true, clicked: p.text, tag: p.tag, at: [Math.round(p.x), Math.round(p.y)] }));
  } else if (action === 'type') {
    // One character at a time, as real key events. Note: emoji and other
    // characters outside the basic plane do NOT survive this — they are
    // surrogate pairs and arrive mangled. For those, set the field's value with
    // the native setter from cdp-eval.mjs and fire an 'input' event instead.
    for (const ch of arg) {
      await send('Input.dispatchKeyEvent', { type: 'keyDown', text: ch, unmodifiedText: ch });
      await send('Input.dispatchKeyEvent', { type: 'keyUp', text: ch, unmodifiedText: ch });
      await sleep(12);
    }
    console.log(JSON.stringify({ ok: true, typed: arg.length + ' chars' }));
  } else if (action === 'key') {
    const map = { Enter: [13, 'Enter'], Tab: [9, 'Tab'], Escape: [27, 'Escape'], Backspace: [8, 'Backspace'] };
    const [code, key] = map[arg] || [0, arg];
    await send('Input.dispatchKeyEvent', { type: 'rawKeyDown', windowsVirtualKeyCode: code, key });
    await send('Input.dispatchKeyEvent', { type: 'keyUp', windowsVirtualKeyCode: code, key });
    console.log(JSON.stringify({ ok: true, key: arg }));
  } else if (action === 'clear') {
    // Emptying a field you have already clicked into. Select-all then type looks
    // obvious and does not work in every framework's input — the new text ends
    // up appended to the old. Deleting key by key always works.
    const n = parseInt(arg || '80', 10);
    for (let i = 0; i < n; i++) {
      await send('Input.dispatchKeyEvent', { type: 'rawKeyDown', windowsVirtualKeyCode: 46, key: 'Delete', code: 'Delete' });
      await send('Input.dispatchKeyEvent', { type: 'keyUp', windowsVirtualKeyCode: 46, key: 'Delete', code: 'Delete' });
      await send('Input.dispatchKeyEvent', { type: 'rawKeyDown', windowsVirtualKeyCode: 8, key: 'Backspace', code: 'Backspace' });
      await send('Input.dispatchKeyEvent', { type: 'keyUp', windowsVirtualKeyCode: 8, key: 'Backspace', code: 'Backspace' });
    }
    console.log(JSON.stringify({ ok: true, cleared: n }));
  } else {
    console.error('unknown action', action);
    process.exit(1);
  }
} catch (e) {
  console.log(JSON.stringify({ ok: false, error: e.message }));
  process.exit(5);
}
ws.close();
process.exit(0);
