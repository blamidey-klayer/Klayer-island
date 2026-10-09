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
import {
  MOTION, danceMotion, footTapLift, klayGaze, pointerCurve, rand, rotateAbout, spring2Step, springStep,
  stretchAmount,
  type Gaze, type P, type Spring, type Spring2,
} from "./motion";

// ── Types ─────────────────────────────────────────────────────────────────────

export type EyeShape =
  | "pill" | "wide" | "dot" | "line" | "flat" | "happy" | "closed"
  | "spiral" | "heart" | "star" | "tired" | "wink";

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
  | "oy" | "ox" | "tint" | "hands" | "blush" | "es" | "badgeS";

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
  /** Fixed look direction (yaw, pitch); pitch > 0 looks up. */
  look: readonly [number, number] | null;
  tilt: number;
}

interface Particle {
  type: "heart" | "star" | "spark" | "sweat" | "z";
  x: number; y: number; vx: number; vy: number;
  age: number; life: number; rot: number; size: number;
}

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
/**
 * Binoculars of the searching state, seen from the front and fitted just around the
 * eyes: a round glass centred on each eye (the eye with its rim fits inside), in a
 * brume rim, in a teal-deep ring. The two rings join over the bridge of the nose into
 * one teal-deep shape, a divider between the glasses and a short bridge on top with
 * the focus knob. Klay's eye shows magnified in each glass. Right lens; the left
 * mirrors.
 */
const BINO = {
  /** Lens centre: on the eye. */
  x: EYE_DX, y: EYE_DY,
  /** Glass radius, then the brume rim and the teal-deep ring around it. */
  glassR: 64, rim: 7, ring: 12,
  /** Half width of the teal-deep divider between the two glasses, over the nose. */
  dividerHW: 6,
  /** The eye in the glass: the whole eye scaled by zoom about the lens centre. */
  zoom: 1.3,
  /** Teal-light veil at the glass edge: clear inside veilFrom × glassR, veilAlpha at the edge. */
  veilFrom: 0.62, veilAlpha: 0.75,
  /** White streak of light on the glass, over the eye: an arc about the lens centre, angles in π. */
  shineR: 52, shineFrom: 1.1, shineTo: 1.4, shineW: 7,
  /** Short bridge over the nose between the rings, the focus knob on top of it. */
  bridgeHW: 28, bridgeTop: -84, bridgeBottom: -60,
  knobY: -92, knobHW: 23, knobHH: 13, knobR: 9, knobBand: 8,
  /** The sweep: x offset = yaw × sweep, turn = yaw × turn (rad) about the pivot. */
  sweep: 12, turn: 0.08, pivot: { x: 0, y: EYE_DY } as P,
  /** Where each hand grips the outer side of a lens. */
  hand: { x: 146, y: -6 } as P,
} as const;
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
/** Glyph units in one R (R = 0.3 × canvas width; ox, oy and the dance are in R). */
const UNITS_PER_R = (0.3 * GLYPH_W) / GLYPH_SPAN;
/** Below this glyph width (px) the limbs would be sub-pixel noise: they are left out. */
const LIMBS_MIN_PX = 30;

// ── Colours ───────────────────────────────────────────────────────────────────

/** Glyph white on the dark island (the brand's glyph-white). */
const BODY = "#FFFFFF";
/** Eyes: Klayer teal-deep. */
export const INK = "rgb(7,27,32)"; // #071B20
const MINI_INK = "rgb(7,27,32)";
/** Klayer brume, the rim of the binocular glasses and the band of their focus knob. */
const BRUME = "#ECEDE7";
/** Binocular glasses: Klayer teal-light, a veil at their edge. */
const LENS = "#3E7280";

/**
 * State colours (glow and badge): lightened variants of the Klayer brand colours,
 * readable on the black island (the exact brand values are too dark on black).
 * Mirror of StateColor in BotEngine.swift.
 */
const C = {
  idle: hexToRGB("#3E7280"), // teal-light
  working: hexToRGB("#4FA3B5"), // teal, lightened
  thinking: hexToRGB("#7FB8C4"), // teal, lightened
  searching: hexToRGB("#A8D0D8"), // teal, lightened
  approval: hexToRGB("#D69A3A"), // etat-tension, lightened
  question: hexToRGB("#E2B866"), // etat-tension, lightened
  error: hexToRGB("#D0663F"), // brick, lightened
  finished: hexToRGB("#6FA35E"), // etat-tenu, lightened
  ratelimit: hexToRGB("#B0761C"), // etat-tension
  sleeping: hexToRGB("#C9CAC3"), // filet
  dizzy: hexToRGB("#E08A6A"), // brick, lightened
};

const base = {
  bounces: false, scans: false, breathes: false, zz: false, sweat: false,
  look: null, tilt: 0,
};

export const BOT_STATES: Record<BotStateName, BotStateCfg> = {
  idle: { ...base, color: C.idle, tint: 0.35, eye: "pill", badge: null },
  working: { ...base, color: C.working, tint: 0.72, eye: "pill", badge: { kind: "dots", color: C.working } },
  thinking: { ...base, color: C.thinking, tint: 0.72, eye: "pill", badge: { kind: "dots", color: C.thinking }, look: [0.55, 0.55] },
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

/** Relative luminance (WCAG 2) of a colour. */
function luminance(c: RGB): number {
  const f = (v: number) => (v <= 0.03928 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4);
  return 0.2126 * f(c[0]) + 0.7152 * f(c[1]) + 0.0722 * f(c[2]);
}

/**
 * Above this luminance a badge fill is light. 0.2 is where white and teal-deep
 * contrast equally; every state colour with a badge is above it and gets at least
 * 4.6:1 with teal-deep.
 */
const LIGHT_FILL = 0.2;

/** The colour of a badge's marks (dots, "!", "?"): teal-deep on a light fill, white otherwise. */
export function badgeMarkColor(fill: RGB): string {
  return luminance(fill) > LIGHT_FILL ? INK : "#FFFFFF";
}

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
  state: BotStateName, t: number, waving: number, look = 0,
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
      // Both hands grip the binoculars (drawKlayBinoculars) and follow their sweep.
      lh = binocularsPoint({ x: -BINO.hand.x, y: BINO.hand.y }, look);
      rh = binocularsPoint(BINO.hand, look);
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

/**
 * The "arms open" pose of the drop zone: both hands out to the sides, a little above
 * the eyes, welcoming the file. In Klay's frame (glyph units). Mirror of
 * KlayPaint.armsOpenTargets on the Mac.
 */
export function armsOpenTargets(): { lh: P; rh: P } {
  return { lh: { x: -200, y: -40 }, rh: { x: 200, y: -40 } };
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

/**
 * The hands again, in front of what was drawn over the arms (the binoculars): the arms
 * redrawn inside a disc a little wider than each hand, so the hands grip in front while
 * the arms stay behind, with no seam at the wrist. In Klay's frame. Mirror of
 * KlayPaint.drawHands on the Mac.
 */
export function drawKlayHands(x: CanvasRenderingContext2D, lh: P, rh: P, ink: string = INK) {
  const r = HAND_R + 2 * LIMB_RIM;
  x.save();
  x.beginPath();
  for (const h of [lh, rh]) {
    x.moveTo(h.x + r, h.y);
    x.arc(h.x, h.y, r, 0, Math.PI * 2);
  }
  x.clip();
  drawKlayArms(x, lh, rh, ink);
  x.restore();
}

/** Where a point of the binoculars (Klay's frame, at rest) is once they follow `look`. */
export function binocularsPoint(p: P, look: number): P {
  const k = Math.max(-1, Math.min(1, look));
  const a = k * BINO.turn;
  const dx = p.x - BINO.pivot.x;
  const dy = p.y - BINO.pivot.y;
  return {
    x: BINO.pivot.x + dx * Math.cos(a) - dy * Math.sin(a) + k * BINO.sweep,
    y: BINO.pivot.y + dx * Math.sin(a) + dy * Math.cos(a),
  };
}

/**
 * The binoculars Klay holds up in the searching state, around his eyes, which show
 * magnified in the glasses (the engine draws no other eyes meanwhile). `look` is the
 * yaw (−1…1): they follow the look sweep, x offset = yaw × 12 and a turn of
 * yaw × 0.08 rad about the pivot, and the eyes move with them. `eye` is the eye's
 * shape, blink and scale; the pupils follow `g` (klayGaze) as in drawKlayEyesGaze.
 * The hands grip them at BINO.hand (limbTargets). In Klay's frame. Mirror of
 * KlayPaint.drawBinoculars on the Mac.
 */
export function drawKlayBinoculars(
  x: CanvasRenderingContext2D, look: number, eye: EyeLook, g: Gaze,
) {
  const k = Math.max(-1, Math.min(1, look));
  const B = BINO;
  const outer = B.glassR + B.rim + B.ring;
  x.save();
  x.translate(B.pivot.x + k * B.sweep, B.pivot.y);
  x.rotate(k * B.turn);
  x.translate(-B.pivot.x, -B.pivot.y);
  // One teal-deep shape: the two rings, joined over the nose, and the short bridge on top.
  x.fillStyle = INK;
  for (const sd of [-1, 1]) {
    x.beginPath();
    x.arc(sd * B.x, B.y, outer, 0, Math.PI * 2);
    x.fill();
  }
  x.fillRect(-B.bridgeHW, B.bridgeTop, B.bridgeHW * 2, B.bridgeBottom - B.bridgeTop);
  for (const sd of [-1, 1]) {
    // Each lens stops at the divider: the brume rim, then the glass inside it.
    const side = (from: number) => {
      x.beginPath();
      x.rect(sd > 0 ? from : -from - outer * 2, B.y - outer, outer * 2, outer * 2);
      x.clip();
    };
    x.save();
    side(B.dividerHW);
    x.beginPath();
    x.arc(sd * B.x, B.y, B.glassR + B.rim, 0, Math.PI * 2);
    x.fillStyle = BRUME;
    x.fill();
    side(B.dividerHW + B.rim);
    x.beginPath();
    x.arc(sd * B.x, B.y, B.glassR, 0, Math.PI * 2);
    x.clip();
    x.translate(sd * B.x, B.y);
    // The eye, magnified: the whole of it scaled about the lens centre, the pupil on the gaze.
    x.save();
    x.scale(B.zoom, B.zoom);
    drawKlayEye(x, eye, { x: g.pupilX, y: g.pupilY }, sd, 1);
    x.restore();
    // The teal-light glass, as a veil at its edge, and a streak of light over the eye.
    const veil = x.createRadialGradient(0, 0, B.glassR * B.veilFrom, 0, 0, B.glassR);
    veil.addColorStop(0, rgba(hexToRGB(LENS), 0));
    veil.addColorStop(1, rgba(hexToRGB(LENS), B.veilAlpha));
    x.fillStyle = veil;
    x.fillRect(-B.glassR, -B.glassR, B.glassR * 2, B.glassR * 2);
    x.beginPath();
    x.arc(0, 0, B.shineR, Math.PI * B.shineFrom, Math.PI * B.shineTo);
    x.lineWidth = B.shineW;
    x.lineCap = "round";
    x.strokeStyle = BODY;
    x.stroke();
    x.restore();
  }
  // Focus knob on top of the bridge.
  roundRectPath(x, -B.knobHW, B.knobY - B.knobHH, B.knobHW * 2, B.knobHH * 2, B.knobR);
  x.fillStyle = INK;
  x.fill();
  x.fillStyle = BRUME;
  x.fillRect(-B.knobHW, B.knobY - B.knobBand / 2, B.knobHW * 2, B.knobBand);
  x.restore();
}

/**
 * Hands and feet of Klay in the drop sequence: `arms` (0…1, a little over 1 while the pose
 * overshoots) raises both hands from rest to the open pose (armsOpenTargets), where they sway
 * a little with `t` (seconds); the feet stay at rest. Mirror of KlayPaint.dropLimbs on the Mac.
 */
export function dropLimbs(arms: number, t: number): { lh: P; rh: P; lf: P; rf: P } {
  const open = armsOpenTargets();
  const lhOpen = { x: open.lh.x, y: open.lh.y + Math.sin(t * 1.8 - 1) * 6 };
  const rhOpen = { x: open.rh.x, y: open.rh.y + Math.sin(t * 1.8 + 1) * 6 };
  return {
    lh: { x: lerp(-HAND_REST.x, lhOpen.x, arms), y: lerp(HAND_REST.y, lhOpen.y, arms) },
    rh: { x: lerp(HAND_REST.x, rhOpen.x, arms), y: lerp(HAND_REST.y, rhOpen.y, arms) },
    lf: { x: -FOOT_REST.x, y: FOOT_REST.y },
    rf: FOOT_REST,
  };
}

/** A pose of Klay in the drop sequence (a frame of UploadSequenceEngine on the Mac). */
export interface DropPose {
  /** Hands: 0 at rest, 1 open for the file. */
  arms: number;
  /** pill at rest, wide for the file, closed while he swallows it. */
  eye: EyeShape;
  /** Eyelids: 1 open, towards 0 in a blink. */
  open?: number;
  /** Where he looks (klayGaze: −1…1, yaw > 0 right, pitch > 0 up), the island Klay's gaze. */
  gaze?: { yaw: number; pitch: number };
  /** The gulp's squash, about the middle of his height. */
  sx?: number;
  sy?: number;
}

/**
 * Klay in the drop sequence, drawn like the island's Klay of diameter `d` (BotPlacement's
 * canvas is d / 0.6 wide, the glyph spans GLYPH_SPAN of it), centred on (cx, cy), the middle
 * of his full height: the island's Klay hands over to him there without a jump. `t` (seconds)
 * sways the open hands. Mirror of UploadCanvasView.drawKlay on the Mac.
 */
export function drawKlayDrop(
  x: CanvasRenderingContext2D, cx: number, cy: number, d: number, t: number, pose: DropPose,
) {
  const s = ((d / 0.6) * GLYPH_SPAN) / GLYPH_W; // px per glyph unit
  const l = dropLimbs(pose.arms, t);
  const g = pose.gaze ?? { yaw: 0, pitch: 0 };
  x.save();
  x.translate(cx, cy);
  x.scale(pose.sx ?? 1, pose.sy ?? 1);
  x.translate(0, -CENTER_Y * s);
  x.scale(s, s);
  const limbs = GLYPH_W * s >= LIMBS_MIN_PX;
  if (limbs) drawKlayLegs(x, l.lf, l.rf);
  drawKlayGlyph(x);
  if (limbs) drawKlayArms(x, l.lh, l.rh);
  drawKlayEyesGaze(x, { shape: pose.eye, open: pose.open ?? 1, es: 1, ink: INK }, klayGaze(g.yaw, g.pitch), 1, 0, 0);
  x.restore();
}

/** Pink cheeks under the eyes, `b` 0…1, shifted by `dx` with the eyes. In Klay's frame. */
export function drawKlayBlush(x: CanvasRenderingContext2D, b: number, dx = 0) {
  if (b <= 0.01) return;
  x.save();
  x.fillStyle = `rgba(255,120,150,${0.55 * b})`;
  for (const sd of [-1, 1]) {
    x.beginPath();
    x.ellipse(sd * 74 + dx, 44, 20, 11, 0, 0, Math.PI * 2);
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
ink: string;
}

/**
 * The engine's eyes, in Klay's frame around (cxu, cyu), placed by a gaze (klayGaze):
 * the whites shift and the eye on the side Klay turns to narrows, the pupils move
 * further inside and never leave the white. Mirror of KlayPaint.drawEyes(gaze:) on the Mac.
 */
export function drawKlayEyesGaze(
  x: CanvasRenderingContext2D, e: EyeLook, g: Gaze,
  mult: number, cxu: number, cyu: number,
) {
  const dx = EYE_DX * mult * g.spacing;
  x.save();
  for (const sd of [-1, 1]) {
    x.save();
    x.translate(cxu + sd * dx + g.eyeX * mult, cyu + EYE_DY * mult + g.eyeY * mult);
    x.scale(sd < 0 ? g.squeezeL : g.squeezeR, 1);
    drawKlayEye(x, e, { x: g.pupilX, y: g.pupilY }, sd, mult);
    x.restore();
  }
  x.restore();
}

/**
 * One eye on the origin: the white with its teal-deep rim, and the eye shape moved by
 * `pupil` (glyph units, before `mult`), kept inside the white, inside the rim. `sd` is
 * −1 for the left eye, +1 for the right. Mirror of KlayPaint.drawEye on the Mac.
 */
function drawKlayEye(
  x: CanvasRenderingContext2D, e: EyeLook, pupil: P, sd: number, mult: number,
) {
  const er = EYE_R * e.es * mult;
  x.save();
  x.beginPath();
  x.arc(0, 0, er, 0, Math.PI * 2);
  x.fillStyle = "#FFFFFF";
  x.fill();
  x.lineWidth = EYE_RIM * mult;
  x.strokeStyle = e.ink;
  x.stroke();
  // The pupil stays inside the white, inside the rim.
  x.beginPath();
  x.arc(0, 0, Math.max(0, er - (EYE_RIM * mult) / 2), 0, Math.PI * 2);
  x.clip();
  x.translate(pupil.x * mult, pupil.y * mult);
  x.fillStyle = e.ink;
  x.strokeStyle = e.ink;
  drawEyeShape(x, e.shape, EYE_W * e.es * mult, EYE_H * e.es * mult, sd, e.open);
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
  tint = 0; hands = 0; blush = 0; es = 1; badgeS = 0;

  // Targets
  tgYaw = 0; tgPitch = 0; tgTilt = 0; tgSy = 1; tgSx = 1; tgEs = 1;

  /** Extra canvas height above the body so hearts can fly out without clipping. */
  particleOverhang = 0;

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

  // Limbs, in Klay's frame (glyph units): damped springs pulled towards limbTargets().
  private lh: Spring2 = { x: -HAND_REST.x, y: HAND_REST.y, vx: 0, vy: 0 };
  private rh: Spring2 = { x: HAND_REST.x, y: HAND_REST.y, vx: 0, vy: 0 };
  private lf: Spring2 = { x: -FOOT_REST.x, y: FOOT_REST.y, vx: 0, vy: 0 };
  private rf: Spring2 = { x: FOOT_REST.x, y: FOOT_REST.y, vx: 0, vy: 0 };
  /** The body's place last frame, so its motion can be taken out of the limbs (inertia). */
  private bodyPrev: { x: number; y: number; lean: number; tilt: number } | null = null;

  // Gaze springs (yaw, pitch) and the lean of the whole figure (x from yaw, y from pitch).
  private yawVel = 0;
  private pitchVel = 0;
  private lean: Spring2 = { x: 0, y: 0, vx: 0, vy: 0 };
  /** Hover: the island sets tgEs above 1 while the pointer is on Klay. */
  private hovered = false;
  /** 0…1, eased: how far Klay has lifted towards a pointer on him. */
  private hoverLift = 0;

  /** Where the pointer is, −1…1 each way (tanh of the distance); lookY > 0 is above Klay. */
  lookX = 0;
  lookY = 0;
  private lastLookX = 0;
  private lastLookY = 0;
  private pointerStillSince = now();
  private stillLook = rand(MOTION.idle.stillLook);
  /** While the pointer is still: where Klay glances (null = back at the pointer). */
  private glance: { x: number; y: number } | null = null;
  private glanceNext = 0;
  /** Idle fidgets: a foot tap or a stretch under way, the next fidget, the next stretch or yawn. */
  private fidget: { kind: "tap" | "stretch"; start: number; side: number } | null = null;
  private nextFidget = now() + rand(MOTION.idle.fidget);
  private nextLong = 0;
  private longYawn = true;

  // Dancing (music playing): the level fades in over 0.3 s and out over 0.5 s.
  isDancing = false;
  dancingLevel = 0;

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
    // The hands carry on down as the body squashes.
    this.lh.vy += MOTION.kick.squash;
    this.rh.vy += MOTION.kick.squash;
  }

  slap() {
    this.interruptGreet();
    if (this.state === "dizzy") return;
    const t = now();
    this.slapTimes = this.slapTimes.filter((s) => t - s < 1.7);
    this.slapTimes.push(t);
    Sound.play("slap");
    this.squash();
    // The slap flings the hands up and to one side, the feet a little.
    const side = Math.random() < 0.5 ? -1 : 1;
    for (const h of [this.lh, this.rh]) {
      h.vy -= MOTION.kick.slapUp;
      h.vx += side * MOTION.kick.slapSide;
    }
    this.lf.vy -= MOTION.kick.slapFeet;
    this.rf.vy -= MOTION.kick.slapFeet;
    if (this.slapTimes.length >= 3) {
      this.slapTimes = [];
      this.onDizzy?.();
    } else {
      this.eyeOverride = "line";
      this.eyeOverrideUntil = t + 0.8;
      setTimeout(() => Sound.play("annoyed"), 60);
    }
  }

  /** Spins the whole character `turns` times (finished, dizzy), then lands with a squash. */
  doRoll(durationMs: number, turns: number) {
    this.roll = 0;
    this.anim("roll", [[Math.PI * 2 * turns, durationMs, Ease.inOut]], () => {
      this.roll = 0;
      this.squash();
    });
  }

  setDancing(dancing: boolean) {
    this.isDancing = dancing;
  }

  /** The perk-up as the pointer arrives on Klay: a little stretch, hands up. */
  private perk() {
    this.anim("sy", [[1.07, 110, Ease.out], [1, 280, Ease.back]]);
    this.anim("sx", [[0.96, 110, Ease.out], [1, 280, Ease.back]]);
    this.lh.vy -= MOTION.kick.perk;
    this.rh.vy -= MOTION.kick.perk;
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
        this.squash();
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

  /**
   * True while anything is still moving, which is always now: the main Klay breathes,
   * glances and fidgets in every state, a mini Klay pulses and wanders.
   */
  get busy(): boolean {
    return true;
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
    const kGen = 1 - Math.pow(0.0008, dt);

    // Hover: the island raises tgEs above 1 while the pointer is on Klay.
    const hovered = !this.isMini && this.tgEs > 1.001;
    if (hovered && !this.hovered) this.perk();
    this.hovered = hovered;
    this.hoverLift += ((hovered ? 1 : 0) - this.hoverLift) * kGen;

    // How long the pointer has been still.
    if (Math.abs(this.lookX - this.lastLookX) + Math.abs(this.lookY - this.lastLookY) > 0.002) {
      this.pointerStillSince = n;
      this.stillLook = rand(MOTION.idle.stillLook);
      this.glance = null;
      this.glanceNext = 0;
    }
    this.lastLookX = this.lookX;
    this.lastLookY = this.lookY;
    const still = n - this.pointerStillSince;

    // Where Klay looks: the pointer, through the response curve (closer still when on him).
    const gain = hovered ? MOTION.hover.gain : 1;
    let ty = Math.max(-1, Math.min(1, pointerCurve(this.lookX) * gain)) * MOTION.yawRange;
    let tp = Math.max(-1, Math.min(1, pointerCurve(this.lookY) * gain)) * MOTION.pitchRange;

    if (this.cfg.look) {
      ty = ty * 0.35 + this.cfg.look[0] * 0.55;
      tp = tp * 0.3 + this.cfg.look[1] * 0.5;
    }
    if (this.cfg.scans) {
      // The binoculars sweep left and right, a little above the horizon.
      ty = Math.sin(t * 2.6) * 0.6;
      tp = 0.06;
    }
    if (this.state === "sleeping") { ty = 0; tp = -0.14; }
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

    // The main Klay, pointer still for a while: he looks around, now and then back at it.
    const glances = !this.isMini && !hovered && !this.cfg.look && !this.cfg.scans &&
      (this.state === "idle" || this.state === "working" || this.state === "finished");
    if (glances && still > this.stillLook) {
      if (n >= this.glanceNext) {
        const I = MOTION.idle;
        this.glance = Math.random() < I.back ? null : {
          x: (Math.random() * 2 - 1) * I.glanceX,
          y: I.glanceDown + Math.random() * (I.glanceUp - I.glanceDown),
        };
        this.glanceNext = n + rand(I.glance);
      }
      if (this.glance) {
        ty = this.glance.x * MOTION.yawRange;
        tp = this.glance.y * MOTION.pitchRange;
      }
    } else {
      this.glance = null;
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
    if (!this.locks.has("oy")) this.oy += (bounce - this.oy) * kGen;

    if (this.cfg.breathes) {
      const amp = this.isMini ? 0.07 : 0.035;
      this.tgSy = 1 + Math.sin(t * 1.8) * amp;
      this.tgSx = 1 - Math.sin(t * 1.8) * amp * 0.57;
    } else if (this.isMini) {
      this.tgSy = 1 + Math.sin(t * 2.2) * 0.04;
      this.tgSx = 1 - Math.sin(t * 2.2) * 0.02;
    } else {
      // Awake, the main Klay breathes too, lightly.
      const B = MOTION.breath;
      this.tgSy = 1 + Math.sin(t * B.speed) * B.amp;
      this.tgSx = 1 - Math.sin(t * B.speed) * B.amp * 0.5;
    }

    if (this.isMini && n > this.miniNextBehavior) this.doMiniBehaviorLoop();

    // The gaze springs to its target: the eyes dart, overshoot a touch and settle.
    const G = MOTION.gaze;
    if (!this.locks.has("yaw")) {
      const sp: Spring = { v: this.yaw, vel: this.yawVel };
      springStep(sp, this.tgYaw, dt, G.response, G.damping);
      this.yaw = sp.v;
      this.yawVel = sp.vel;
    } else {
      this.yawVel = 0;
    }
    if (!this.locks.has("pitch")) {
      const sp: Spring = { v: this.pitch, vel: this.pitchVel };
      springStep(sp, this.tgPitch, dt, G.response, G.damping);
      this.pitch = sp.v;
      this.pitchVel = sp.vel;
    } else {
      this.pitchVel = 0;
    }
    if (!this.locks.has("tilt")) this.tilt += (this.tgTilt - this.tilt) * kGen;
    if (!this.locks.has("sy")) this.sy += (this.tgSy - this.sy) * kGen;
    if (!this.locks.has("sx")) this.sx += (this.tgSx - this.sx) * kGen;
    if (!this.locks.has("es")) this.es += (this.tgEs - this.es) * kGen;

    // The whole figure leans towards where Klay looks, after the eyes.
    if (!this.isMini) {
      const L = MOTION.lean;
      const target = {
        x: Math.max(-1, Math.min(1, this.tgYaw / MOTION.yawRange)),
        y: Math.max(-1, Math.min(1, this.tgPitch / MOTION.pitchRange)),
      };
      spring2Step(this.lean, target, dt, L.response, L.damping);
    }

    this.col = mix3(this.col, this.colT, 1 - Math.pow(0.002, dt));

    // Dance level: fade in 0.3 s, out 0.5 s.
    const danceTarget = this.isDancing ? 1 : 0;
    if (this.dancingLevel < danceTarget) this.dancingLevel = Math.min(danceTarget, this.dancingLevel + dt / 0.3);
    else if (this.dancingLevel > danceTarget) this.dancingLevel = Math.max(danceTarget, this.dancingLevel - dt / 0.5);

    this.updateFidget(n, still);

    // Limbs: springs pulled towards the pose, carried by the body's motion.
    if (!this.isMini) this.updateLimbs(n, t, dt, waving);

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

    this.lastTime = n;
  }

  /**
   * Idle fidgets of the main Klay: a foot tap every few seconds, and when the pointer has
   * been still a long while, a stretch or a yawn in turn. Only while idle and calm.
   */
  private updateFidget(n: number, still: number) {
    if (this.fidget) {
      const dur = this.fidget.kind === "tap" ? MOTION.tap.dur : MOTION.stretch.dur;
      if (n - this.fidget.start >= dur || this.state !== "idle" || this.hovered) this.fidget = null;
      return;
    }
    const calm = !this.isMini && this.state === "idle" && !this.hovered && this.dancingLevel < 0.01 &&
      n >= this.waveUntil && !this.eyeOverride && !this.locks.has("sy");
    if (!calm) {
      this.nextFidget = Math.max(this.nextFidget, n + 2);
      return;
    }
    if (n < this.nextFidget) return;
    const I = MOTION.idle;
    this.nextFidget = n + rand(I.fidget);
    if (still > I.longAfter && n >= this.nextLong) {
      this.nextLong = n + rand(I.longEvery);
      this.longYawn = !this.longYawn;
      if (this.longYawn) {
        this.triggerEmote("yawn", 2.2);
        return;
      }
      this.fidget = { kind: "stretch", start: n, side: 1 };
      const S = MOTION.stretch;
      const up = S.up * 1000;
      const hold = (S.hold - S.up) * 1000;
      const down = (S.dur - S.hold) * 1000;
      this.anim("sy", [[1.06, up, Ease.inOut], [1.06, hold, Ease.lin], [1, down, Ease.back]]);
      this.anim("sx", [[0.97, up, Ease.inOut], [0.97, hold, Ease.lin], [1, down, Ease.back]]);
      return;
    }
    this.fidget = { kind: "tap", start: n, side: Math.random() < 0.5 ? -1 : 1 };
  }

  /** Where the body is, for the limbs' inertia: glyph units and radians. */
  private bodyPose(n: number) {
    const L = MOTION.lean;
    let x = this.ox * UNITS_PER_R + this.lean.x * L.shift;
    let y = this.oy * UNITS_PER_R - (this.lean.y * L.rise + this.hoverLift * MOTION.hover.rise);
    if (this.dancingLevel > 0.001) {
      const d = danceMotion(n, this.dancingLevel);
      x += d.dx * UNITS_PER_R;
      y += d.dy * UNITS_PER_R;
    }
    return { x, y, lean: this.lean.x * L.tilt, tilt: this.tilt };
  }

  private updateLimbs(n: number, t: number, dt: number, waving: boolean) {
    const lt = limbTargets(this.state, t, waving ? this.hands : 0, this.yaw);
    if (this.fidget) {
      const ft = n - this.fidget.start;
      if (this.fidget.kind === "tap") {
        const foot = this.fidget.side < 0 ? lt.lf : lt.rf;
        foot.y -= footTapLift(ft);
      } else {
        const k = stretchAmount(ft);
        const H = MOTION.stretch.hands;
        lt.lh = { x: lerp(lt.lh.x, -H.x, k), y: lerp(lt.lh.y, H.y, k) };
        lt.rh = { x: lerp(lt.rh.x, H.x, k), y: lerp(lt.rh.y, H.y, k) };
      }
    }

    // The body's motion since last frame, seen from Klay's frame: a limb keeps `inertia`
    // of its place in the world, then its spring brings it back (lag, overshoot, settle).
    const B = this.bodyPose(n);
    const prev = this.bodyPrev ?? B;
    this.bodyPrev = B;
    const cl = (v: number, m: number) => Math.max(-m, Math.min(m, v));
    const dx = cl(B.x - prev.x, MOTION.maxStep);
    const dy = cl(B.y - prev.y, MOTION.maxStep);
    const dLean = cl(B.lean - prev.lean, MOTION.maxTurn);
    const dTilt = cl(B.tilt - prev.tilt, MOTION.maxTurn);
    const limbs = [
      [this.lh, lt.lh, MOTION.hand], [this.rh, lt.rh, MOTION.hand],
      [this.lf, lt.lf, MOTION.foot], [this.rf, lt.rf, MOTION.foot],
    ] as const;
    for (const [sp, target, cfg] of limbs) {
      const k = cfg.inertia;
      sp.x -= dx * k;
      sp.y -= dy * k;
      rotateAbout(sp, 0, BOTTOM, -dLean * k);
      rotateAbout(sp, 0, 0, -dTilt * k);
      spring2Step(sp, target, dt, cfg.response, cfg.damping);
    }
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
   * Draws Klay — glow, limbs, glyph, eyes, badge and particles — into a
   * canvas of `W`×`H` CSS pixels (the caller has already applied the DPR transform).
   */
  draw(x: CanvasRenderingContext2D, W: number, H: number) {
    const R = W * 0.3;
    const cx = W / 2 + this.ox * R;
    const cy = H / 2 + this.particleOverhang / 2 + this.oy * R;

    x.save();
    this.applyDance(x, W, H);
    if (this.isMini) this.drawMini(x, R, cx, cy);
    else this.drawMain(x, W, cx, cy);

    if (this.badge && this.badgeS > 0.01) {
      this.drawBadge(x, this.badge, R, cx, cy);
    }
    this.drawParticles(x, R, cx, cy);
    x.restore();
  }

  /**
   * The dance bounce and sway around Klay's soles (the bottom of a mini's disc), applied
   * to everything drawn after it. Mirror of BotEngine.applyDance on the Mac.
   */
  applyDance(x: CanvasRenderingContext2D, W: number, H: number) {
    if (this.dancingLevel <= 0.001) return;
    const R = W * 0.3;
    const s = (W * GLYPH_SPAN) / GLYPH_W;
    const footOffset = this.isMini ? R : (BOTTOM - CENTER_Y) * s;
    const px = W / 2 + this.ox * R;
    const py = H / 2 + this.particleOverhang / 2 + this.oy * R + footOffset;
    const d = danceMotion(now(), this.dancingLevel);
    x.translate(px + d.dx * R, py + d.dy * R);
    x.rotate(d.rot);
    x.scale(d.sx, d.sy);
    x.translate(-px, -py);
  }

  private drawMain(x: CanvasRenderingContext2D, W: number, cx: number, cy: number) {
    const s = (W * GLYPH_SPAN) / GLYPH_W; // px per glyph unit
    const ox = cx;
    const oy = cy - CENTER_Y * s; // the hub, in canvas px

    // Glow of the state colour behind the rays.
    const glow = this.tint;
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
    // Lean: the whole figure turns towards where Klay looks, about the soles; looking up
    // lifts and stretches him a little, and he rises towards a pointer on him.
    const L = MOTION.lean;
    const soles = BOTTOM * s;
    x.translate(this.lean.x * L.shift * s, -(this.lean.y * L.rise + this.hoverLift * MOTION.hover.rise) * s);
    x.translate(0, soles);
    x.rotate(this.lean.x * L.tilt);
    x.scale(1, 1 + this.lean.y * L.stretch);
    x.translate(0, -soles);
    if (Math.abs(this.roll) > 0.001) {
      // Spins turn the whole of Klay around the middle of its height.
      x.translate(0, CENTER_Y * s);
      x.rotate(this.roll);
      x.translate(0, -CENTER_Y * s);
    }
    if (this.tilt !== 0) x.rotate(this.tilt);
    x.scale(this.sx * s, this.sy * s);

    const limbs = W * GLYPH_SPAN >= LIMBS_MIN_PX;
    if (limbs) drawKlayLegs(x, this.lf, this.rf);
    drawKlayGlyph(x);
    if (limbs) drawKlayArms(x, this.lh, this.rh);
    if (this.state === "searching") {
      // Binoculars up around the eyes, which show magnified in them, over the arms and the
      // cheeks; the hands grip their sides in front.
      drawKlayBinoculars(x, this.yaw, this.eyeStyle(), klayGaze(this.yaw, this.pitch));
      if (limbs) drawKlayHands(x, this.lh, this.rh);
    } else {
      drawKlayBlush(x, this.blush, klayGaze(this.yaw, this.pitch).eyeX * 0.8);
      this.drawEyes(x, 1, 0, 0);
    }
    x.restore();
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

  /** Eye shape now: the state's or an emote's, happy while dancing, shut mid-stretch. */
  private eyeShape(): EyeShape {
    let shape: EyeShape = this.eyeOverride ?? this.cfg.eye;
    // Dance: happy eyes in the calm states.
    if (this.isDancing && this.dancingLevel > 0.15 && !this.isMini && (this.state === "idle" || this.state === "finished")) {
      shape = "happy";
    }
    // Stretching: eyes shut in the middle of it.
    if (this.fidget?.kind === "stretch" && !this.eyeOverride) {
      const ft = now() - this.fidget.start;
      if (ft > MOTION.stretch.eyesFrom && ft < MOTION.stretch.eyesTo) shape = "closed";
    }
    return shape;
  }

  /** The eyes' shape, blink, scale and ink this frame. */
  private eyeStyle(): EyeLook {
    return { shape: this.eyeShape(), open: this.open, es: this.es, ink: this.isMini ? MINI_INK : INK };
  }

  private drawEyes(x: CanvasRenderingContext2D, mult: number, cxu: number, cyu: number) {
    drawKlayEyesGaze(x, this.eyeStyle(), klayGaze(this.yaw, this.pitch), mult, cxu, cyu);
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
    const mark = badgeMarkColor(badge.color);

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
          x.fillStyle = mark;
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
        x.fillStyle = mark;
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
