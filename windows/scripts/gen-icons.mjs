// Draws the Klayer Island app icon into the PNG/ICO set Tauri needs. No
// dependencies: the icons are rasterised here and encoded with node:zlib, so
// the app icon stays "drawn in code" like the character itself.
//
// Design (same as the macOS AppIcon): a rounded tile (superellipse, macOS grid:
// 824/1024 of the canvas, soft drop shadow) with a vertical teal gradient
// #1E4B57 -> #10323B, a faint teal-light glow rising behind the glyph, and the
// Klayer glyph in white, 62 % of the tile wide. The glyph is read from
// src/klay/glyph.ts (GLYPH_SEGMENTS) and drawn exactly as its path.
//
//   node scripts/gen-icons.mjs

import { deflateSync } from "node:zlib";
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const HERE = dirname(fileURLToPath(import.meta.url));
const OUT = join(HERE, "..", "src-tauri", "icons");

// ── Glyph ─────────────────────────────────────────────────────────────────────

/** GLYPH_SEGMENTS parsed out of src/klay/glyph.ts (the single source of the mark). */
function loadGlyph() {
  const src = readFileSync(join(HERE, "..", "src", "klay", "glyph.ts"), "utf8");
  const from = src.indexOf("GLYPH_SEGMENTS");
  const open = src.indexOf("= [", from) + 2;
  const close = src.indexOf("];", open) + 1;
  const json = src.slice(open, close).replace(/,\s*\]$/, "]");
  const segs = JSON.parse(json);
  const w = Number(/GLYPH_W\s*=\s*([\d.]+)/.exec(src)[1]);
  const h = Number(/GLYPH_H\s*=\s*([\d.]+)/.exec(src)[1]);
  return { segs, w, h };
}

const GLYPH = loadGlyph();

/** Flattens the glyph into closed polylines, mapped by (x, y) -> (ox + x*k, oy + y*k). */
function glyphPolys(ox, oy, k) {
  const polys = [];
  let cur = null;
  let px = 0;
  let py = 0;
  const steps = 32;
  for (const s of GLYPH.segs) {
    if (s[0] === "M") {
      cur = [[s[1], s[2]]];
      polys.push(cur);
      [px, py] = [s[1], s[2]];
    } else if (s[0] === "L") {
      cur.push([s[1], s[2]]);
      [px, py] = [s[1], s[2]];
    } else if (s[0] === "C") {
      const [, x1, y1, x2, y2, x3, y3] = s;
      for (let i = 1; i <= steps; i++) {
        const t = i / steps;
        const u = 1 - t;
        cur.push([
          u * u * u * px + 3 * u * u * t * x1 + 3 * u * t * t * x2 + t * t * t * x3,
          u * u * u * py + 3 * u * u * t * y1 + 3 * u * t * t * y2 + t * t * t * y3,
        ]);
      }
      [px, py] = [x3, y3];
    }
    // "Z": polygons are implicitly closed by the filler
  }
  return polys.map((p) => p.map(([x, y]) => [ox + x * k, oy + y * k]));
}

/** Superellipse |x|^n + |y|^n = 1 (n = 5): a macOS-like continuous-corner tile. */
function tilePoly(cx, cy, half, n = 5, N = 512) {
  const pts = [];
  for (let i = 0; i < N; i++) {
    const t = (i / N) * 2 * Math.PI;
    const c = Math.cos(t);
    const s = Math.sin(t);
    pts.push([
      cx + half * Math.sign(c) * Math.pow(Math.abs(c), 2 / n),
      cy + half * Math.sign(s) * Math.pow(Math.abs(s), 2 / n),
    ]);
  }
  return [pts];
}

// ── Rasteriser ────────────────────────────────────────────────────────────────

const SUB = 16; // sub-scanlines per pixel; horizontal coverage is exact

/** Non-zero fill of closed polygons into a size x size coverage mask (0..1). */
function fill(polys, size) {
  const cov = new Float32Array(size * size);
  const edges = [];
  for (const poly of polys) {
    for (let i = 0; i < poly.length; i++) {
      const [x0, y0] = poly[i];
      const [x1, y1] = poly[(i + 1) % poly.length];
      if (y0 === y1) continue;
      edges.push(y0 < y1 ? { ya: y0, yb: y1, x: x0, dx: (x1 - x0) / (y1 - y0), w: 1 }
                         : { ya: y1, yb: y0, x: x1, dx: (x0 - x1) / (y0 - y1), w: -1 });
    }
  }
  const addSpan = (row, xa, xb) => {
    xa = Math.max(0, xa);
    xb = Math.min(size, xb);
    if (xb <= xa) return;
    const o = row * size;
    const ia = Math.floor(xa);
    const ib = Math.floor(xb);
    if (ia === ib) {
      cov[o + ia] += (xb - xa) / SUB;
      return;
    }
    cov[o + ia] += (ia + 1 - xa) / SUB;
    for (let i = ia + 1; i < ib; i++) cov[o + i] += 1 / SUB;
    if (ib < size) cov[o + ib] += (xb - ib) / SUB;
  };
  for (let row = 0; row < size; row++) {
    for (let s = 0; s < SUB; s++) {
      const y = row + (s + 0.5) / SUB;
      const xs = [];
      for (const e of edges) {
        if (y >= e.ya && y < e.yb) xs.push([e.x + (y - e.ya) * e.dx, e.w]);
      }
      if (xs.length < 2) continue;
      xs.sort((a, b) => a[0] - b[0]);
      let wind = 0;
      for (let i = 0; i < xs.length - 1; i++) {
        wind += xs[i][1];
        if (wind !== 0) addSpan(row, xs[i][0], xs[i + 1][0]);
      }
    }
  }
  for (let i = 0; i < cov.length; i++) cov[i] = Math.min(1, cov[i]);
  return cov;
}

/** Approximate Gaussian blur (three box passes) of a mask, with a vertical offset. */
function shadowMask(mask, size, sigma, dy) {
  let a = new Float32Array(size * size);
  const shift = Math.round(dy);
  for (let y = 0; y < size; y++) {
    const sy = y - shift;
    if (sy < 0 || sy >= size) continue;
    a.set(mask.subarray(sy * size, sy * size + size), y * size);
  }
  const r = Math.max(1, Math.round((Math.sqrt(4 * sigma * sigma + 1) - 1) / 2)); // 3 passes ~ Gaussian(sigma)
  const box = (src, horizontal) => {
    const dst = new Float32Array(size * size);
    for (let j = 0; j < size; j++) {
      let acc = 0;
      const at = (i) => (horizontal ? src[j * size + i] : src[i * size + j]) || 0;
      for (let i = -r; i <= r; i++) acc += i >= 0 && i < size ? at(i) : 0;
      for (let i = 0; i < size; i++) {
        const idx = horizontal ? j * size + i : i * size + j;
        dst[idx] = acc / (2 * r + 1);
        const add = i + r + 1;
        const sub = i - r;
        if (add < size) acc += at(add);
        if (sub >= 0) acc -= at(sub);
      }
    }
    return dst;
  };
  for (let k = 0; k < 3; k++) a = box(box(a, true), false);
  return a;
}

// ── Klayer Island icon ────────────────────────────────────────────────────────

const TEAL_SURFACE = [0x1e, 0x4b, 0x57]; // #1E4B57
const TEAL = [0x10, 0x32, 0x3b]; // #10323B
const TEAL_LIGHT = [0x3e, 0x72, 0x80]; // #3E7280
const WHITE = [255, 255, 255];

function renderIcon(size) {
  const tile = (size * 824) / 1024;
  const off = (size - tile) / 2;
  const cx = size / 2;
  const tileCov = fill(tilePoly(cx, cx, tile / 2), size);

  const gw = tile * 0.62;
  const k = gw / GLYPH.w;
  const gh = GLYPH.h * k;
  const gx = (size - gw) / 2;
  const gy = (size - gh) / 2;
  const glyphCov = fill(glyphPolys(gx, gy, k), size);

  // rising-sun glow: radial, centred at the foot of the glyph
  const sunY = gy + gh * 0.95;
  const sunR = tile * 0.55;
  const glow = (d) => {
    const t = d / sunR;
    if (t >= 1) return 0;
    return t < 0.55 ? 0.55 + (0.18 - 0.55) * (t / 0.55) : 0.18 * (1 - (t - 0.55) / 0.45);
  };

  const shadow = size >= 64 ? shadowMask(tileCov, size, size * 0.01, size * 0.008) : null;

  const px = new Uint8Array(size * size * 4);
  for (let y = 0; y < size; y++) {
    const gt = Math.min(1, Math.max(0, (y + 0.5 - off) / tile));
    for (let x = 0; x < size; x++) {
      const i = y * size + x;
      // background (premultiplied-free "over" with straight alpha)
      let col = [0, 0, 0];
      let alpha = shadow ? shadow[i] * 0.3 : 0;
      const ta = tileCov[i];
      if (ta > 0) {
        let c = TEAL_SURFACE.map((v, n) => v + (TEAL[n] - v) * gt);
        const ga = glow(Math.hypot(x + 0.5 - cx, y + 0.5 - sunY));
        c = c.map((v, n) => v + (TEAL_LIGHT[n] - v) * ga);
        const ga2 = glyphCov[i];
        c = c.map((v, n) => v + (WHITE[n] - v) * ga2);
        const outA = ta + alpha * (1 - ta);
        col = c.map((v, n) => (v * ta + col[n] * alpha * (1 - ta)) / outA);
        alpha = outA;
      }
      const o = i * 4;
      px[o] = Math.round(col[0]);
      px[o + 1] = Math.round(col[1]);
      px[o + 2] = Math.round(col[2]);
      px[o + 3] = Math.round(Math.min(1, alpha) * 255);
    }
  }
  return px;
}

// ── PNG ───────────────────────────────────────────────────────────────────────

const CRC_TABLE = (() => {
  const t = new Uint32Array(256);
  for (let n = 0; n < 256; n++) {
    let c = n;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    t[n] = c >>> 0;
  }
  return t;
})();

function crc32(buf) {
  let c = 0xffffffff;
  for (const b of buf) c = CRC_TABLE[(c ^ b) & 0xff] ^ (c >>> 8);
  return (c ^ 0xffffffff) >>> 0;
}

function chunk(type, data) {
  const len = Buffer.alloc(4);
  len.writeUInt32BE(data.length);
  const body = Buffer.concat([Buffer.from(type, "ascii"), data]);
  const crc = Buffer.alloc(4);
  crc.writeUInt32BE(crc32(body));
  return Buffer.concat([len, body, crc]);
}

function encodePNG(size, rgba) {
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(size, 0);
  ihdr.writeUInt32BE(size, 4);
  ihdr[8] = 8; // bit depth
  ihdr[9] = 6; // RGBA
  const raw = Buffer.alloc(size * (size * 4 + 1));
  for (let y = 0; y < size; y++) {
    raw[y * (size * 4 + 1)] = 0; // filter: none
    Buffer.from(rgba.buffer, y * size * 4, size * 4).copy(raw, y * (size * 4 + 1) + 1);
  }
  return Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    chunk("IHDR", ihdr),
    chunk("IDAT", deflateSync(raw, { level: 9 })),
    chunk("IEND", Buffer.alloc(0)),
  ]);
}

// ── ICO (PNG-in-ICO, Vista and later) ─────────────────────────────────────────

function encodeICO(entries) {
  const header = Buffer.alloc(6);
  header.writeUInt16LE(0, 0);
  header.writeUInt16LE(1, 2);
  header.writeUInt16LE(entries.length, 4);
  const dir = Buffer.alloc(16 * entries.length);
  let offset = header.length + dir.length;
  entries.forEach((e, i) => {
    const o = i * 16;
    dir[o] = e.size >= 256 ? 0 : e.size;
    dir[o + 1] = e.size >= 256 ? 0 : e.size;
    dir[o + 2] = 0;
    dir[o + 3] = 0;
    dir.writeUInt16LE(1, o + 4);
    dir.writeUInt16LE(32, o + 6);
    dir.writeUInt32LE(e.png.length, o + 8);
    dir.writeUInt32LE(offset, o + 12);
    offset += e.png.length;
  });
  return Buffer.concat([header, dir, ...entries.map((e) => e.png)]);
}

// ── Go ────────────────────────────────────────────────────────────────────────

mkdirSync(OUT, { recursive: true });

const png = (size) => encodePNG(size, renderIcon(size));

const files = {
  "32x32.png": png(32),
  "128x128.png": png(128),
  "128x128@2x.png": png(256),
  "icon.png": png(512),
};
for (const [name, data] of Object.entries(files)) {
  writeFileSync(join(OUT, name), data);
  console.log(`${name} — ${data.length} bytes`);
}

const ico = encodeICO([16, 24, 32, 48, 64, 128, 256].map((size) => ({ size, png: png(size) })));
writeFileSync(join(OUT, "icon.ico"), ico);
console.log(`icon.ico — ${ico.length} bytes`);
