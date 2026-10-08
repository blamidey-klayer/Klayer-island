// Dev harness: Klay's character sheet — every state, the emotes, the hello
// wave, the mailbox and the mini Klays, side by side. Not part of the app bundle.
// ?freeze=<seconds> stops every engine after that long, for screenshots.

import { BotEngine, hexToRGB } from "../src/klay/engine";
import type { BotEmoteName, BotStateName } from "../src/core/layout";

const STATES: BotStateName[] = [
  "idle", "working", "thinking", "searching", "approval", "question",
  "error", "finished", "ratelimit", "sleeping", "dizzy",
];
const EMOTES: BotEmoteName[] = ["love", "surprised", "proud", "wink", "yawn", "happy"];

const grid = document.getElementById("grid")!;
const minis = document.getElementById("minis")!;
const engines: { e: BotEngine; c: HTMLCanvasElement; size: number }[] = [];

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
  if (!freeze || now - t0 < freeze * 1000) requestAnimationFrame(loop);
}
requestAnimationFrame(loop);
