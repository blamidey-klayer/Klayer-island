// Render bench: Klay's character sheet. Every state, the emotes, the hello
// wave, the dance, the drop sequence's poses and the mini Klays, side by side, drawn by
// src/engine.ts. Not part of the app. ?freeze=<seconds> stops every engine after
// that long, for screenshots; ?size=<px> changes the cell size.
//
// Every Klay follows the pointer as on the Mac (BotCanvasView): lookX = tanh(dx / 260),
// lookY = −tanh(dy / 200) from the centre of its cell, and the pointer on a cell is a
// hover (tgEs 1.08 and a blink, like IslandWindowController.botHoverIn).
// ?live=<px> shows a single Klay of that size instead of the sheet (?state=<name>
// picks its state), to watch the gaze, the lean and the idle fidgets up close.

import { BotEngine, drawKlayDrop, hexToRGB } from "./engine";
import { frameDelta } from "./motion";
import type { BotEmoteName, BotStateName } from "./types";

const STATES: BotStateName[] = [
  "idle", "working", "thinking", "searching", "approval", "question",
  "error", "finished", "ratelimit", "sleeping", "dizzy",
];
const EMOTES: BotEmoteName[] = ["love", "surprised", "proud", "wink", "yawn", "happy"];

const grid = document.getElementById("grid")!;
const minis = document.getElementById("minis")!;
const engines: { e: BotEngine; c: HTMLCanvasElement; size: number }[] = [];
// Cells drawn by a function instead of an engine (the drop zone).
const drawers: { c: HTMLCanvasElement; w: number; h: number; draw: (x: CanvasRenderingContext2D, t: number) => void }[] = [];

const SIZE = Number(new URLSearchParams(location.search).get("size") ?? "180");
function cell(label: string, size = SIZE, host: HTMLElement = grid) {
  const d = document.createElement("div");
  d.className = "cell";
  const c = document.createElement("canvas");
  const dpr = 2;
  c.width = size * dpr;
  c.height = size * dpr;
  c.style.width = `${size}px`;
  c.style.height = `${size}px`;
  d.append(c, label);
  host.append(d);
  const e = new BotEngine();
  engines.push({ e, c, size });
  return e;
}

const params = new URLSearchParams(location.search);
const LIVE = Number(params.get("live") ?? "0");
if (LIVE) {
  // One Klay, big, alone: the gaze bench.
  grid.style.gridTemplateColumns = `${LIVE}px`;
  const e = cell("regard", LIVE);
  e.setState((params.get("state") ?? "idle") as BotStateName, true);
} else {
  buildSheet();
}

function buildSheet() {
  for (const s of STATES) cell(s).setState(s, true);
  for (const em of EMOTES) {
    const e = cell(`emote: ${em}`);
    const fire = () => e.triggerEmote(em, 2.4);
    setTimeout(fire, 300);
    setInterval(fire, 3200);
  }
  const wave = cell("hello wave");
  setTimeout(() => wave.greet(), 200);
  setInterval(() => wave.greet(), 2600);
  const dance = cell("dance");
  dance.setDancing(true);

  // The drop sequence (UploadCanvasView on the Mac): one Klay, the island's own. His arms open
  // and his eyes widen for the file, then he swallows it, squashed, eyes shut (the deepest
  // squash of the gulp, 0.07 s after the file went in, his arms coming down). Drawn at the
  // size of the island's Klay in a cell (diameter 0.6 × the cell).
  function drawerCell(label: string, w: number, h: number, draw: (x: CanvasRenderingContext2D, t: number) => void, host: HTMLElement = grid) {
    const d = document.createElement("div");
    d.className = "cell";
    const c = document.createElement("canvas");
    c.width = w * 2;
    c.height = h * 2;
    c.style.width = `${w}px`;
    c.style.height = `${h}px`;
    d.append(c, label);
    host.append(d);
    drawers.push({ c, w, h, draw });
  }

  drawerCell("dépôt : bras ouverts", SIZE, SIZE, (x, t) => {
    drawKlayDrop(x, SIZE / 2, SIZE / 2, SIZE * 0.6, t, { arms: 1, eye: "wide", gaze: { yaw: 0.3, pitch: 0.4 } });
  });
  drawerCell("dépôt : avale", SIZE, SIZE, (x, t) => {
    drawKlayDrop(x, SIZE / 2, SIZE / 2, SIZE * 0.6, t, { arms: 0.41, eye: "closed", sx: 1.14, sy: 0.82 });
  });

  // The drop card as the Mac lays it out, Klay in its middle (island 320, 92; diameter 62),
  // « Dépose ton fichier » under him (island y 133). The Déposer tab (98 pt card, island
  // y 55…153) shows the island's own Klay, at rest; when a file comes, the drag-over canvas
  // (124 pt card, island y 42…166) takes over at the same spot and opens his arms.
  const CARD_W = 620;
  const KLAY = { x: 320 - 10, y: 92, d: 62 };
  function dropCard(h: number, top: number, draw: (x: CanvasRenderingContext2D, cy: number, t: number) => void) {
    return (x: CanvasRenderingContext2D, t: number) => {
      x.fillStyle = "#0D0E10";
      x.beginPath();
      x.roundRect(0, 0, CARD_W, h, 20);
      x.fill();
      x.strokeStyle = "rgba(255,255,255,0.14)";
      x.lineWidth = 1.5;
      x.setLineDash([6, 5]);
      x.beginPath();
      x.roundRect(0.75, 0.75, CARD_W - 1.5, h - 1.5, 19.5);
      x.stroke();
      x.setLineDash([]);
      draw(x, KLAY.y - top, t);
      x.fillStyle = "#D5D7DB";
      x.font = `500 13px system-ui, sans-serif`;
      x.textAlign = "center";
      x.textBaseline = "middle";
      x.fillText("Dépose ton fichier", CARD_W / 2, 133 - top);
    };
  }
  // Déposer tab: the island's Klay (BotEngine), idle, in a canvas d / 0.6 wide as BotPlacement draws him.
  const resting = new BotEngine();
  const W = KLAY.d / 0.6;
  drawerCell("dépôt, onglet Déposer (carte 620 × 98)", CARD_W, 98, dropCard(98, 55, (x, cy) => {
    x.save();
    x.translate(KLAY.x - W / 2, cy - W / 2);
    resting.update(0.016);
    resting.draw(x, W, W);
    x.restore();
  }), minis);
  // A file over the island: the same Klay, arms open, eyes on the file.
  drawerCell("dépôt, glisser (carte 620 × 124)", CARD_W, 124, dropCard(124, 42, (x, cy, t) => {
    drawKlayDrop(x, KLAY.x, cy, KLAY.d, t, { arms: 1, eye: "wide", gaze: { yaw: 0.35, pitch: 0.3 } });
  }), minis);

  for (const [state, color] of [
    ["working", "#D97757"], ["approval", "#635BFF"], ["finished", "#24292F"], ["idle", "#10323B"], ["sleeping", "#3E7280"],
  ] as const) {
    const e = cell("", 60, minis);
    e.isMini = true;
    e.bodyColor = hexToRGB(color);
    e.setState(state, true);
  }
}

// For scripted checks (Playwright): the engines, in the order of the cells.
(window as unknown as { klay: BotEngine[] }).klay = engines.map(({ e }) => e);

// The pointer drives every Klay's gaze, as on the Mac; on a cell, it is a hover.
let pointer: { x: number; y: number } | null = null;
addEventListener("pointermove", (ev) => { pointer = { x: ev.clientX, y: ev.clientY }; });
const hovering = new Set<BotEngine>();
function followPointer() {
  if (!pointer) return;
  for (const { e, c } of engines) {
    const r = c.getBoundingClientRect();
    const dx = pointer.x - (r.left + r.width / 2);
    const dy = pointer.y - (r.top + r.height / 2);
    e.lookX = Math.tanh(dx / 260);
    e.lookY = -Math.tanh(dy / 200);
    const over = Math.hypot(dx, dy) <= r.width / 2;
    if (over && !hovering.has(e)) {
      hovering.add(e);
      e.blink();
      e.tgEs = 1.08;
    } else if (!over && hovering.has(e)) {
      hovering.delete(e);
      e.tgEs = 1;
    }
  }
}

const freeze = Number(params.get("freeze") ?? "0");
const t0 = performance.now();
let last = performance.now();
function loop(now: number) {
  const dt = frameDelta(now / 1000, last / 1000);
  last = now;
  followPointer();
  for (const { e, c, size } of engines) {
    e.update(dt);
    const x = c.getContext("2d")!;
    x.setTransform(2, 0, 0, 2, 0, 0);
    x.clearRect(0, 0, size, size);
    e.draw(x, size, size);
  }
  for (const { c, w, h, draw } of drawers) {
    const x = c.getContext("2d")!;
    x.setTransform(2, 0, 0, 2, 0, 0);
    x.clearRect(0, 0, w, h);
    draw(x, (now - t0) / 1000);
  }
  if (!freeze || now - t0 < freeze * 1000) requestAnimationFrame(loop);
}
requestAnimationFrame(loop);
