import assert from 'node:assert/strict';
import { execFileSync, spawn } from 'node:child_process';
import { existsSync } from 'node:fs';
import { readFile, writeFile, mkdir, open, rename, rm, readdir } from 'node:fs/promises';
import { dirname, resolve, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createServer } from 'node:net';
import { request } from 'node:http';
import { chromium } from 'playwright';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const artifacts = join(root, 'BrowserTests/artifacts');
const fixtures = join(root, 'BrowserTests/.fixtures/Counter with spaces');
await mkdir(artifacts, { recursive: true });
await mkdir(fixtures, { recursive: true });
await rm(join(fixtures, 'Views'), { recursive: true, force: true });
const source = join(fixtures, 'Counter "quoted".swift');
const original = await readFile(join(root, 'Examples/Counter.swift'), 'utf8');
await writeFile(source, original);
execFileSync(join(root, 'scripts/check.sh'), ['build', '--product', 'roost-playground'], { stdio: 'inherit' });
const binPath = execFileSync(join(root, 'scripts/check.sh'), ['bin-path'], { encoding: 'utf8' }).trim();
const binary = join(binPath, 'roost-playground');
const port = await new Promise(resolvePort => {
  const server = createServer();
  server.listen(0, '127.0.0.1', () => { const port = server.address().port; server.close(() => resolvePort(port)); });
});
const log = await open(join(artifacts, 'supervisor.log'), 'w');
const environment = { ...process.env, ROOST_PLAYGROUND_ROOT: root };
const launch = () => spawn(binary, [source, '--no-open', '--port', String(port)], {
  cwd: root, env: environment, stdio: ['ignore', log.fd, log.fd],
});
let child = launch();
const base = `http://127.0.0.1:${port}`;
let browser;
async function poll(predicate, label, timeout = 240_000) {
  const deadline = Date.now() + timeout;
  while (Date.now() < deadline) {
    if (child.exitCode !== null || child.signalCode !== null) throw new Error(`Supervisor exited (${child.exitCode ?? child.signalCode}) during ${label}`);
    const value = await predicate();
    if (value) return value;
    await new Promise(resolve => setTimeout(resolve, 200));
  }
  throw new Error(`Timed out: ${label}`);
}
async function status() { try { return await (await fetch(`${base}/__playground/status`)).json(); } catch { return null; } }
async function phase(name) { return poll(async () => { const s = await status(); return s?.phase === name && s; }, name); }
async function readyAfter(generation) {
  return poll(async () => {
    const s = await status();
    if (s?.phase === 'failed') throw new Error(s.diagnostics);
    return s?.phase === 'ready' && s.generation > generation && s;
  }, `ready after build ${generation}`);
}
async function save(text, file = source) {
  await writeFile(`${file}.saving`, text);
  await rename(`${file}.saving`, file);
  await phase('building');
}
async function stop(signal = 'SIGTERM') {
  if (child.exitCode !== null || child.signalCode !== null) return;
  const exited = new Promise(resolve => child.once('exit', resolve));
  child.kill(signal);
  const graceful = await Promise.race([exited.then(() => true), new Promise(resolve => setTimeout(() => resolve(false), 8_000))]);
  if (!graceful) { child.kill('SIGKILL'); await exited; throw new Error('Supervisor did not stop gracefully'); }
  assert.equal(child.exitCode, 0, 'Supervisor should exit cleanly');
}
const previewAddresses = new Set();
async function assertClosed(address) {
  let connected = false;
  try { await fetch(address, { signal: AbortSignal.timeout(1000) }); connected = true; } catch {}
  assert(!connected, `Owned preview still listening: ${address}`);
}
try {
  await poll(status, 'shell startup', 15_000);
  const ready = await poll(async () => {
    const s = await status();
    if (s?.phase === 'failed') throw new Error(s.diagnostics);
    return s?.phase === 'ready' && s;
  }, 'first compile');
  assert.equal(ready.generation, 1);
  const chrome = process.env.PLAYWRIGHT_EXECUTABLE_PATH || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
  browser = await chromium.launch({ headless: true, ...(existsSync(chrome) ? { executablePath: chrome } : {}) });
  const page = await browser.newPage({ viewport: { width: 1280, height: 960 } });
  const errors = [];
  page.on('pageerror', error => errors.push(error.message));
  await page.goto(base);
  const frame = page.frameLocator('#preview');
  async function connected(state) {
    previewAddresses.add(state.previewURL);
    await poll(async () => await page.locator('#preview').getAttribute('src') === state.previewURL, 'iframe replacement', 10_000);
    await frame.locator('[data-esw-state="connected"]').waitFor();
  }
  async function count(expected) { await poll(async () => await frame.locator('#count').textContent() === String(expected), `counter = ${expected}`, 10_000); }
  await connected(ready);
  await frame.locator('[data-esw-state="connected"]').waitFor();
  await frame.getByRole('button', { name: 'Increase', exact: true }).click();
  await poll(async () => await frame.locator('#count').textContent() === '1', 'counter increment', 10_000);
  await frame.getByLabel('Your name').fill('William');
  await frame.getByRole('button', { name: 'Say hello' }).click();
  await poll(async () => await frame.locator('#greeting').textContent() === 'Hello, William!', 'form event', 10_000);
  await page.screenshot({ path: join(artifacts, 'ready.png'), fullPage: true });
  console.log('PASS: one-file counter, form, and bundled live client');
  assert((await page.context().cookies()).some(cookie => cookie.name.startsWith('_roost_playground_')), 'Playgrounds must isolate their session cookie from other local Roost apps');
  assert(!(await page.context().cookies()).some(cookie => cookie.name === '_roost_session'));
  const rejectedHost = await new Promise((resolveStatus, reject) => {
    request(`${base}/__playground/status`, { headers: { Host: 'untrusted.example' } }, response => {
      response.resume(); resolveStatus(response.statusCode);
    }).on('error', reject).end();
  });
  assert.equal(rejectedHost, 403);
  assert.throws(() => execFileSync(binary, [source, '--no-open', '--port', String(port)], { env: environment, stdio: 'pipe' }), /already has a running playground/);
  await page.evaluate(() => { window.parentIdentity = 'stable-shell'; });
  await page.setViewportSize({ width: 390, height: 844 });
  await page.screenshot({ path: join(artifacts, 'mobile.png'), fullPage: true });
  assert(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth), 'Shell fits a narrow viewport');
  assert(await frame.locator('html').evaluate(html => html.scrollWidth <= html.clientWidth), 'Preview fits a narrow viewport');
  await page.setViewportSize({ width: 1280, height: 960 });

  let current = ready;
  if (!process.env.PLAYGROUND_UNDO_ONLY) {
    const broken = original + '\nlet broken: Int = "compiler error"\n';
    await save(broken);
    await frame.getByRole('button', { name: 'Increase', exact: true }).click();
    await count(2);
    const failure = await phase('failed');
    assert.equal(failure.previewURL, ready.previewURL);
    assert.equal(failure.generation, 1);
    assert(failure.diagnostics.includes(source), 'Diagnostics point to the original quoted filename');
    assert.match(failure.diagnostics, /cannot convert|cannot assign/);
    await page.locator('#diagnostic-panel').waitFor({ state: 'visible' });
    await frame.getByRole('button', { name: 'Increase', exact: true }).click();
    await count(3);
    await page.screenshot({ path: join(artifacts, 'compiler-error.png'), fullPage: true });
    console.log('PASS: compiler error retains the live preview, original filename, and state');

    // An unused-argument formatter can remove a binding used only inside the template string.
    const brokenMacro = original.replace('func render(_ state: State)', 'func render(_: State)');
    assert.notEqual(brokenMacro, original);
    await save(brokenMacro);
    const macroFailure = await phase('failed');
    assert.equal(macroFailure.previewURL, ready.previewURL);
    assert(macroFailure.diagnostics.startsWith('macro expansion #live:'));
    assert(macroFailure.diagnostics.includes("cannot find 'state' in scope"));
    assert(macroFailure.diagnostics.includes(source));
    assert(!macroFailure.diagnostics.includes('Conflicting identity'));
    assert(!macroFailure.diagnostics.includes('\x1b'));
    await poll(async () => (await page.locator('#diagnostics').textContent()).includes("cannot find 'state' in scope"), 'macro error shown');
    await frame.getByRole('button', { name: 'Increase', exact: true }).click();
    await count(4);
    await page.screenshot({ path: join(artifacts, 'macro-error.png'), fullPage: true });
    console.log('PASS: macro errors appear before dependency warnings while the previous preview remains live');

    const saved = original.replaceAll('A little Swift, live.', 'Saved and live.');
    await save(saved);
    current = await readyAfter(1);
    assert.equal(current.generation, 2);
    await connected(current);
    await frame.getByRole('heading', { name: 'Saved and live.' }).waitFor();
    await count(0);
    assert.equal(await page.evaluate(() => window.parentIdentity), 'stable-shell');
    await assertClosed(ready.previewURL);
    console.log('PASS: atomic save refreshes only the preview and resets live state');

    await save(original.replaceAll('A little Swift, live.', 'Outdated version.'));
    const latest = original.replaceAll('A little Swift, live.', 'Newest version.');
    await writeFile(source, latest);
    current = await readyAfter(2);
    assert.equal(current.generation, 3, 'An edit during compilation must not promote stale code');
    await connected(current);
    await frame.getByRole('heading', { name: 'Newest version.' }).waitFor();
    console.log('PASS: only the latest source snapshot is promoted');

    const startupFailure = 'import Foundation\n' + latest.replace('static let title', 'static func main() async throws { exit(23) }\n    static let title');
    await save(startupFailure);
    const failedStartup = await phase('failed');
    assert.equal(failedStartup.generation, 3);
    assert.equal(failedStartup.previewURL, current.previewURL);
    assert.match(failedStartup.diagnostics, /exited before it was ready \(23\)/);
    await frame.getByRole('button', { name: 'Increase', exact: true }).click();
    await count(1);
    console.log('PASS: a failed candidate cannot replace the working server');

    await rename(source, `${source}.missing`);
    await poll(async () => (await status())?.diagnostics.includes('Cannot read the playground files'), 'source deletion');
    await frame.getByRole('button', { name: 'Increase', exact: true }).click();
    await count(2);
    await writeFile(source, latest);
    await phase('building');
    current = await readyAfter(3);
    await connected(current);
    await count(0);
    await rm(`${source}.missing`);
    console.log('PASS: deleted/recreated source recovers without stopping the runner');

    const workerPID = Number(execFileSync('/usr/sbin/lsof', ['-t', '-iTCP:' + new URL(current.previewURL).port, '-sTCP:LISTEN'], { encoding: 'utf8' }).trim());
    assert(workerPID > 0);
    process.kill(workerPID, 'SIGKILL');
    const crash = await phase('failed');
    assert.equal(crash.previewURL, undefined);
    assert.match(crash.diagnostics, /preview process exited/);
    await save(original);
    current = await readyAfter(4);
    await connected(current);
    console.log('PASS: worker crash is reported and a source edit recovers');

    await stop('SIGINT');
    for (const address of previewAddresses) await assertClosed(address);
    // Reuse the same input, port and browser tab: the lock must be released and the shell must reconnect.
    await writeFile(source, broken);
    child = launch();
    await poll(status, 'restart', 15_000);
    const initialFailure = await phase('failed');
    assert.equal(initialFailure.generation, 0);
    assert.equal(initialFailure.previewURL, undefined);
    await page.locator('#diagnostic-panel').waitFor({ state: 'visible' });
    await save(original);
    current = await readyAfter(0);
    await connected(current);
    await count(0);
    console.log('PASS: clean SIGINT, lock release, initially broken file, and recovery in the same tab');

    const templateSource = await readFile(join(root, 'Examples/Templated/Counter.swift'), 'utf8');
    const templateFile = join(fixtures, 'Views/counter.live.heex');
    const template = await readFile(join(root, 'Examples/Templated/Views/counter.live.heex'), 'utf8');
    await mkdir(dirname(templateFile), { recursive: true });
    await writeFile(templateFile, template);
    await save(templateSource);
    current = await readyAfter(1);
    await connected(current);
    await frame.getByRole('heading', { name: 'A template, alive.' }).waitFor();
    await frame.getByRole('button', { name: 'Increase', exact: true }).click();
    await count(1);
    await save(template.replace('A template, alive.', 'Saved template.'), templateFile);
    current = await readyAfter(2);
    await connected(current);
    await frame.getByRole('heading', { name: 'Saved template.' }).waitFor();
    await count(0);
    await save(template.replace('{count}', '{missingValue}'), templateFile);
    const templateError = await phase('failed');
    assert.equal(templateError.generation, 3);
    assert(templateError.diagnostics.includes(templateFile), 'Template diagnostics point to the original Views path');
    await rm(templateFile);
    await phase('building');
    const deletedTemplate = await phase('failed');
    assert.match(deletedTemplate.diagnostics, /renderCounterLive/);
    await save(template, templateFile);
    current = await readyAfter(3);
    await connected(current);
    await frame.getByRole('heading', { name: 'A template, alive.' }).waitFor();
    console.log('PASS: HEEx plugin, template-only rebuild, diagnostic mapping, deletion and recreation');
  }

  // A compiler may finish an obsolete A while B is on disk, then the editor undoes back to A.
  // An obsolete attempt must not suppress that second A forever.
  const beforeUndo = current.generation;
  const versionA = original + '\n// Undo regression: A\n';
  await save(versionA);
  const compilationLog = (await status()).logPath;
  await writeFile(source, original + '\n// Undo regression: B\n');
  await poll(async () => (await readFile(compilationLog, 'utf8')).includes('Build complete!'), 'obsolete compilation finishes');
  await new Promise(resolve => setTimeout(resolve, 200));
  await writeFile(source, versionA);
  current = await poll(async () => {
    const s = await status();
    return s?.phase === 'ready' && s.generation > beforeUndo && s;
  }, 'undo to a discarded source snapshot', 20_000);
  await connected(current);
  await frame.getByRole('heading', { name: 'A little Swift, live.' }).waitFor();
  console.log('PASS: A → B → A undo cannot strand the watcher on an obsolete attempt');

  assert.deepEqual(errors, [], 'No uncaught browser JavaScript errors');
  const workspace = dirname(dirname(current.logPath));
  await stop();
  for (const address of previewAddresses) await assertClosed(address);
  assert.deepEqual(await readdir(join(workspace, 'runs')), [], 'No staged workers remain after shutdown');
  console.log('PASS: SIGTERM closes workers and removes staged executables');
} finally {
  await browser?.close();
  await stop();
  await log.close();
}
