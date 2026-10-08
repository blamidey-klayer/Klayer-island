// Render bench: Klay's character sheet. Every state, the emotes, the hello
// wave, the mailbox and the mini Klays, side by side, drawn by src/engine.ts.
// Not part of the app. ?freeze=<seconds> stops every engine after that long,
// for screenshots; ?size=<px> changes the cell size.

import { BotEngine, drawKlayDrop, hexToRGB } from "./engine";
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
const box = cell("mailbox");
box.morph = 1;
box.slotH = 0.35;
box.slotHTarget = 0.35;

// The drop zone: Klay with wide eyes and both arms open, welcoming the file.
// First the pose in a sheet cell, then at real size in the island's drop card
// (620 × 124), with the mailbox that follows the cursor and the text, as the Mac
// app lays them out (UploadCanvasView, drag over the island).
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

drawerCell("dépôt", SIZE, SIZE, (x, t) => {
  drawKlayDrop(x, SIZE / 2, SIZE / 2, SIZE * 0.7, t);
});

// The card as the Mac lays it out: the drag-over canvas has a 124 pt card (figure 72 pt,
// text 13 pt under it); the Déposer tab gets the 98 pt content frame (figure 56 pt in a
// 64 pt canvas, 6 pt gap, ~16 pt of text, centred). Same dashed border, same mailbox at
// its resting place (140, 104 on the island).
const CARD_W = 620;
function dropCard(h: number, figH: number, figCY: number, textY: number, actorCY: number) {
  const actor = new BotEngine();
  actor.morph = 1;
  actor.slotH = 0.2;
  actor.slotHTarget = 0.2;
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
    const W = 99.4;
    x.save();
    x.translate(130 - W / 2, actorCY - W / 2);
    actor.update(0.016);
    actor.draw(x, W, W);
    x.restore();
    drawKlayDrop(x, CARD_W / 2, figCY, figH, t);
    x.fillStyle = "#D5D7DB";
    x.font = `500 13px system-ui, sans-serif`;
    x.textAlign = "center";
    x.textBaseline = "middle";
    x.fillText("Dépose ton fichier", CARD_W / 2, textY);
  };
}
// Drag-over canvas: figure 14 pt under the card's top edge, text 14 pt above the bottom.
drawerCell("dépôt, glisser (carte 620 × 124)", CARD_W, 124, dropCard(124, 72, 50, 102, 62), minis);
// Déposer tab: 98 pt card, stack of 86 pt centred: 6 pt of margin, canvas 64 + gap 6 + text 16.
drawerCell("dépôt, onglet Déposer (carte 620 × 98)", CARD_W, 98, dropCard(98, 56, 6 + 32, 6 + 64 + 6 + 8, 49), minis);

for (const [state, color] of [
  ["working", "#D97757"], ["approval", "#635BFF"], ["finished", "#24292F"], ["idle", "#10323B"], ["sleeping", "#3E7280"],
] as const) {
  const e = cell("", 60, minis);
  e.isMini = true;
  e.bodyColor = hexToRGB(color);
  e.setState(state, true);
}

const freeze = Number(new URLSearchParams(location.search).get("freeze") ?? "0");
const t0 = performance.now();
let last = performance.now();
function loop(now: number) {
  const dt = Math.min(0.05, (now - last) / 1000);
  last = now;
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
