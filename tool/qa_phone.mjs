// فحص ضمان جودة كمستخدم على الجوال (390×844) في Edge: استيراد نسخة بصيغة التطبيق السابق (صور JPEG حقيقية مولّدة، بيانات محايدة)
// عبر زر الاستيراد الفعلي، ثم التنقل في كل الشاشات، وتسجيل الأخطاء والزمن واللقطات. الاستخدام: node tool/qa_phone.mjs [عدد]
import { createRequire } from 'node:module';
import http from 'node:http';
import { readFileSync, existsSync, mkdirSync, writeFileSync } from 'node:fs';
import { join, dirname, extname } from 'node:path';
import { fileURLToPath } from 'node:url';

const N = +(process.argv[2] || 150);
const root = join(dirname(fileURLToPath(import.meta.url)), '..'), web = join(root, 'build', 'web'), out = join(root, 'test', 'out', 'qa'); mkdirSync(out, { recursive: true });
const require = createRequire(join(root, '..', 'favorites-app', 'package.json'));
const { chromium } = require('playwright-core');
const MIME = { '.html': 'text/html', '.js': 'text/javascript', '.mjs': 'text/javascript', '.wasm': 'application/wasm', '.json': 'application/json', '.png': 'image/png', '.ttf': 'font/ttf', '.otf': 'font/otf', '.svg': 'image/svg+xml' };
const server = http.createServer((q, r) => { let p = join(web, decodeURIComponent(q.url.split('?')[0].split('#')[0])); if (p.endsWith('\\') || p.endsWith('/') || !existsSync(p)) p = join(web, 'index.html'); r.writeHead(200, { 'Content-Type': MIME[extname(p)] || 'application/octet-stream' }); r.end(readFileSync(p)); });
await new Promise(r => server.listen(0, '127.0.0.1', r));
const base = 'http://127.0.0.1:' + server.address().port + '/';
let browser; for (const channel of ['msedge', 'chrome']) { try { browser = await chromium.launch({ channel, headless: true }); break; } catch {} }

// ---------- نسخة احتياطية بصيغة القديم ----------
const gen = await browser.newPage();
const jpegs = await gen.evaluate(n => { const out = []; for (let i = 0; i < n; i++) { const c = document.createElement('canvas'); c.width = 900; c.height = 1200; const x = c.getContext('2d');
  const g = x.createLinearGradient(0, 0, 900, 1200); g.addColorStop(0, `hsl(${i * 37 % 360},50%,40%)`); g.addColorStop(1, `hsl(${(i * 37 + 80) % 360},55%,15%)`); x.fillStyle = g; x.fillRect(0, 0, 900, 1200);
  for (let k = 0; k < 14; k++) { x.fillStyle = `hsla(${(i * 37 + k * 30) % 360},70%,60%,.5)`; x.beginPath(); x.arc((k * 173 + i * 7) % 900, (k * 241 + i * 11) % 1200, 60 + k * 9, 0, 7); x.fill(); }
  out.push(c.toDataURL('image/jpeg', .82)); } return out; }, 24);
await gen.close();
const cc = ['US', 'CZ', 'ES', 'BR', 'HU', 'FR', 'RU', 'UA'];
const items = [];
for (let i = 0; i < N; i++) {
  const y = 1985 + i % 15;
  items.push({ id: 'old-' + i, name: 'Sample Person ' + i, aliases: i % 4 ? '' : 'Alias ' + i, birth: `${y}-0${1 + i % 9}-1${i % 9}`, country: cc[i % 8], rating: (i % 10) / 2, fav: i % 3 === 0,
    tags: ['tag' + (i % 5)], lists: i % 6 === 0 ? ['L1'] : [], stashId: i % 2 ? `00000000-0000-0000-0000-${String(i).padStart(12, '0')}` : '', notes: i % 7 === 0 ? 'note ' + i : '',
    photos: [jpegs[i % 24], jpegs[(i + 5) % 24]], thumb: jpegs[i % 24], thumbV: 3, views: i % 9, lastView: Date.now() - i * 1e6, elo: 1000 + i, tier: ['S', 'A', 'B', ''][i % 4],
    works: Array.from({ length: 15 }, (_, k) => ({ t: `Scene ${i}-${k}`, s: 'Studio ' + (k % 6), d: `${2015 + k % 10}-0${1 + k % 9}-1${k % 9}`, ...(k % 3 === 0 ? { w: 1, wd: `2025-0${1 + k % 9}-1${k % 9}` } : {}), ...(k % 5 === 0 ? { q: 1 } : {}), ...(k % 4 === 0 ? { r: 4 } : {}), p: `https://img.test/w${k % 6}.jpg` })),
    added: Date.now() - i * 86400000, updated: Date.now() - i * 3600000, unknownOldField: 'keep-me' });
}
items.push({ id: 'minor-x', name: 'Should Be Skipped', birth: '2014-01-01', photos: [] });
const backup = JSON.stringify({ app: 'vkte-favorites', v: 5, exportedAt: Date.now(), lists: [{ id: 'L1', name: 'قائمتي القديمة' }], wlists: [], prefs: { vkte_theme: 'dark', vkte_key: 'MUST-NOT-IMPORT' }, items });
const bpath = join(out, 'old-backup.json'); writeFileSync(bpath, backup);
console.log(`backup: ${N} performers, ${(backup.length / 1048576).toFixed(1)} MB`);

// ---------- الجلسة ----------
const ctx = await browser.newContext({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 2, locale: 'ar' });
await ctx.route('https://**', r => r.fulfill({ status: 200, contentType: 'image/jpeg', body: Buffer.from(jpegs[3].split(',')[1], 'base64') }));
const page = await ctx.newPage(); const errors = [], log = [];
page.on('pageerror', e => errors.push('pageerror: ' + e.message)); page.on('console', m => { if (m.type() === 'error') errors.push('console: ' + m.text().slice(0, 300)); });
const shot = async n => { await page.waitForTimeout(700); await page.screenshot({ path: join(out, n + '.png') }); };
const btn = name => page.getByRole('button', { name }).first();
const nav = name => page.getByRole('tab', { name }).or(page.getByRole('button', { name })).first();
const t0 = Date.now();
await page.goto(base + '?qa=1'); await page.waitForTimeout(4000);
log.push('open: ' + (Date.now() - t0) + 'ms'); await shot('01-empty');
// استيراد عبر الزر الحقيقي
await page.getByRole('tab', { name: /المزيد/ }).or(btn(/المزيد/)).first().click(); await page.waitForTimeout(800);
const [fc] = await Promise.all([page.waitForEvent('filechooser', { timeout: 15000 }), btn(/استيراد نسخة احتياطية/).click()]);
await fc.setFiles(bpath);
await page.waitForTimeout(1500); await shot('02-import-confirm');
const ti = Date.now(); await btn(/^استيراد$/).click();
for (let k = 0; k < 300; k++) { await page.waitForTimeout(1000); const s = await page.screenshot(); if (k > 3 && k % 3 === 0) { const busy = await page.evaluate(() => document.querySelectorAll('flt-semantics').length); if (busy >= 0 && k > 8) break; } }
log.push('import: ' + (Date.now() - ti) + 'ms'); await shot('03-import-done');
// المكتبة
await nav(/المكتبة/).click(); await page.waitForTimeout(1500); await shot('04-library');
const libText = await page.getByText(/ممثلة/).first().textContent().catch(() => '');
log.push('library header: ' + libText);
await page.mouse.move(195, 600); for (let k = 0; k < 6; k++) { await page.mouse.wheel(0, 900); await page.waitForTimeout(250); } await shot('05-library-scrolled');
// البحث
await page.mouse.click(195, 112); await page.waitForTimeout(300); await page.keyboard.type('Person 12'); await page.waitForTimeout(800); await shot('06-search');
await page.keyboard.press('Control+A'); await page.keyboard.press('Backspace'); await page.waitForTimeout(500);
// فتح ممثلة
await page.mouse.click(290, 330); await page.waitForTimeout(1500); await shot('07-performer');
await page.mouse.move(195, 600); await page.mouse.wheel(0, 900); await page.waitForTimeout(600); await shot('08-performer-works');
await page.mouse.click(195, 420); await page.waitForTimeout(1200); await shot('09-work-sheet');
await page.keyboard.press('Escape'); await page.waitForTimeout(500);
await page.getByRole('button', { name: /Back|رجوع/ }).first().click().catch(() => page.goBack()); await page.waitForTimeout(1000);
// الأعمال، اكتشف، الاستديو، المزيد
for (const [k, n] of [['الأعمال', '10-works'], ['اكتشف', '11-discover'], ['الاستديو', '12-studio'], ['الرئيسية', '13-home']]) { await nav(new RegExp(k)).click().catch(e => errors.push(k + ': ' + e.message)); await page.waitForTimeout(1500); await shot(n); }
// الاستديو: اكتشاف بلا مفتاح (صور المشاهد)
await nav(/الاستديو/).click(); await page.waitForTimeout(800); await btn(/ابدأ الاكتشاف|اكتشاف صور جديدة/).click().catch(() => {}); await page.waitForTimeout(4000); await shot('14-studio-after');
const facts = await page.evaluate(() => ({ heapMB: performance.memory ? Math.round(performance.memory.usedJSHeapSize / 1048576) : null }));
log.push('heapMB: ' + facts.heapMB);
writeFileSync(join(out, 'report.txt'), [...log, '', 'ERRORS:', ...errors].join('\n'));
console.log(log.join('\n')); console.log(errors.length ? 'ERRORS:\n' + errors.slice(0, 15).join('\n') : 'no errors');
await browser.close(); server.close();
