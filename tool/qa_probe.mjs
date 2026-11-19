// أداة تشخيص: تعرض عناصر الإتاحة (الأدوار والأسماء) في صفحة من نسخة الويب التجريبية.
import { createRequire } from 'node:module';
import http from 'node:http';
import { readFileSync, existsSync } from 'node:fs';
import { join, dirname, extname } from 'node:path';
import { fileURLToPath } from 'node:url';
const root = join(dirname(fileURLToPath(import.meta.url)), '..'), web = join(root, 'build', 'web');
const require = createRequire(join(root, '..', 'favorites-app', 'package.json'));
const { chromium } = require('playwright-core');
const MIME = { '.html': 'text/html', '.js': 'text/javascript', '.mjs': 'text/javascript', '.wasm': 'application/wasm', '.json': 'application/json', '.png': 'image/png', '.ttf': 'font/ttf', '.otf': 'font/otf', '.svg': 'image/svg+xml' };
const server = http.createServer((q, r) => { let p = join(web, decodeURIComponent(q.url.split('?')[0].split('#')[0])); if (p.endsWith('\\') || p.endsWith('/') || !existsSync(p)) p = join(web, 'index.html'); r.writeHead(200, { 'Content-Type': MIME[extname(p)] || 'application/octet-stream' }); r.end(readFileSync(p)); });
await new Promise(r => server.listen(0, '127.0.0.1', r));
const browser = await chromium.launch({ channel: 'msedge', headless: true });
const page = await (await browser.newContext({ viewport: { width: 390, height: 844 }, locale: 'ar' })).newPage();
await page.goto('http://127.0.0.1:' + server.address().port + '/?qa=1&demo=1#' + (process.argv[2] || '/library')); await page.waitForTimeout(4000);
await page.locator('flt-semantics-placeholder').click({ force: true }).catch(() => {}); await page.waitForTimeout(1500);
const els = await page.evaluate(() => { const all = [...document.querySelectorAll('*')].filter(e => e.getAttribute && (e.getAttribute('role') || e.getAttribute('aria-label'))); return ['flt-semantics: ' + document.querySelectorAll('flt-semantics').length, ...all.map(e => e.tagName + ' ' + e.getAttribute('role') + ' | ' + (e.getAttribute('aria-label') || e.textContent || '').replace(/\s+/g, ' ').slice(0, 50))]; });
console.log(els.slice(0, 40).join('\n'));
await browser.close(); server.close();
