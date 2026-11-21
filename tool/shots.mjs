// لقطات وتجربة نسخة الويب في Edge الحقيقي (بيانات تجريبية محايدة ?demo=1، وصور مولّدة لنطاق img.test الوهمي).
// الاستخدام: node tool/shots.mjs   (بعد flutter build web --release --no-web-resources-cdn)
import { createRequire } from 'node:module';
import http from 'node:http';
import { readFileSync, existsSync, mkdirSync } from 'node:fs';
import { join, dirname, extname } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..'), web = join(root, 'build', 'web'), out = join(root, 'test', 'out');
mkdirSync(out, { recursive: true });
const require = createRequire(join(root, '..', 'favorites-app', 'package.json'));
const { chromium } = require('playwright-core');
const MIME = { '.html': 'text/html', '.js': 'text/javascript', '.mjs': 'text/javascript', '.wasm': 'application/wasm', '.json': 'application/json', '.png': 'image/png', '.ttf': 'font/ttf', '.otf': 'font/otf', '.svg': 'image/svg+xml', '.bin': 'application/octet-stream' };
const server = http.createServer((q, r) => { let p = join(web, decodeURIComponent(q.url.split('?')[0].split('#')[0])); if (p.endsWith('\\') || p.endsWith('/') || !existsSync(p)) p = join(web, 'index.html'); r.writeHead(200, { 'Content-Type': MIME[extname(p)] || 'application/octet-stream' }); r.end(readFileSync(p)); });
await new Promise(r => server.listen(0, '127.0.0.1', r));
const base = 'http://127.0.0.1:' + server.address().port + '/';
let browser; for (const channel of ['msedge', 'chrome']) { try { browser = await chromium.launch({ channel, headless: true }); break; } catch {} }

// صور تجريبية مولدة (تدرجات وأشكال) — لا صور حقيقية
const gen = await browser.newPage();
const imgs = {};
for (const k of [...Array(12).keys()].map(i => 'p' + i).concat([...Array(6).keys()].map(i => 'w' + i))) {
  const wide = k.startsWith('w');
  imgs[k] = Buffer.from((await gen.evaluate(([k, wide]) => { const c = document.createElement('canvas'); c.width = wide ? 640 : 600; c.height = wide ? 360 : 800; const x = c.getContext('2d'); let h = 0; for (const ch of k) h = (h * 31 + ch.charCodeAt(0)) % 360;
    const g = x.createLinearGradient(0, 0, c.width, c.height); g.addColorStop(0, `hsl(${h},55%,38%)`); g.addColorStop(1, `hsl(${(h + 70) % 360},60%,18%)`); x.fillStyle = g; x.fillRect(0, 0, c.width, c.height);
    for (let i = 0; i < 9; i++) { x.fillStyle = `hsla(${(h + i * 40) % 360},70%,${55 + i % 3 * 8}%,.55)`; x.beginPath(); x.arc((i * 137) % c.width, (i * 211) % c.height, 40 + (i * 23) % 110, 0, 7); x.fill(); }
    return c.toDataURL('image/png').split(',')[1]; }, [k, wide])), 'base64');
}
await gen.close();

const errors = [];
async function shoot(vp, name, path, extra) {
  const [hp, hq] = path.split('?');
  const ctx = await browser.newContext({ viewport: vp, deviceScaleFactor: vp.width < 500 ? 2 : 1, locale: 'ar' });
  await ctx.route('https://img.test/**', r => { const k = r.request().url().split('/').pop().replace('.png', ''); r.fulfill({ status: 200, contentType: 'image/png', body: imgs[k] || imgs.p0 }); });
  const page = await ctx.newPage(); page.on('pageerror', e => errors.push(name + ': ' + e.message)); page.on('console', m => { if (m.type() === 'error') errors.push(name + ': ' + m.text()); });
  await page.goto(base + '?demo=1&qa=1' + (hq ? '&' + hq : '') + '#' + hp); await page.waitForTimeout(3500);
  if (extra) { await extra(page); await page.waitForTimeout(1200); }
  await page.screenshot({ path: join(out, name + '.png') });
  await ctx.close();
}
const phone = { width: 390, height: 844 }, desk = { width: 1440, height: 900 };
await shoot(phone, 'phone-01-home', '/');
await shoot(phone, 'phone-02-library', '/library');
await shoot(phone, 'phone-03-detail', '/p/demo-4');
await shoot(phone, 'phone-04b-detail-works', '/p/demo-4', async p => { await p.mouse.move(195, 600); for (let k = 0; k < 3; k++) { await p.mouse.wheel(0, 600); await p.waitForTimeout(200); } });
await shoot(phone, 'phone-04-detail-scroll', '/p/demo-4', async p => { await p.mouse.move(195, 600); await p.mouse.wheel(0, 700); });
await shoot(phone, 'phone-05-more', '/more');
await shoot(phone, 'phone-06-works', '/works');
await shoot(phone, 'phone-06b-works-scroll', '/works', async p => { await p.mouse.move(195, 600); await p.mouse.wheel(0, 500); });
for (const [t, n] of [[6, 'performers'], [7, 'studios'], [5, 'diary'], [1, 'watch']]) {
  await shoot(phone, 'phone-06c-works-' + n, '/works?wt=' + t, async p => { await p.mouse.move(195, 600); await p.mouse.wheel(0, 560); });
}
await shoot(phone, 'phone-06d-works-focus', '/works?wp=demo-4', async p => { await p.mouse.move(195, 600); await p.mouse.wheel(0, 560); });
await shoot(phone, 'phone-07-discover', '/discover');
await shoot(phone, 'phone-08-discover-more', '/discover', async p => { await p.mouse.move(195, 600); await p.mouse.wheel(0, 900); });
await shoot(desk, 'desk-05-discover', '/discover');
await shoot(phone, 'phone-08b-candidate', '/discover', async p => { await p.mouse.click(300, 430); await p.waitForTimeout(2500); });
await shoot(phone, 'phone-09-studio', '/studio');
// تبويبات الاستديو (صف الشرائح y≈152؛ الأخيرة تحتاج تمرير الصف أفقيًا)
for (const [x, n, sc] of [[222, 'all', 0], [110, 'liked', 0], [120, 'albums', 400], [12, 'performers', 400]]) {
  await shoot(phone, 'phone-09-studio-' + n, '/studio', async p => { if (sc) { await p.mouse.move(200, 152); await p.mouse.wheel(-sc, 0); await p.waitForTimeout(500); } await p.mouse.click(x, 152); });
}
await shoot(phone, 'phone-10-stats', '/stats');
await shoot(phone, 'phone-11-tools', '/tools');
await shoot(phone, 'phone-12-sync', '/sync');
await shoot(desk, 'desk-06-studio', '/studio');
await shoot(desk, 'desk-04-works', '/works');
await shoot(desk, 'desk-01-home', '/');
await shoot(desk, 'desk-02-library', '/library');
await shoot(desk, 'desk-03-detail', '/p/demo-1');
console.log(errors.length ? 'ERRORS:\n' + errors.slice(0, 10).join('\n') : 'no JS errors');
await browser.close(); server.close();
