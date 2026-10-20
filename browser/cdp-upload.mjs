#!/usr/bin/env node
// Upload files through a web page in the shared browser, without the file picker.
//
// The problem: every "Browse files" button opens the operating system's own file
// dialog. That dialog is not part of the web page, so no amount of clicking from
// inside the browser can reach it. This is the single most common place where an
// AI driving a browser gets stuck — it can fill in every field on a form and then
// cannot attach the one file.
//
// The way through is to hand the file straight to the page's hidden
// <input type=file>, which is what the picker would have done anyway. The page
// cannot tell the difference and its upload starts normally.
//
//   node browser/cdp-upload.mjs <urlSubstring> <path> [path...] [-r] [--dry] [--selector <css>]
//
//   -r / --recursive   include files in subdirectories (flattened — see below)
//   --dry              list exactly what would be sent, send nothing
//   --selector <css>   which file input to use, when the page has more than one
//
// About --selector. By default this takes the FIRST <input type=file> on the page,
// which is right almost everywhere, because most pages have exactly one. It is
// wrong on pages that have several — a profile form with both an avatar picker and
// a document picker, for instance. The symptom is nasty: the upload succeeds, the
// script reports success, and the file lands in the wrong field. Found 2026-10-20
// on YouTube Studio, whose thumbnail picker is specifically `input#file-loader`.
// When in doubt, run --dry and inspect the page first; pass --selector only when
// you have actually looked and found more than one input.
//
// ALWAYS --dry first. You are handing files to a website; look at the list.
//
// Flattening: a plain file input has no notion of folders, so subdirectories
// collapse into one flat set. Before using -r across folders, check for repeated
// filenames — two files with the same name mean one can overwrite the other on
// the far side. Keep a manifest of the original paths if structure matters.
//
// Port follows the shared browser: LEFTY_CHROME_PORT, default 9222.

import { readdirSync, statSync } from 'node:fs';
import { basename, join, resolve } from 'node:path';

const PORT = process.env.LEFTY_CHROME_PORT || '9222';
const argv = process.argv.slice(2);
const match = argv.shift();
const selValueIdx = argv.indexOf('--selector') + 1;
const paths = argv.filter((a, i) => !a.startsWith('-') && !(selValueIdx > 0 && i === selValueIdx));
const flags = argv.filter((a) => a.startsWith('-'));
const RECURSIVE = flags.includes('-r') || flags.includes('--recursive');
const DRY = flags.includes('--dry');
// --selector takes a value, so it is read off the raw argv rather than the flag list.
const selIdx = argv.indexOf('--selector');
const SELECTOR = selIdx !== -1 ? argv[selIdx + 1] : 'input[type=file]';

if (!match || !paths.length) {
  console.error('usage: cdp-upload.mjs <urlSubstring> <path> [path...] [-r] [--dry] [--selector <css>]');
  process.exit(1);
}

// Finder/Explorer metadata is noise in an upload.
const JUNK = new Set(['.DS_Store', 'Thumbs.db', 'desktop.ini']);
const walk = (d) =>
  readdirSync(d)
    .filter((f) => !JUNK.has(f))
    .flatMap((f) => {
      const p = join(d, f);
      const st = statSync(p);
      if (st.isFile()) return [p];
      return st.isDirectory() && RECURSIVE ? walk(p) : [];
    });

// Accepting MANY paths matters: the set you want is often a couple of folders
// plus a few loose files sitting beside dozens of unrelated ones, and pointing
// this at the parent folder would sweep all of them up.
let files = [...new Set(paths.flatMap((raw) => {
  const p = resolve(raw);
  return statSync(p).isFile() ? [p] : walk(p);
}))];

if (!files.length) { console.error('no files found under', paths.join(', ')); process.exit(2); }

const gb = (b) => (b / 1073741824).toFixed(2);
const total = files.reduce((n, p) => n + statSync(p).size, 0);
console.error(`[plan] ${files.length} files, ${gb(total)} GB${RECURSIVE ? ' (recursive, flattened)' : ''}`);

// Name collisions are silent data loss once the files land. Say so loudly.
const seen = new Map();
for (const p of files) {
  const b = basename(p);
  seen.set(b, (seen.get(b) || 0) + 1);
}
const dupes = [...seen].filter(([, n]) => n > 1);
if (dupes.length) {
  console.error(`[WARNING] ${dupes.length} filename(s) appear more than once — one may overwrite the other:`);
  for (const [name, n] of dupes.slice(0, 10)) console.error(`   ${n}x  ${name}`);
}

for (const p of files) console.error(`   ${(statSync(p).size / 1048576).toFixed(1).padStart(9)} MB  ${basename(p)}`);
if (DRY) { console.log(JSON.stringify({ ok: true, dry: true, count: files.length, bytes: total, collisions: dupes.length })); process.exit(0); }

let targets;
try {
  targets = await (await fetch(`http://127.0.0.1:${PORT}/json`)).json();
} catch {
  console.error(`No shared browser answering on port ${PORT}.`);
  process.exit(3);
}
const target = targets.find((t) => t.type === 'page' && (t.url || '').includes(match) && t.webSocketDebuggerUrl);
if (!target) { console.error(`No tab matching "${match}"`); process.exit(4); }

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

await send('DOM.enable');
const { root } = await send('DOM.getDocument', { depth: -1, pierce: true });
const { nodeId } = await send('DOM.querySelector', { nodeId: root.nodeId, selector: SELECTOR });
if (!nodeId) {
  console.error(`No element matching "${SELECTOR}" on this page. Open the upload dialog first —`);
  console.error('most sites only create the input after you click their Upload button.');
  process.exit(5);
}

// Say which input was used. Silence here is how a file ends up in the wrong field
// on a multi-input page without anyone noticing.
const { nodeIds: allInputs } = await send('DOM.querySelectorAll', { nodeId: root.nodeId, selector: 'input[type=file]' });
if (allInputs && allInputs.length > 1 && selIdx === -1) {
  console.error(`[WARNING] this page has ${allInputs.length} file inputs and no --selector was given.`);
  console.error('          Using the first one. If the file lands in the wrong field, that is why.');
}

await send('DOM.setFileInputFiles', { nodeId, files });
console.error(`[sent] ${files.length} file handles to the page. The upload now runs in the browser.`);
console.error('Do NOT reload or navigate that tab — a reload aborts every transfer in the queue.');
console.log(JSON.stringify({ ok: true, count: files.length, bytes: total }));
ws.close();
process.exit(0);
