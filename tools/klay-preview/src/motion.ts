// Klay's motion: damped springs, the gaze, the lean towards the pointer and the idle
// fidgets. Pure functions of time and dt (seconds), never of the frame count, so Klay
// moves the same at 30, 60 or 120 Hz. Mirror of KlayMotion.swift on the Mac: same
// constants, same formulas.

export interface P { x: number; y: number }

const clamp = (v: number, lo: number, hi: number) => Math.max(lo, Math.min(hi, v));

// ── Springs ───────────────────────────────────────────────────────────────────

/** A damped spring of mass 1: its value and its velocity (units per second). */
export interface Spring { v: number; vel: number }

/** A spring for each axis of a point. */
export interface Spring2 { x: number; y: number; vx: number; vy: number }

/** Integration step: a long frame is cut into steps no longer than this (s). */
export const SUBSTEP = 1 / 240;
/** Longest time a spring integrates in one call (s): a longer frame is a pause. */
export const MAX_DT = 0.1;

/**
 * Moves `s` towards `target` over `dt` seconds. ω₀ = 2π / response, ζ = damping
 * (below 1 it overshoots, then settles). Semi-implicit Euler, cut into SUBSTEP slices
 * so a slow frame never destabilises it. A frame with no time (0, negative, NaN) does
 * nothing; a frame longer than MAX_DT (a pause) counts as MAX_DT.
 */
export function springStep(s: Spring, target: number, dt: number, response: number, damping: number) {
  if (!(dt > 0)) return;
  const span = Math.min(dt, MAX_DT);
  const w = (2 * Math.PI) / response;
  const n = Math.max(1, Math.ceil(span / SUBSTEP));
  const h = span / n;
  for (let i = 0; i < n; i++) {
    const acc = w * w * (target - s.v) - 2 * damping * w * s.vel;
    s.vel += acc * h;
    s.v += s.vel * h;
  }
}

/** springStep on both axes of a point. */
export function spring2Step(s: Spring2, target: P, dt: number, response: number, damping: number) {
  const a: Spring = { v: s.x, vel: s.vx };
  const b: Spring = { v: s.y, vel: s.vy };
  springStep(a, target.x, dt, response, damping);
  springStep(b, target.y, dt, response, damping);
  s.x = a.v; s.vx = a.vel;
  s.y = b.v; s.vy = b.vel;
}

/** Turns point `p` by `a` radians about (cx, cy), in place. */
export function rotateAbout(p: { x: number; y: number }, cx: number, cy: number, a: number) {
  if (a === 0) return;
  const c = Math.cos(a);
  const s = Math.sin(a);
  const dx = p.x - cx;
  const dy = p.y - cy;
  p.x = cx + dx * c - dy * s;
  p.y = cy + dx * s + dy * c;
}

// ── Constants ─────────────────────────────────────────────────────────────────

export const MOTION = {
  /** The gaze (yaw, pitch) springs towards where Klay looks: quick, a touch of overshoot. */
  gaze: { response: 0.2, damping: 0.6 },
  /**
   * Hands and feet are damped springs in Klay's frame. When the body moves (hops, shakes,
   * dance, lean), `inertia` of that motion is taken out of them, so they lag, overshoot
   * and settle. Feet are stiffer and mostly follow the body.
   */
  hand: { response: 0.22, damping: 0.45, inertia: 0.85 },
  foot: { response: 0.14, damping: 0.6, inertia: 0.4 },
  /** Largest body motion fed to the limbs in one frame (glyph units, rad): snaps are not motion. */
  maxStep: 60, maxTurn: 0.2,
  /** Kicks (units per second) given to the hands: a squash pushes them down, a slap flings them. */
  kick: { squash: 420, slapUp: 900, slapSide: 500, slapFeet: 300, perk: 350 },
  /**
   * The lean: the whole figure turns towards where Klay looks, more slowly than the eyes.
   * x (−1…1, from the yaw): a turn of `tilt` rad about the soles and a shift of `shift`
   * units. y (−1…1, from the pitch): looking up lifts him by `rise` units and stretches
   * him by `stretch` about the soles; looking down does the opposite.
   */
  lean: { response: 0.6, damping: 0.5, tilt: 0.06, shift: 16, rise: 10, stretch: 0.02 },
  /** Largest yaw and pitch the pointer gives (lookX × 0.62, lookY × 0.5, as in the original). */
  yawRange: 0.62, pitchRange: 0.5,
  /**
   * The pointer (lookX, lookY, −1…1 from tanh of the distance) goes through
   * sign(l)·|l|^curve, so small moves near Klay show in his eyes.
   */
  curve: 0.75,
  /**
   * Hover (the island sets tgEs above 1 while the pointer is on Klay): the gaze gain is
   * multiplied by `gain` (the pointer is close, his eyes follow it closely), he lifts by
   * `rise` units towards it, and perks up as the pointer arrives.
   */
  hover: { gain: 2.4, rise: 8 },
  /** Awake breathing of the main Klay (sleeping keeps its own, deeper one). */
  breath: { speed: 1.9, amp: 0.012 },
  idle: {
    /** Pointer still this long (s, random in range) → Klay looks around. */
    stillLook: [3.5, 6] as const,
    /** Each glance lasts (s); `back` is the chance a glance returns to the pointer. */
    glance: [0.6, 1.6] as const, back: 0.3,
    /** Where a glance goes: x within ±glanceX, y from glanceDown (down) to glanceUp (up). */
    glanceX: 0.9, glanceDown: -0.35, glanceUp: 0.55,
    /** Time between two fidgets while idle (s). */
    fidget: [5, 12] as const,
    /** Pointer still this long (s) before a stretch or a yawn, then one every `longEvery` s. */
    longAfter: 25, longEvery: [35, 70] as const,
  },
  /** Foot tap: taps at `hz` over `dur` s, the toe lifting `lift` units. */
  tap: { dur: 0.9, hz: 3.3, lift: 20 },
  /**
   * Stretch: both hands up to (±x, y) and the body stretched, eyes closed in the middle.
   * Up in `up` s, held until `hold`, down by `dur`.
   */
  stretch: { dur: 1.8, up: 0.45, hold: 1.3, hands: { x: 130, y: -215 } as P, eyesFrom: 0.35, eyesTo: 1.35 },
} as const;

// ── Pointer ───────────────────────────────────────────────────────────────────

/** The pointer response curve: odd, monotonic, 0 → 0 and ±1 → ±1, steeper near 0. */
export function pointerCurve(l: number): number {
  const k = clamp(l, -1, 1);
  return Math.sign(k) * Math.pow(Math.abs(k), MOTION.curve);
}

// ── Gaze ──────────────────────────────────────────────────────────────────────

export const GAZE = {
  /** Eye whites shift by yaw × eyeX and −pitch × eyeY (glyph units, before `mult`). */
  eyeX: 48, eyeY: 30,
  /** Pupils shift further inside the eye by yaw × pupilX and −pitch × pupilY. */
  pupilX: 40, pupilY: 32,
  /** The pupil never leaves this ellipse around the eye centre (it stays inside the white). */
  pupilMaxX: 26, pupilMaxY: 18,
  /** Turning, the eye on that side narrows (head turn) and the two eyes come closer. */
  squeeze: 0.16, spacing: 0.08,
} as const;

/** Where the eyes and pupils sit for a gaze. Glyph units, y down, before `mult`. */
export interface Gaze {
  eyeX: number; eyeY: number;
  pupilX: number; pupilY: number;
  /** Factor on the eye spacing. */
  spacing: number;
  /** Horizontal scale of the left (−1) and right (+1) eye. */
  squeezeL: number; squeezeR: number;
}

/** The gaze for a yaw and a pitch (each −1…1; pitch > 0 looks up, yaw > 0 looks right). */
export function klayGaze(yaw: number, pitch: number): Gaze {
  const k = clamp(yaw, -1, 1);
  const p = clamp(pitch, -1, 1);
  let px = k * GAZE.pupilX;
  let py = -p * GAZE.pupilY;
  const e = Math.hypot(px / GAZE.pupilMaxX, py / GAZE.pupilMaxY);
  if (e > 1) { px /= e; py /= e; }
  return {
    eyeX: k * GAZE.eyeX,
    eyeY: -p * GAZE.eyeY,
    pupilX: px,
    pupilY: py,
    spacing: 1 - GAZE.spacing * Math.abs(k),
    squeezeL: 1 - GAZE.squeeze * Math.max(0, -k),
    squeezeR: 1 - GAZE.squeeze * Math.max(0, k),
  };
}

// ── Fidgets ───────────────────────────────────────────────────────────────────

const smooth = (t: number) => { const k = clamp(t, 0, 1); return k * k * (3 - 2 * k); };

/** How high the tapping toe is lifted (glyph units, ≥ 0) `ft` seconds into a foot tap. */
export function footTapLift(ft: number): number {
  const T = MOTION.tap;
  if (ft <= 0 || ft >= T.dur) return 0;
  // Fades in and out over the first and last tenth so the foot never jumps.
  const env = Math.min(1, ft / (T.dur * 0.1), (T.dur - ft) / (T.dur * 0.1));
  return Math.max(0, Math.sin(2 * Math.PI * T.hz * ft)) * T.lift * env;
}

/** How far the hands are into the stretch pose (0…1) `ft` seconds into a stretch. */
export function stretchAmount(ft: number): number {
  const S = MOTION.stretch;
  if (ft <= 0 || ft >= S.dur) return 0;
  if (ft < S.up) return smooth(ft / S.up);
  if (ft < S.hold) return 1;
  return 1 - smooth((ft - S.hold) / (S.dur - S.hold));
}

/**
 * The dance at 112 BPM, `level` 0…1, at time `n` (s): a hop and a sway around the soles,
 * a squash on each landing. dx, dy in R (y down); rot in radians; sx, sy scales.
 */
export function danceMotion(n: number, level: number) {
  const beat = (n * 112) / 60;
  const sw = Math.sin(Math.PI * beat);
  const hop = Math.abs(sw);
  const land = Math.pow(1 - hop, 6);
  return {
    dx: 0.08 * sw * level,
    dy: -0.2 * hop * level,
    rot: 0.1 * sw * level,
    sx: 1 + 0.045 * land * level,
    sy: 1 - 0.06 * land * level,
  };
}

/** The frame's dt (s) from two readings of the same clock: never negative, at most 0.05. */
export function frameDelta(now: number, last: number): number {
  return Math.min(0.05, Math.max(0, now - last));
}

/** A random number in [a, b). */
export const rand = (r: readonly [number, number]) => r[0] + Math.random() * (r[1] - r[0]);
