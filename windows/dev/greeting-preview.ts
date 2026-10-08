// Dev harness: plays the launch greeting in a plain browser, on a loop.
// Not part of the app bundle.

import { GREETING_H, GREETING_W, Greeting } from "../src/klay/greeting";

const c = document.getElementById("c") as HTMLCanvasElement;
const dpr = 2;
c.width = GREETING_W * dpr;
c.height = GREETING_H * dpr;
c.style.width = `${GREETING_W}px`;
c.style.height = `${GREETING_H}px`;
const ctx = c.getContext("2d")!;
ctx.scale(dpr, dpr);

const g = new Greeting();
g.start();
setInterval(() => g.start(), 6000);
function loop() {
  g.draw(ctx);
  requestAnimationFrame(loop);
}
requestAnimationFrame(loop);
