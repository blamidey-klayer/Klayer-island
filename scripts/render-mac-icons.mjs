// Renders the macOS app icon and menu bar icon (NotchBuddy/Assets.xcassets) from
// the Klayer glyph in tools/klay-preview/src/glyph.ts, with headless Chromium.
//   node scripts/render-mac-icons.mjs   (needs playwright; set the import below to your install)
import { chromium } from '/opt/node22/lib/node_modules/playwright/index.mjs';
import { readFileSync, writeFileSync } from 'node:fs';
const ROOT = new URL('..', import.meta.url).pathname.replace(/\/$/, '');
const src = readFileSync(`${ROOT}/tools/klay-preview/src/glyph.ts`, 'utf8');
const a = src.slice(src.indexOf('GLYPH_SEGMENTS'));
const segs = JSON.parse(a.slice(a.indexOf('= [') + 2, a.indexOf('];') + 1).replace(/\],\s*\]$/, ']]'));

const b = await chromium.launch();
const p = await b.newPage();
await p.setContent('<html><body></body></html>');

async function render(size, mode) {
  const url = await p.evaluate(({ size, mode, segs }) => {
    const c = document.createElement('canvas'); c.width = c.height = size;
    const g = c.getContext('2d');
    const glyph = new Path2D();
    for (const s of segs) {
      if (s[0] === 'M') glyph.moveTo(s[1], s[2]);
      else if (s[0] === 'L') glyph.lineTo(s[1], s[2]);
      else if (s[0] === 'C') glyph.bezierCurveTo(s[1], s[2], s[3], s[4], s[5], s[6]);
      else glyph.closePath();
    }
    const GW = 797, GH = 512;
    if (mode === 'menubar') {
      const scale = size / 18; const margin = 1 * scale;
      const k = (size - 2 * margin) / GW;
      g.translate(margin, (size - GH * k) / 2); g.scale(k, k);
      g.fillStyle = '#000'; g.fill(glyph);
      return c.toDataURL('image/png');
    }
    // App icon: macOS Big Sur grid, tile = 824/1024 of the canvas.
    const tile = size * 824 / 1024, off = (size - tile) / 2;
    const tilePath = new Path2D();
    const n = 5, N = 256, h = tile / 2, cx = size / 2, cy = size / 2;
    for (let i = 0; i < N; i++) {
      const t = i / N * 2 * Math.PI, ct = Math.cos(t), st = Math.sin(t);
      const x = cx + h * Math.sign(ct) * Math.pow(Math.abs(ct), 2 / n);
      const y = cy + h * Math.sign(st) * Math.pow(Math.abs(st), 2 / n);
      i ? tilePath.lineTo(x, y) : tilePath.moveTo(x, y);
    }
    tilePath.closePath();
    // soft drop shadow, like the system icons
    if (size >= 64) {
      g.save(); g.shadowColor = 'rgba(0,0,0,0.30)'; g.shadowBlur = size * 0.02; g.shadowOffsetY = size * 0.008;
      g.fillStyle = '#10323B'; g.fill(tilePath); g.restore();
    }
    const grad = g.createLinearGradient(0, off, 0, off + tile);
    grad.addColorStop(0, '#1E4B57'); grad.addColorStop(1, '#10323B');
    g.fillStyle = grad; g.fill(tilePath);
    g.save(); g.clip(tilePath);
    // faint rising-sun glow behind the glyph
    const gw = tile * 0.62, k = gw / GW, gh = GH * k;
    const gx = (size - gw) / 2, gy = (size - gh) / 2;
    const sunY = gy + gh * 0.95;
    const rg = g.createRadialGradient(cx, sunY, 0, cx, sunY, tile * 0.55);
    rg.addColorStop(0, 'rgba(62,114,128,0.55)'); rg.addColorStop(0.55, 'rgba(62,114,128,0.18)'); rg.addColorStop(1, 'rgba(62,114,128,0)');
    g.fillStyle = rg; g.fillRect(0, 0, size, size);
    g.restore();
    g.save(); g.translate(gx, gy); g.scale(k, k); g.fillStyle = '#FFFFFF'; g.fill(glyph); g.restore();
    return c.toDataURL('image/png');
  }, { size, mode, segs });
  return Buffer.from(url.split(',')[1], 'base64');
}

const app = `${ROOT}/NotchBuddy/Assets.xcassets/AppIcon.appiconset`;
const contents = JSON.parse(readFileSync(`${app}/Contents.json`, 'utf8'));
for (const im of contents.images) {
  const px = parseInt(im.size) * parseInt(im.scale);
  writeFileSync(`${app}/${im.filename}`, await render(px, 'app'));
  console.log(im.filename, px);
}
const mb = `${ROOT}/NotchBuddy/Assets.xcassets/MenuBarIcon.imageset`;
for (const [f, px] of [['menubar.png', 18], ['menubar@2x.png', 36], ['menubar@3x.png', 54]]) {
  writeFileSync(`${mb}/${f}`, await render(px, 'menubar')); console.log(f, px);
}
await b.close();
