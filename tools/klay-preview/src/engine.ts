// Klay — the Klayer Island character, drawn in Canvas 2D.
//
// The body is the Klayer glyph itself (glyph.ts), drawn white on the dark
// island, never reshaped. Klay's character comes from what is added around it:
// two eyes on the solid hub under the rays, noodle arms with round hands, two
// little legs under the tip, and a glow of the current state's colour behind
// the rays, like the sun the mark already draws. The state machine, tweens and
// particles keep the engine's original timings (MIT code from Coucou); the
// drawing below is Klay's own.

import { Ease, lerp, type EaseFn } from "./anim";
import { Sound } from "./sound";
import type { BotEmoteName, BotStateName } from "./types";
import { GLYPH_W, glyphPath } from "./glyph";

// ── Types ─────────────────────────────────────────────────────────────────────

export type EyeShape =
  | "pill" | "wide" | "dot" | "line" | "flat" | "happy" | "closed"
  | "spiral" | "heart" | "star" | "tired" | "wink" | "cup";

export type BadgeKind = "dots" | "bang" | "question" | "dot";

export interface Badge {
  kind: BadgeKind;
  color: RGB;
}

export type RGB = readonly [number, number, number]; // components 0…1

export type TweenKey = readonly [target: number, durationMs: number, ease: EaseFn];

interface Tween {
  prop: PropKey;
  keys: TweenKey[];
  index: number;
  from: number;
  startMs: number;
  onComplete?: () => void;
}

type PropKey =
  | "yaw" | "pitch" | "roll" | "tilt" | "open" | "sx" | "sy"
  | "oy" | "ox" | "tint" | "morph" | "hands" | "blush" | "es" | "badgeS";

interface BotStateCfg {
  color: RGB;
  tint: number;
  eye: EyeShape;
  badge: Badge | null;
  bounces: boolean;
  scans: boolean;
  breathes: boolean;
  zz: boolean;
  sweat: boolean;
  look: readonly [number, number] | null;
  tilt: number;
}

interface Particle {
  type: "heart" | "star" | "spark" | "sweat" | "z";
  x: number; y: number; vx: number; vy: number;
  age: number; life: number; rot: number; size: number;
}

/** A point in Klay's own frame: glyph units, origin on the hub, y down. */
interface P { x: number; y: number }

// ── Geometry (glyph units: the glyph is 797 × 512) ───────────────────────────

/** Hub centre in the glyph — the solid part under the rays, where the face sits. */
const HUB_X = 398.5;
const HUB_Y = 400;
/** Eyes, relative to the hub centre: two round eyes, white with a teal-deep rim. */
const EYE_DX = 56;
const EYE_DY = -6;
const EYE_R = 52;
const EYE_RIM = 9;
/** The pupil (or whatever shape the eye takes) inside each eye. */
const EYE_W = 33;
const EYE_H = 52;
/** Shoulders and hips, relative to the hub centre. */
const SHOULDER: P = { x: 82, y: 50 };
const HIP: P = { x: 17, y: 104 };
/** Where the hands and feet rest. */
const HAND_REST: P = { x: 168, y: 150 };
const FOOT_REST: P = { x: 36, y: 212 };
const LIMB_W = 26;
const LIMB_RIM = 7;
const HAND_R = 26;
const FOOT_RX = 32;
const FOOT_RY = 15;
/** Top and bottom of the whole character (glyph top, soles), relative to the hub. */
const TOP = -HUB_Y;
const BOTTOM = FOOT_REST.y + FOOT_RY;
/** Vertical offset that centres the character's full height on the canvas centre. */
const CENTER_Y = (TOP + BOTTOM) / 2;
/** Klay's figure, for whoever draws him outside the engine (the launch greeting). */
export const KLAY_FIGURE = {
  top: TOP,
  bottom: BOTTOM,
  centerY: CENTER_Y,
  halfWidth: 398.5,
  handRest: HAND_REST,
  footRest: FOOT_REST,
} as const;
/** Fraction of the canvas width the glyph spans. */
const GLYPH_SPAN = 0.62;
/** Below this glyph width (px) the limbs would be sub-pixel noise: they are left out. */
const LIMBS_MIN_PX = 30;

// ── Colours ───────────────────────────────────────────────────────────────────

/** Glyph white on the dark island (the brand's glyph-white). */
const BODY = "#FFFFFF";
/** Eyes: Klayer teal-deep. */
export const INK = "rgb(7,27,32)"; // #071B20
const MINI_INK = "rgb(7,27,32)";

const C = {
  idle: [0.243, 0.447, 0.502] as RGB, // Klayer teal-light #3E7280
  working: [0.231, 0.62, 1] as RGB,
  thinking: [0.545, 0.361, 0.965] as RGB,
  searching: [0.388, 0.396, 0.949] as RGB,
  approval: [0.961, 0.647, 0.141] as RGB,
  question: [0.133, 0.827, 0.933] as RGB,
  error: [0.871, 0.384, 0.231] as RGB, // brick, brightened for the dark island
  finished: [0.204, 0.831, 0.6] as RGB,
  ratelimit: [0.984, 0.573, 0.235] as RGB,
  sleeping: [0.58, 0.635, 0.722] as RGB,
  dizzy: [0.957, 0.447, 0.714] as RGB,
};

const base = {
  bounces: false, scans: false, breathes: false, zz: false, sweat: false,
  look: null, tilt: 0,
};

export const BOT_STATES: Record<BotStateName, BotStateCfg> = {
  idle: { ...base, color: C.idle, tint: 0.35, eye: "pill", badge: null },
  working: { ...base, color: C.working, tint: 0.72, eye: "pill", badge: { kind: "dots", color: C.working } },
  thinking: { ...base, color: C.thinking, tint: 0.72, eye: "pill", badge: { kind: "dots", color: C.thinking }, look: [0.55, -0.55] },
  searching: { ...base, color: C.searching, tint: 0.72, eye: "pill", badge: { kind: "dots", color: C.searching }, scans: true },
  approval: { ...base, color: C.approval, tint: 0.78, eye: "wide", badge: { kind: "bang", color: C.approval }, bounces: true },
  question: { ...base, color: C.question, tint: 0.75, eye: "pill", badge: { kind: "question", color: C.question }, tilt: 0.12 },
  error: { ...base, color: C.error, tint: 0.78, eye: "flat", badge: { kind: "dot", color: C.error } },
  finished: { ...base, color: C.finished, tint: 0.5, eye: "happy", badge: { kind: "dot", color: C.finished } },
  ratelimit: { ...base, color: C.ratelimit, tint: 0.72, eye: "tired", badge: { kind: "dot", color: C.ratelimit }, sweat: true },
  sleeping: { ...base, color: C.sleeping, tint: 0.25, eye: "closed", badge: null, breathes: true, zz: true },
  dizzy: { ...base, color: C.dizzy, tint: 0.7, eye: "spiral", badge: null },
};

/** State → sound, as in BotStateCfg.sound. */
export const STATE_SOUND: Partial<Record<BotStateName, string>> = {
  working: "work", thinking: "think", searching: "search", approval: "approval",
  question: "question", error: "error", finished: "finish", ratelimit: "rate",
  sleeping: "sleep", dizzy: "dizzy",
};

const EMOTE_EYE: Record<BotEmoteName, EyeShape> = {
  love: "heart", surprised: "dot", proud: "star", wink: "wink",
  yawn: "tired", happy: "happy", annoyed: "line",
};

// ── Small helpers ─────────────────────────────────────────────────────────────

const now = () => performance.now() / 1000;

export function hexToRGB(hex: string): RGB {
  const h = hex.replace("#", "");
  const v = parseInt(h, 16);
  return [((v >> 16) & 255) / 255, ((v >> 8) & 255) / 255, (v & 255) / 255];
}

const rgba = (c: RGB, a = 1) =>
  `rgba(${Math.round(c[0] * 255)},${Math.round(c[1] * 255)},${Math.round(c[2] * 255)},${a})`;

const mix3 = (a: RGB, b: RGB, t: number): RGB => [
  lerp(a[0], b[0], t), lerp(a[1], b[1], t), lerp(a[2], b[2], t),
];

function roundRectPath(x: CanvasRenderingContext2D, X: number, Y: number, W: number, H: number, R: number) {
  const r = Math.max(0, Math.min(R, W / 2, H / 2));
  x.beginPath();
  x.moveTo(X + r, Y);
  x.arcTo(X + W, Y, X + W, Y + H, r);
  x.arcTo(X + W, Y + H, X, Y + H, r);
  x.arcTo(X, Y + H, X, Y, r);
  x.arcTo(X, Y, X + W, Y, r);
  x.closePath();
}

function heartPath(x: CanvasRenderingContext2D, s: number) {
  x.beginPath();
  x.moveTo(0, s * 0.38);
  x.bezierCurveTo(-s * 1.05, -s * 0.15, -s * 0.5, -s * 0.95, 0, -s * 0.38);
  x.bezierCurveTo(s * 0.5, -s * 0.95, s * 1.05, -s * 0.15, 0, s * 0.38);
  x.closePath();
}

function starPath(x: CanvasRenderingContext2D, ro: number, ri: number) {
  x.beginPath();
  for (let i = 0; i < 10; i++) {
    const r = i % 2 ? ri : ro;
    const a = -Math.PI / 2 + (i * Math.PI) / 5;
    x.lineTo(Math.cos(a) * r, Math.sin(a) * r);
  }
  x.closePath();
}

const FONT = `system-ui, "Segoe UI Variable Text", "Segoe UI", sans-serif`;

/** Where the hands and feet want to be for a state, at time `t` (seconds). */
export function limbTargets(
  state: BotStateName, t: number, waving: number,
): { lh: P; rh: P; lf: P; rf: P } {
  const rest = (sd: number, dy = 0): P => ({ x: sd * HAND_REST.x, y: HAND_REST.y + dy + Math.sin(t * 1.8 + sd) * 3 });
  let lh = rest(-1);
  let rh = rest(1);
  let lf: P = { x: -FOOT_REST.x, y: FOOT_REST.y };
  let rf: P = { x: FOOT_REST.x, y: FOOT_REST.y };

  switch (state) {
    case "working": {
      // Busy hands, typing in turn, and a little march in place.
      const k = Math.sin(t * 9);
      lh = { x: -132, y: 104 + k * 14 };
      rh = { x: 132, y: 104 - k * 14 };
      lf = { x: -FOOT_REST.x, y: FOOT_REST.y - Math.max(0, Math.sin(t * 6)) * 10 };
      rf = { x: FOOT_REST.x, y: FOOT_REST.y - Math.max(0, -Math.sin(t * 6)) * 10 };
      break;
    }
    case "thinking":
      // Hand on the chin.
      rh = { x: 52 + Math.sin(t * 2) * 3, y: 92 };
      break;
    case "searching":
      // A hand over the eyes, scanning the horizon.
      rh = { x: 78, y: -34 + Math.sin(t * 2.6) * 4 };
      break;
    case "approval": {
      // Both arms up, waving for attention.
      const k = Math.sin(t * 11);
      lh = { x: -196, y: -66 + k * 14 };
      rh = { x: 196, y: -66 - k * 14 };
      break;
    }
    case "question":
      // Scratching the side of the head.
      rh = { x: 150, y: -40 + Math.sin(t * 14) * 6 };
      break;
    case "error":
      lh = { x: -112, y: 150 };
      rh = { x: 112, y: 150 };
      break;
    case "finished":
      // Arms up in a V.
      lh = { x: -214, y: -96 + Math.sin(t * 4) * 5 };
      rh = { x: 214, y: -96 - Math.sin(t * 4) * 5 };
      break;
    case "ratelimit":
      lh = { x: -118, y: 158 };
      rh = { x: 118, y: 158 };
      break;
    case "sleeping":
      lh = { x: -122, y: 146 };
      rh = { x: 122, y: 146 };
      break;
    case "dizzy":
      lh = { x: -170 + Math.sin(t * 7) * 30, y: 40 + Math.cos(t * 9) * 50 };
      rh = { x: 170 + Math.sin(t * 8 + 1) * 30, y: 40 + Math.cos(t * 7 + 2) * 50 };
      lf = { x: -FOOT_REST.x - Math.max(0, Math.sin(t * 5)) * 12, y: FOOT_REST.y };
      rf = { x: FOOT_REST.x + Math.max(0, -Math.sin(t * 5)) * 12, y: FOOT_REST.y };
      break;
    default:
      break;
  }

  if (waving > 0) {
    // The hello: right hand up, waving fast.
    const wave = { x: 206 + Math.cos(13 * t) * 16, y: -40 - Math.sin(13 * t) * 26 };
    rh = { x: lerp(rh.x, wave.x, waving), y: lerp(rh.y, wave.y, waving) };
  }
  return { lh, rh, lf, rf };
}

/** The glyph, white, placed so that its hub sits on Klay's origin. */
export function drawKlayGlyph(x: CanvasRenderingContext2D) {
  x.save();
  x.translate(-HUB_X, -HUB_Y);
  x.fillStyle = BODY;
  x.fill(glyphPath());
  x.restore();
}

/** Legs with little oval feet, behind the glyph. In Klay's frame. */
export function drawKlayLegs(x: CanvasRenderingContext2D, lf: P, rf: P) {
  x.save();
  x.strokeStyle = BODY;
  x.fillStyle = BODY;
  x.lineWidth = LIMB_W;
  x.lineCap = "round";
  for (const [sd, foot] of [[-1, lf], [1, rf]] as const) {
    const hip = { x: sd * HIP.x, y: HIP.y };
    const knee = { x: (hip.x + foot.x) / 2 + sd * 8, y: (hip.y + foot.y) / 2 };
    x.beginPath();
    x.moveTo(hip.x, hip.y);
    x.quadraticCurveTo(knee.x, knee.y, foot.x, foot.y - FOOT_RY * 0.4);
    x.stroke();
    x.beginPath();
    x.ellipse(foot.x + sd * 8, foot.y, FOOT_RX, FOOT_RY, 0, 0, Math.PI * 2);
    x.fill();
  }
  x.restore();
}

/**
 * Noodle arms with round hands, in front of the glyph and rimmed in ink like the
 * eyes, so a raised hand still reads over the white rays. A white disc over each
 * shoulder hides where the rim starts, inside the hub. In Klay's frame.
 */
export function drawKlayArms(x: CanvasRenderingContext2D, lh: P, rh: P, ink: string = INK) {
  x.save();
  x.lineCap = "round";
  x.lineJoin = "round";
  for (const [sd, hand] of [[-1, lh], [1, rh]] as const) {
    const sh = { x: sd * SHOULDER.x, y: SHOULDER.y };
    // The elbow bows outwards and down, which keeps the noodle look in every pose.
    const elbow = {
      x: (sh.x + hand.x) / 2 + sd * 26,
      y: (sh.y + hand.y) / 2 + 20,
    };
    const arm = new Path2D();
    arm.moveTo(sh.x, sh.y);
    arm.quadraticCurveTo(elbow.x, elbow.y, hand.x, hand.y);
    x.strokeStyle = ink;
    x.lineWidth = LIMB_W + 2 * LIMB_RIM;
    x.stroke(arm);
    x.fillStyle = ink;
    x.beginPath();
    x.arc(hand.x, hand.y, HAND_R + LIMB_RIM, 0, Math.PI * 2);
    x.fill();
    x.strokeStyle = BODY;
    x.lineWidth = LIMB_W;
    x.stroke(arm);
    x.fillStyle = BODY;
    x.beginPath();
    x.arc(hand.x, hand.y, HAND_R, 0, Math.PI * 2);
    x.fill();
    x.beginPath();
    x.arc(sh.x, sh.y, LIMB_W / 2 + LIMB_RIM + 1, 0, Math.PI * 2);
    x.fill();
  }
  x.restore();
}

/** Pink cheeks under the eyes, `b` 0…1. In Klay's frame. */
export function drawKlayBlush(x: CanvasRenderingContext2D, b: number) {
  if (b <= 0.01) return;
  x.save();
  x.fillStyle = `rgba(255,120,150,${0.55 * b})`;
  for (const sd of [-1, 1]) {
    x.beginPath();
    x.ellipse(sd * 74, 44, 20, 11, 0, 0, Math.PI * 2);
    x.fill();
  }
  x.restore();
}

export interface EyeLook {
shape: EyeShape;
/** 1 = open, towards 0 while blinking. */
open: number;
/** Eye scale (surprised = bigger). */
es: number;
/** Where Klay looks, −1…1 each way. */
yaw: number;
pitch: number;
ink: string;
}

/**
 * Eyes, in Klay's frame (glyph units) around (cxu, cyu): two round white eyes
 * with a teal-deep rim. They slide a little towards where Klay looks, the
 * pupils twice as far.
 */
export function drawKlayEyes(x: CanvasRenderingContext2D, e: EyeLook, mult: number, cxu: number, cyu: number) {
const { shape, ink } = e;
  x.save();
  x.fillStyle = ink;
  x.strokeStyle = ink;
  const lookX = Math.max(-1, Math.min(1, e.yaw)) * 14;
  const lookY = Math.max(-1, Math.min(1, e.pitch)) * 12;
  const ew = EYE_W * e.es * mult;
  const eh = EYE_H * e.es * mult;
  const er = EYE_R * e.es * mult;
  const dx = EYE_DX * mult;
  for (const sd of [-1, 1]) {
    x.save();
    // The eye itself follows the look a little; the pupil, twice as far.
    x.translate(cxu + sd * dx + lookX * 0.4 * mult, cyu + EYE_DY * mult + lookY * 0.4 * mult);
    x.beginPath();
    x.arc(0, 0, er, 0, Math.PI * 2);
    x.fillStyle = "#FFFFFF";
    x.fill();
    x.lineWidth = EYE_RIM * mult;
    x.strokeStyle = ink;
    x.stroke();
    x.translate(lookX * 0.8 * mult, lookY * 0.8 * mult);
    x.fillStyle = ink;
    drawEyeShape(x, shape, ew, eh, sd, e.open);
    x.restore();
  }
  x.restore();
}

function drawEyeShape(
x: CanvasRenderingContext2D, shape: EyeShape,
w: number, h: number, sd: number, open: number,
) {
  const t = now();
  switch (shape) {
    case "wide":
      drawEyeShape(x, "pill", w * 1.16, h * 1.12, sd, open);
      break;
    case "pill": {
      const hh = Math.max(h * open, w * 0.3);
      roundRectPath(x, -w / 2, -hh / 2, w, hh, Math.min(w / 2, hh / 2));
      x.fill();
      break;
    }
    case "dot":
      x.beginPath();
      x.arc(0, 0, w * 0.5, 0, Math.PI * 2);
      x.fill();
      break;
    case "line":
      x.rotate(-sd * 0.25);
      roundRectPath(x, -w * 0.8, -w * 0.22, w * 1.6, w * 0.44, w * 0.22);
      x.fill();
      break;
    case "flat":
      roundRectPath(x, -w * 0.75, -w * 0.21, w * 1.5, w * 0.42, w * 0.21);
      x.fill();
      break;
    case "happy":
      x.lineWidth = w * 0.42;
      x.lineCap = "round";
      x.beginPath();
      x.arc(0, h * 0.2, w * 0.7, Math.PI * 1.15, Math.PI * 1.85);
      x.stroke();
      break;
    case "closed":
      x.lineWidth = w * 0.34;
      x.lineCap = "round";
      x.beginPath();
      x.arc(0, -h * 0.12, w * 0.68, Math.PI * 0.18, Math.PI * 0.82);
      x.stroke();
      break;
    case "spiral": {
      x.lineWidth = w * 0.2;
      x.lineCap = "round";
      x.beginPath();
      for (let a = 0; a < 4.4 * Math.PI; a += 0.2) {
        const r = w * 0.06 + a * w * 0.055;
        const aa = a + t * 9 * sd;
        const px = Math.cos(aa) * r;
        const py = Math.sin(aa) * r;
        if (a === 0) x.moveTo(px, py);
        else x.lineTo(px, py);
      }
      x.stroke();
      break;
    }
    case "heart":
      x.fillStyle = "#E8445E";
      heartPath(x, w * 1.15);
      x.fill();
      x.fillStyle = INK;
      break;
    case "star":
      x.fillStyle = "#E3A21A";
      x.rotate(t * 1.5 * sd);
      starPath(x, w * 1.0, w * 0.44);
      x.fill();
      x.fillStyle = INK;
      break;
    case "tired":
      roundRectPath(x, -w / 2, -h * 0.02, w, h * 0.38, w / 2);
      x.fill();
      roundRectPath(x, -w * 0.62, -h * 0.1, w * 1.24, w * 0.22, w * 0.11);
      x.fill();
      break;
    case "wink":
      if (sd < 0) {
        const hh = Math.max(h * open, w * 0.3);
        roundRectPath(x, -w / 2, -hh / 2, w, hh, Math.min(w / 2, hh / 2));
        x.fill();
      } else {
        x.lineWidth = w * 0.42;
        x.lineCap = "round";
        x.beginPath();
        x.arc(0, h * 0.2, w * 0.7, Math.PI * 1.15, Math.PI * 1.85);
        x.stroke();
      }
      break;
    case "cup": {
      // Flat top, rounded bottom corners (U shape) — used while the box is open
      const hh = Math.max(h * open, w * 0.3);
      const cr = Math.min(w / 2, hh / 2);
      x.beginPath();
      x.moveTo(-w / 2, -hh / 2);
      x.lineTo(w / 2, -hh / 2);
      x.lineTo(w / 2, hh / 2 - cr);
      x.quadraticCurveTo(w / 2, hh / 2, w / 2 - cr, hh / 2);
      x.lineTo(-w / 2 + cr, hh / 2);
      x.quadraticCurveTo(-w / 2, hh / 2, -w / 2, hh / 2 - cr);
      x.closePath();
      x.fill();
      break;
    }
  }
}


// ── Engine ────────────────────────────────────────────────────────────────────

export class BotEngine {
  isMini = false;
  /** Disc colour behind a mini Klay (integration pills, agents). null = the main Klay. */
  bodyColor: RGB | null = null;

  // Animated state
  yaw = 0; pitch = 0; roll = 0; tilt = 0; open = 1;
  sx = 1; sy = 1; oy = 0; ox = 0;
  tint = 0; morph = 0; hands = 0; blush = 0; es = 1; badgeS = 0;

  // Targets
  tgYaw = 0; tgPitch = 0; tgTilt = 0; tgSy = 1; tgSx = 1; tgEs = 1;

  /** Extra canvas height above the body so hearts can fly out without clipping. */
  particleOverhang = 0;

  // Mouth spring (fraction of R)
  slotH = 0; slotHTarget = 0; slotHVel = 0; isChewing = false;

  col: RGB = C.idle;
  colT: RGB = C.idle;

  state: BotStateName = "idle";
  cfg: BotStateCfg = BOT_STATES.idle;

  eyeOverride: EyeShape | null = null;
  eyeOverrideUntil = 0;
  permanentEye: EyeShape | null = null;
  permanentEmote: BotEmoteName | null = null;
  miniNextBehavior = 0;

  badge: Badge | null = null;
  private badgeKey = "none";
  private badgeToken = 0;

  private tweens = new Map<PropKey, Tween>();
  private locks = new Set<PropKey>();
  private particles: Particle[] = [];

  // Limbs, in Klay's frame (glyph units), eased towards limbTargets().
  private lh: P = { x: -HAND_REST.x, y: HAND_REST.y };
  private rh: P = { x: HAND_REST.x, y: HAND_REST.y };
  private lf: P = { x: -FOOT_REST.x, y: FOOT_REST.y };
  private rf: P = { x: FOOT_REST.x, y: FOOT_REST.y };

  lookX = 0;
  lookY = 0;

  lastTime = now();
  private t0 = now() - Math.random() * 5;
  private nextBlink = now() + 1.5 + Math.random() * 2;
  waveUntil = 0;
  waveStart = 0;
  private greetToken = 0;
  private lastAmbient = 0;
  private slapTimes: number[] = [];
  private miniLookTarget = { x: 0, y: 0 };
  private miniLookNextTime = 0;

  /** Fired when three slaps land inside 1.7 s (→ dizzy + confused view). */
  onDizzy: (() => void) | null = null;

  // ── Public API ──────────────────────────────────────────────────────────────

  setState(next: BotStateName, force = false) {
    if (this.state === next && !force) return;
    const prev = this.state;
    this.state = next;
    this.cfg = BOT_STATES[next];
    this.colT = this.cfg.color;
    if (!this.locks.has("tint")) this.tint = this.cfg.tint;
    if (!this.locks.has("tilt")) this.tgTilt = this.cfg.tilt;
    this.setBadge(this.cfg.badge);

    switch (next) {
      case "finished":
        // A little jump and a full spin, then sparks.
        this.anim("oy", [[-0.35, 260, Ease.out], [0, 380, Ease.back]]);
        this.doRoll(700, 1);
        setTimeout(() => this.emit("spark", 5), 500);
        break;
      case "error":
        this.anim("ox", [
          [0.08, 50, Ease.out], [-0.08, 70, Ease.inOut],
          [0.05, 70, Ease.inOut], [0, 90, Ease.out],
        ]);
        break;
      case "approval":
        this.anim("oy", [[-0.2, 150, Ease.out], [0, 300, Ease.back]]);
        break;
      case "dizzy":
        this.doRoll(1300, 2);
        break;
      case "question":
        this.blink();
        break;
      case "ratelimit":
        this.emit("sweat", 1);
        break;
      default:
        if (prev !== "idle" || next !== "idle") this.blink();
    }
  }

  setBadge(b: Badge | null) {
    const key = b ? `${b.kind}-${b.color.join(",")}` : "none";
    if (key === this.badgeKey) return;
    this.badgeKey = key;
    const tok = ++this.badgeToken;
    this.anim("badgeS", [[0, 90, Ease.inOut]]);
    setTimeout(() => {
      if (tok !== this.badgeToken) return;
      this.badge = b;
      if (b) this.anim("badgeS", [[1, 280, Ease.back]]);
    }, 100);
  }

  blink() {
    if (this.locks.has("open")) return;
    this.anim("open", [[0.06, 70, Ease.inOut], [1, 130, Ease.out]]);
  }

  squash() {
    this.anim("sy", [[0.8, 70, Ease.out], [1.1, 130, Ease.out], [1, 170, Ease.inOut]]);
    this.anim("sx", [[1.14, 70, Ease.out], [0.95, 130, Ease.out], [1, 170, Ease.inOut]]);
  }

  /** Mailbox swallow — opens the slot, chews, then closes. */
  gulp() {
    this.slotHTarget = 0.42;
    setTimeout(() => {
      this.slotHTarget = 0;
      this.isChewing = true;
      setTimeout(() => { this.isChewing = false; }, 800);
    }, 460);
    this.anim("sy", [[0.78, 80, Ease.out], [1.18, 130, Ease.out], [1, 220, Ease.back]]);
    this.anim("sx", [[1.28, 80, Ease.out], [0.92, 130, Ease.out], [1, 220, Ease.back]]);
    this.blink();
  }

  slap() {
    this.interruptGreet();
    if (this.state === "dizzy") return;
    const t = now();
    this.slapTimes = this.slapTimes.filter((s) => t - s < 1.7);
    this.slapTimes.push(t);
    Sound.play("slap");
    this.squash();
    if (this.slapTimes.length >= 3) {
      this.slapTimes = [];
      this.onDizzy?.();
    } else {
      this.eyeOverride = "line";
      this.eyeOverrideUntil = t + 0.8;
      setTimeout(() => Sound.play("annoyed"), 60);
    }
  }

  doRoll(durationMs: number, turns: number) {
    this.roll = 0;
    this.anim("roll", [[Math.PI * 2 * turns, durationMs, Ease.inOut]], () => { this.roll = 0; });
  }

  /** The hello wave when the island peeks out. */
  greet() {
    const t = now();
    const tok = ++this.greetToken;
    this.waveStart = t + 0.45;
    this.waveUntil = t + 1.55;

    this.eyeOverride = "happy";
    this.eyeOverrideUntil = t + 2.0;
    this.anim("oy", [[-0.06, 220, Ease.out], [0.0, 220, Ease.back]]);

    setTimeout(() => {
      if (this.greetToken !== tok) return;
      this.anim("hands", [[1, 280, Ease.out]]);
      this.anim("sy", [[0.95, 100, Ease.out], [1.0, 260, Ease.back]]);
      this.anim("sx", [[1.04, 100, Ease.out], [1.0, 260, Ease.back]]);
      Sound.play("greet");
    }, 250);

    setTimeout(() => { if (this.greetToken === tok) this.blink(); }, 550);
    setTimeout(() => { if (this.greetToken === tok) this.blink(); }, 1500);
    setTimeout(() => {
      if (this.greetToken !== tok) return;
      this.waveUntil = 0;
      this.anim("hands", [[0, 200, Ease.inOut]]);
    }, 1550);
    setTimeout(() => {
      if (this.greetToken !== tok) return;
      this.eyeOverride = "happy";
      this.eyeOverrideUntil = now() + 0.3;
    }, 1750);
  }

  interruptGreet() {
    if (this.hands <= 0.01 && now() >= this.waveUntil) return;
    this.greetToken++;
    this.waveUntil = 0;
    this.waveStart = 0;
    this.anim("hands", [[0, 150, Ease.inOut]]);
  }

  setPermanentEmote(emote: BotEmoteName | null) {
    this.permanentEmote = emote;
    if (emote === "wink") {
      this.miniNextBehavior = now() + 0.8 + Math.random() * 1.7;
      return;
    }
    this.permanentEye = emote ? EMOTE_EYE[emote] : null;
    if (this.permanentEye) {
      this.eyeOverride = this.permanentEye;
      this.eyeOverrideUntil = Number.POSITIVE_INFINITY;
    } else if (this.eyeOverrideUntil === Number.POSITIVE_INFINITY) {
      this.eyeOverride = null;
      this.eyeOverrideUntil = 0;
    }
    this.miniNextBehavior = now() + 0.8 + Math.random() * 1.7;
  }

  triggerEmote(emote: BotEmoteName, duration = 1.8) {
    const t = now();
    this.eyeOverride = EMOTE_EYE[emote];
    this.eyeOverrideUntil = t + duration;

    switch (emote) {
      case "love":
        this.anim("blush", [
          [1, 300, Ease.out], [1, (duration - 0.6) * 1000, Ease.lin], [0, 300, Ease.inOut],
        ]);
        this.emit("heart", 4);
        this.anim("oy", [[-0.1, 160, Ease.out], [0, 300, Ease.back]]);
        break;
      case "surprised":
        this.anim("oy", [[-0.3, 140, Ease.out], [0, 380, Ease.back]]);
        this.anim("es", [[1.25, 120, Ease.out], [1, 500, Ease.inOut]]);
        break;
      case "proud":
        this.emit("star", 5);
        this.anim("tilt", [
          [-0.14, 220, Ease.out], [-0.14, (duration - 0.5) * 1000, Ease.lin], [0, 280, Ease.inOut],
        ]);
        this.anim("blush", [
          [0.7, 250, Ease.out], [0.7, (duration - 0.5) * 1000, Ease.lin], [0, 300, Ease.inOut],
        ]);
        break;
      case "wink":
        this.anim("tilt", [
          [0.12, 160, Ease.out], [0.12, (duration - 0.4) * 1000, Ease.lin], [0, 240, Ease.inOut],
        ]);
        break;
      case "yawn":
        this.anim("sy", [[1.12, 500, Ease.inOut], [1, 500, Ease.inOut]]);
        this.anim("sx", [[0.94, 500, Ease.inOut], [1, 500, Ease.inOut]]);
        setTimeout(() => { this.eyeOverride = "closed"; this.emit("z", 2); }, 700);
        break;
      case "happy":
        this.anim("blush", [[0.6, 200, Ease.out], [0, 600, Ease.inOut]]);
        break;
      case "annoyed":
        this.eyeOverride = "line";
        this.eyeOverrideUntil = t + 0.8;
        setTimeout(() => Sound.play("annoyed"), 60);
        break;
    }
  }

  emit(type: Particle["type"], count: number) {
    for (let i = 0; i < count; i++) {
      const isZ = type === "z";
      this.particles.push({
        type,
        x: (Math.random() - 0.5) * 0.9 + (isZ ? 0.55 : 0),
        y: -0.7 - Math.random() * 0.2,
        vx: (Math.random() - 0.5) * 0.35 + (isZ ? 0.18 : 0),
        vy: -(0.45 + Math.random() * 0.35),
        age: -i * 0.14,
        life: 1.3 + Math.random() * 0.5,
        rot: Math.random() * Math.PI * 2,
        size: 0.15 + Math.random() * 0.08,
      });
    }
  }

  animateMorph(target: number, durationMs?: number) {
    const dur = durationMs ?? (target > 0.5 ? 550 : 650);
    this.anim("morph", [[target, dur, Ease.inOut]]);
  }

  resetMorph() {
    this.tweens.delete("morph");
    this.locks.delete("morph");
    this.morph = 0;
  }

  /** True while anything is still moving — lets the island stop its RAF loop. */
  get busy(): boolean {
    return (
      this.tweens.size > 0 ||
      this.particles.length > 0 ||
      this.cfg.bounces || this.cfg.scans || this.cfg.breathes || this.cfg.zz || this.cfg.sweat ||
      this.isMini ||
      // Klay's limbs keep moving in every state but idle and sleeping.
      (this.state !== "idle" && this.state !== "sleeping") ||
      Math.abs(this.tgYaw - this.yaw) > 0.002 ||
      Math.abs(this.tgPitch - this.pitch) > 0.002 ||
      Math.abs(this.tgTilt - this.tilt) > 0.002 ||
      Math.abs(this.tgSy - this.sy) > 0.002 ||
      Math.abs(this.tgSx - this.sx) > 0.002 ||
      Math.abs(this.tgEs - this.es) > 0.002 ||
      this.slotH > 0.001 || Math.abs(this.slotHVel) > 0.001 ||
      Math.abs(this.col[0] - this.colT[0]) > 0.003 ||
      Math.abs(this.col[1] - this.colT[1]) > 0.003 ||
      Math.abs(this.col[2] - this.colT[2]) > 0.003
    );
  }

  // ── Tweens ──────────────────────────────────────────────────────────────────

  anim(prop: PropKey, keys: TweenKey[], onComplete?: () => void) {
    this.tweens.set(prop, {
      prop, keys, index: 0, from: this[prop], startMs: performance.now(), onComplete,
    });
    this.locks.add(prop);
  }

  // ── Update ──────────────────────────────────────────────────────────────────

  update(dt: number) {
    const n = now();
    const nowMs = performance.now();

    for (const tw of [...this.tweens.values()]) {
      const k = tw.keys[tw.index];
      const p = Math.min(1, Math.max(0, (nowMs - tw.startMs) / k[1]));
      this[tw.prop] = tw.from + (k[0] - tw.from) * k[2](p);
      if (p >= 1) {
        tw.from = k[0];
        tw.index += 1;
        tw.startMs = nowMs;
        if (tw.index >= tw.keys.length) {
          this.tweens.delete(tw.prop);
          this.locks.delete(tw.prop);
          tw.onComplete?.();
        }
      }
    }

    const t = n - this.t0;
    let ty = this.lookX * 0.62;
    let tp = this.lookY * 0.5;

    if (this.cfg.look) {
      ty = ty * 0.35 + this.cfg.look[0] * 0.55;
      tp = tp * 0.3 + this.cfg.look[1] * 0.5;
    }
    if (this.cfg.scans) {
      ty = Math.sin(t * 2.6) * 0.6;
      tp = -0.06;
    }
    if (this.state === "sleeping") { ty = 0; tp = 0.14; }
    if (this.state === "dizzy") { ty = Math.sin(t * 9) * 0.25; }

    // Mini Klays never follow the mouse — they wander.
    if (this.isMini && !this.cfg.look && !this.cfg.scans && this.state !== "sleeping" && this.state !== "dizzy") {
      if (n > this.miniLookNextTime) {
        this.miniLookTarget = {
          x: -0.88 + Math.random() * 1.76,
          y: -0.55 + Math.random() * 1.0,
        };
        this.miniLookNextTime = n + 0.5 + Math.random() * 1.5;
      }
      ty = this.miniLookTarget.x * 0.62;
      tp = this.miniLookTarget.y * 0.5;
    }

    this.tgYaw = ty;
    this.tgPitch = tp;
    this.tgTilt = this.cfg.tilt;

    const waving = n > this.waveStart && n < this.waveUntil;
    if (waving) {
      const wt = n - this.waveStart;
      this.tgTilt = -0.04 + Math.sin(2 * Math.PI * 1.2 * wt) * 0.05;
    }

    const bounce = this.cfg.bounces ? -Math.abs(Math.sin(t * 5.2)) * 0.07 : 0;
    const kGen = 1 - Math.pow(0.0008, dt);
    if (!this.locks.has("oy")) this.oy += (bounce - this.oy) * kGen;

    if (this.cfg.breathes) {
      const amp = this.isMini ? 0.07 : 0.035;
      this.tgSy = 1 + Math.sin(t * 1.8) * amp;
      this.tgSx = 1 - Math.sin(t * 1.8) * amp * 0.57;
    } else if (this.isMini) {
      this.tgSy = 1 + Math.sin(t * 2.2) * 0.04;
      this.tgSx = 1 - Math.sin(t * 2.2) * 0.02;
    } else {
      this.tgSy = 1;
      this.tgSx = 1;
    }

    if (this.isMini && n > this.miniNextBehavior) this.doMiniBehaviorLoop();

    const kLook = 1 - Math.pow(0.0025, dt);
    if (!this.locks.has("yaw")) this.yaw += (this.tgYaw - this.yaw) * kLook;
    if (!this.locks.has("pitch")) this.pitch += (this.tgPitch - this.pitch) * kLook;
    if (!this.locks.has("tilt")) this.tilt += (this.tgTilt - this.tilt) * kGen;
    if (!this.locks.has("sy")) this.sy += (this.tgSy - this.sy) * kGen;
    if (!this.locks.has("sx")) this.sx += (this.tgSx - this.sx) * kGen;
    if (!this.locks.has("es")) this.es += (this.tgEs - this.es) * kGen;

    this.col = mix3(this.col, this.colT, 1 - Math.pow(0.002, dt));

    // Limbs follow their targets with a quick, springy ease.
    const lt = limbTargets(this.state, t, waving ? this.hands : 0);
    const kLimb = 1 - Math.pow(0.00002, dt);
    for (const key of ["lh", "rh", "lf", "rf"] as const) {
      this[key] = {
        x: this[key].x + (lt[key].x - this[key].x) * kLimb,
        y: this[key].y + (lt[key].y - this[key].y) * kLimb,
      };
    }

    if (n > this.nextBlink) {
      if (this.state !== "sleeping" && this.state !== "dizzy") {
        this.blink();
        if (Math.random() < 0.22) setTimeout(() => this.blink(), 230);
      }
      this.nextBlink = n + 2.2 + Math.random() * 3.2;
    }

    if (this.eyeOverride && n > this.eyeOverrideUntil) {
      this.eyeOverride = this.permanentEye;
      if (this.permanentEye) this.eyeOverrideUntil = Number.POSITIVE_INFINITY;
    }

    if (n - this.lastAmbient > 1.3) {
      this.lastAmbient = n;
      if (this.cfg.zz) this.emit("z", 1);
      if (!this.isMini && this.cfg.sweat && Math.random() < 0.5) this.emit("sweat", 1);
    }

    for (const p of this.particles) p.age += dt;
    this.particles = this.particles.filter((p) => p.age < p.life);

    // Mouth slot spring — ω₀ = 2π/0.25, ζ = 0.6
    const omega = (2 * Math.PI) / 0.25;
    const zeta = 0.6;
    const acc = omega * omega * (this.slotHTarget - this.slotH) - 2 * zeta * omega * this.slotHVel;
    this.slotHVel += acc * dt;
    this.slotH = Math.max(0, this.slotH + this.slotHVel * dt);

    this.lastTime = n;
  }

  private doMiniBehaviorLoop() {
    const n = now();
    switch (this.permanentEmote) {
      case "happy":
        if (this.locks.has("oy")) { this.miniNextBehavior = n + 0.4; return; }
        this.anim("oy", [[-0.3, 120, Ease.out], [0.03, 200, Ease.inOut], [0, 160, Ease.back]]);
        this.anim("sy", [[0.82, 80, Ease.out], [1.18, 130, Ease.out], [0.88, 160, Ease.inOut], [1, 200, Ease.back]]);
        this.anim("sx", [[1.15, 80, Ease.out], [0.88, 130, Ease.out], [1.06, 160, Ease.inOut], [1, 200, Ease.back]]);
        this.miniNextBehavior = n + 2.2 + Math.random() * 1.2;
        break;
      case "annoyed":
        if (this.locks.has("yaw")) { this.miniNextBehavior = n + 0.5; return; }
        this.anim("yaw", [
          [-0.65, 50, Ease.out], [0.65, 90, Ease.inOut], [-0.5, 80, Ease.inOut],
          [0.4, 75, Ease.inOut], [-0.2, 70, Ease.inOut], [0, 140, Ease.out],
        ]);
        this.miniNextBehavior = n + 3.0 + Math.random() * 2.5;
        break;
      case "wink":
        this.eyeOverride = "wink";
        this.eyeOverrideUntil = n + 0.55;
        this.anim("tilt", [[0.13, 100, Ease.out], [0.13, 320, Ease.lin], [0, 200, Ease.inOut]]);
        this.miniNextBehavior = n + 2.2 + Math.random() * 2.0;
        break;
      case "love":
        this.emit("heart", 2);
        this.anim("tilt", [[-0.1, 180, Ease.out], [0.1, 340, Ease.inOut], [0, 220, Ease.inOut]]);
        this.miniNextBehavior = n + 2.6 + Math.random() * 1.5;
        break;
      default:
        this.miniNextBehavior = n + 3.0 + Math.random() * 2.0;
    }
  }

  // ── Draw ────────────────────────────────────────────────────────────────────

  /**
   * Draws Klay — glow, limbs, glyph, eyes, mailbox, badge and particles — into a
   * canvas of `W`×`H` CSS pixels (the caller has already applied the DPR transform).
   */
  draw(x: CanvasRenderingContext2D, W: number, H: number) {
    const R = W * 0.3;
    const cx = W / 2 + this.ox * R;
    const cy = H / 2 + this.particleOverhang / 2 + this.oy * R;

    if (this.isMini) this.drawMini(x, R, cx, cy);
    else this.drawMain(x, W, R, cx, cy);

    if (this.badge && this.badgeS > 0.01 && this.morph < 0.25) {
      this.drawBadge(x, this.badge, R, cx, cy);
    }
    this.drawParticles(x, R, cx, cy);
  }

  private drawMain(x: CanvasRenderingContext2D, W: number, R: number, cx: number, cy: number) {
    const m = this.morph;
    const s = (W * GLYPH_SPAN) / GLYPH_W; // px per glyph unit
    const ox = cx;
    const oy = cy - CENTER_Y * s; // the hub, in canvas px

    // Glow of the state colour behind the rays.
    const glow = this.tint * (1 - m);
    if (glow > 0.01) {
      const gx = ox;
      const gy = oy - 70 * s;
      const g = x.createRadialGradient(gx, gy, 0, gx, gy, 380 * s);
      g.addColorStop(0, rgba(this.col, 0.55 * glow));
      g.addColorStop(0.55, rgba(this.col, 0.22 * glow));
      g.addColorStop(1, rgba(this.col, 0));
      x.fillStyle = g;
      x.fillRect(gx - 400 * s, gy - 400 * s, 800 * s, 800 * s);
    }

    x.save();
    x.translate(ox, oy);
    if (Math.abs(this.roll) > 0.001) {
      // Spins turn the whole of Klay around the middle of its height.
      x.translate(0, CENTER_Y * s);
      x.rotate(this.roll);
      x.translate(0, -CENTER_Y * s);
    }
    if (this.tilt !== 0) x.rotate(this.tilt);
    x.scale(this.sx * s, this.sy * s);

    if (m < 0.999) {
      x.save();
      x.globalAlpha = 1 - m;
      const k = 1 - 0.35 * m;
      x.scale(k, k);
      const limbs = W * GLYPH_SPAN >= LIMBS_MIN_PX;
      if (limbs) drawKlayLegs(x, this.lf, this.rf);
      drawKlayGlyph(x);
      if (limbs) drawKlayArms(x, this.lh, this.rh);
      drawKlayBlush(x, this.blush * (1 - m));
      this.drawEyes(x, 1, 0, 0);
      x.restore();
    }
    x.restore();

    if (m > 0.001) this.drawBox(x, R, cx, cy);
  }

  /** Mini Klay: the white glyph and eyes on a disc of the agent's or service's colour. */
  private drawMini(x: CanvasRenderingContext2D, R: number, cx: number, cy: number) {
    const disc = this.bodyColor ?? C.idle;
    x.save();
    x.translate(cx, cy);
    if (this.tilt !== 0) x.rotate(this.tilt);
    x.scale(this.sx, this.sy);
    x.beginPath();
    x.arc(0, 0, R, 0, Math.PI * 2);
    x.fillStyle = rgba(disc, 1);
    x.fill();

    // The glyph fills the disc: 1.55 R wide, its hub a touch below the centre.
    const s = (R * 1.55) / GLYPH_W;
    x.scale(s, s);
    x.translate(0, 70);
    x.save();
    x.translate(-HUB_X, -HUB_Y);
    x.fillStyle = BODY;
    x.fill(glyphPath());
    x.restore();
    this.drawEyes(x, 1.1, 0, 0);
    x.restore();
  }

  /** Eye shape now: the state's, an emote's, or the mailbox's while it eats. */
  private eyeShape(): EyeShape {
    let shape: EyeShape = this.eyeOverride ?? this.cfg.eye;
    if (this.morph > 0.5) {
      if (this.isChewing) shape = "happy";
      else if (this.slotHTarget > 0.05 || this.slotH > 0.1) shape = "cup";
    }
    return shape;
  }

  private drawEyes(x: CanvasRenderingContext2D, mult: number, cxu: number, cyu: number) {
    drawKlayEyes(x, {
      shape: this.eyeShape(), open: this.open, es: this.es, yaw: this.yaw, pitch: this.pitch,
      ink: this.isMini ? MINI_INK : INK,
    }, mult, cxu, cyu);
  }

  /**
   * The mailbox Klay turns into when a file is dropped: a white rounded box with
   * a slot on top and the same eyes. It grows in as the glyph shrinks away.
   */
  private drawBox(x: CanvasRenderingContext2D, R: number, cx: number, cy: number) {
    const m = this.morph;
    const k = 0.55 + 0.45 * m;
    const bw = R * 1.0 * k;
    const bh = R * 0.94 * k;
    x.save();
    x.translate(cx, cy);
    if (this.tilt !== 0) x.rotate(this.tilt);
    x.scale(this.sx, this.sy);
    x.globalAlpha = Math.min(1, m * 1.4);
    roundRectPath(x, -bw, -bh, bw * 2, bh * 2, R * 0.42 * k);
    const g = x.createLinearGradient(0, -bh, 0, bh);
    g.addColorStop(0, "#FFFFFF");
    g.addColorStop(1, "#ECEDE7"); // Klayer brume
    x.fillStyle = g;
    x.fill();

    // Slot
    const hW = R * 1.8 * m * k * 0.9;
    const hH = this.slotH * R * m;
    const hY = -bh + R * 0.1 * m;
    if (hH > 0.8) {
      const hR = Math.min(hW / 2, hH / 2);
      roundRectPath(x, -hW / 2, hY, hW, hH, hR);
      x.fillStyle = "rgb(7,27,32)";
      x.fill();
    }

    // Eyes on the box face (box units → glyph units: the eye shapes are sized in glyph units).
    const u = R / 100;
    x.scale(u, u);
    this.drawEyes(x, 0.62, 0, 12);
    x.restore();
  }

  private drawBadge(x: CanvasRenderingContext2D, badge: Badge, R: number, cx: number, cy: number) {
    const bs = this.badgeS * (this.isMini ? 1.25 : 1);
    const bx = cx - R * (this.isMini ? 0.72 : 0.95) * this.sx;
    const by = cy - R * (this.isMini ? 0.72 : 0.62) * this.sy;
    const t = now();

    x.save();
    x.translate(bx, by);
    x.scale(bs, bs);
    const col = rgba(badge.color);

    if (badge.kind === "dots") {
      if (this.isMini) {
        const phase = (t * 2.4) % 1;
        const dotR = R * 0.22 * (1 + 0.25 * Math.sin(phase * Math.PI * 2));
        x.fillStyle = "#000";
        x.beginPath();
        x.arc(0, 0, R * 0.2, 0, Math.PI * 2);
        x.fill();
        x.fillStyle = col;
        x.beginPath();
        x.arc(0, 0, dotR, 0, Math.PI * 2);
        x.fill();
      } else {
        const pw = R * 0.72;
        const ph = R * 0.36;
        roundRectPath(x, -pw / 2, -ph / 2, pw, ph, ph / 2);
        x.fillStyle = col;
        x.fill();
        for (let i = 0; i < 3; i++) {
          const phase = (((t * 2.4 - i * 0.22) % 1) + 1) % 1;
          const dotR = R * 0.055 * (1 + 0.4 * Math.max(0, Math.sin(phase * Math.PI * 2)));
          x.fillStyle = "#fff";
          x.beginPath();
          x.arc((i - 1) * R * 0.18, 0, dotR, 0, Math.PI * 2);
          x.fill();
        }
      }
    } else if (badge.kind === "bang" || badge.kind === "question") {
      x.fillStyle = "#000";
      x.beginPath();
      x.arc(0, 0, R * 0.3, 0, Math.PI * 2);
      x.fill();
      x.fillStyle = col;
      x.beginPath();
      x.arc(0, 0, R * 0.23, 0, Math.PI * 2);
      x.fill();
      if (!this.isMini) {
        x.fillStyle = "#fff";
        x.font = `900 ${R * 0.32}px ${FONT}`;
        x.textAlign = "center";
        x.textBaseline = "middle";
        x.fillText(badge.kind === "bang" ? "!" : "?", 0, R * 0.02);
      }
    } else {
      x.fillStyle = "#000";
      x.beginPath();
      x.arc(0, 0, R * 0.2, 0, Math.PI * 2);
      x.fill();
      x.fillStyle = col;
      x.beginPath();
      x.arc(0, 0, R * 0.135, 0, Math.PI * 2);
      x.fill();
    }
    x.restore();
  }

  private drawParticles(x: CanvasRenderingContext2D, R: number, cx: number, cy: number) {
    for (const p of this.particles) {
      if (p.age <= 0) continue;
      const k = p.age / p.life;
      const a = k < 0.2 ? k / 0.2 : 1 - (k - 0.2) / 0.8;
      const px = cx + (p.x + p.vx * p.age) * R * 1.3;
      const py = cy + (p.y + p.vy * p.age) * R * 1.3;
      const sz = R * p.size * (1 + k * 0.4);

      x.save();
      x.translate(px, py);
      x.globalAlpha = Math.min(1, Math.max(0, a));
      switch (p.type) {
        case "heart":
          x.rotate(Math.sin(p.age * 6) * 0.3);
          x.fillStyle = "#E8445E";
          heartPath(x, sz);
          x.fill();
          break;
        case "star":
          x.rotate(p.rot + p.age * 2);
          x.fillStyle = "#E3A21A";
          starPath(x, sz, sz * 0.45);
          x.fill();
          break;
        case "spark":
          x.rotate(p.rot);
          x.fillStyle = "#fff";
          starPath(x, sz * 0.8, sz * 0.18);
          x.fill();
          break;
        case "sweat":
          x.fillStyle = "#7CC7FF";
          x.beginPath();
          x.moveTo(0, -sz);
          x.quadraticCurveTo(sz * 0.8, sz * 0.2, 0, sz * 0.6);
          x.quadraticCurveTo(-sz * 0.8, sz * 0.2, 0, -sz);
          x.fill();
          break;
        case "z":
          x.fillStyle = "rgb(209,219,235)";
          x.font = `700 ${sz * 1.9}px ${FONT}`;
          x.textAlign = "center";
          x.textBaseline = "middle";
          x.fillText("z", 0, 0);
          break;
      }
      x.restore();
    }
  }
}
