// يرسم الشعار (assets/brand/logo.svg) إلى أيقونات PNG لكل المنصات عبر متصفح Edge/Chrome المثبّت (playwright-core من مشروع favorites-app).
// الاستخدام: node tool/render_icons.mjs
import { createRequire } from 'node:module';
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const require = createRequire(join(root, '..', 'favorites-app', 'package.json'));
const { chromium } = require('playwright-core');
const svg = readFileSync(join(root, 'assets', 'brand', 'logo.svg'), 'utf8');
// الأمامية لأيقونة أندرويد التكيفية: بلا خلفية، داخل المنطقة الآمنة (66%)
const fg = svg.replace(/<rect[^>]*\/>/, '').replace('viewBox="0 0 1024 1024"', 'viewBox="-264 -264 1552 1552"');

let browser; for (const channel of ['msedge', 'chrome']) { try { browser = await chromium.launch({ channel, headless: true }); break; } catch {} }
const page = await browser.newPage();
async function png(markup, size, out, bg = 'transparent') {
  await page.setViewportSize({ width: size, height: size });
  await page.setContent(`<html><body style="margin:0;background:${bg}">${markup.replace('<svg ', `<svg width="${size}" height="${size}" `)}</body></html>`);
  mkdirSync(dirname(out), { recursive: true });
  writeFileSync(out, await page.screenshot({ omitBackground: bg === 'transparent', clip: { x: 0, y: 0, width: size, height: size } }));
}
const A = p => join(root, p);
await png(svg, 1024, A('assets/brand/icon-1024.png'));
await png(fg, 1024, A('assets/brand/icon-foreground.png'));
// أندرويد (mipmap)
for (const [d, s] of [['mdpi', 48], ['hdpi', 72], ['xhdpi', 96], ['xxhdpi', 144], ['xxxhdpi', 192]]) await png(svg, s, A(`android/app/src/main/res/mipmap-${d}/ic_launcher.png`));
// بانر التلفاز 320x180
await page.setViewportSize({ width: 320, height: 180 });
await page.setContent(`<html><body style="margin:0;width:320px;height:180px;display:flex;align-items:center;justify-content:center;gap:14px;background:radial-gradient(circle at 30% 30%,#34172F,#09070D);font-family:'Segoe UI',sans-serif">${svg.replace('<svg ', '<svg width="96" height="96" ')}<b style="color:#F6DDA6;font-size:34px;letter-spacing:.5px">Favorites</b></body></html>`);
mkdirSync(A('android/app/src/main/res/drawable'), { recursive: true });
writeFileSync(A('android/app/src/main/res/drawable/banner.png'), await page.screenshot({ clip: { x: 0, y: 0, width: 320, height: 180 } }));
// الويب
for (const s of [192, 512]) await png(svg, s, A(`web/icons/Icon-${s}.png`));
for (const s of [192, 512]) await png(svg, s, A(`web/icons/Icon-maskable-${s}.png`));
await png(svg, 32, A('web/favicon.png'));
// iOS: كل الأحجام من 1024 عبر قائمة الأيقونات الموجودة
const iosDir = A('ios/Runner/Assets.xcassets/AppIcon.appiconset');
const contents = JSON.parse(readFileSync(join(iosDir, 'Contents.json'), 'utf8'));
for (const im of contents.images) { if (!im.filename) continue; const px = Math.round(parseFloat(im.size) * parseInt(im.scale)); await png(svg, px, join(iosDir, im.filename), '#09070D'); }
await browser.close();
console.log('icons rendered');
