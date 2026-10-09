// Klay's walk back into the island. After a drag, and on every way home from the desktop,
// Klay walks from where he is to just under his place in the island, then hops in.
//
// The plan (how long, how far at each instant, which way he faces) is in points and
// seconds; the gait (feet, bob, arms) is in glyph units, in Klay's frame (y down), as a
// function of the stride phase. Pure functions, no clock. Mirror of KlayWalk.swift on the
// Mac: same constants, same formulas.

import type { P } from "./motion";

const clamp = (v: number, lo: number, hi: number) => Math.max(lo, Math.min(hi, v));
const smooth = (t: number) => { const k = clamp(t, 0, 1); return k * k * (3 - 2 * k); };

export const WALK = {
  /** Walking speed (pt/s): the walk lasts distance / speed, kept within [minDuration, maxDuration] s. */
  speed: 650,
  minDuration: 0.7,
  maxDuration: 2.2,
  /** Closer than this to the end of the walk (pt): no walk, Klay hops straight in. */
  minDistance: 40,
  /** Steps per second (a step is half a stride). His speed eases in over the first step and out over the last. */
  cadence: 2.5,
  /**
   * Klay is drawn from the front, so the walk reads in height: a swinging foot is lifted by up
   * to `lift` and reaches `stride` forward (the way he faces) at the top of its swing, while
   * the foot on the ground pushes back by stride × push.
   */
  stride: 20,
  push: 0.5,
  lift: 72,
  /** The body drops by `bob` on each contact and rises by `bob` mid-stride. */
  bob: 20,
  /**
   * Seen from the front, a hand swinging forward comes in front of the body: the hand opposite
   * the lifted foot moves up to armIn towards Klay's middle and rises by up to armRise; the
   * other hand swings back, up to armOut away from his middle, rising by armRise × armBackRise.
   */
  armIn: 34,
  armOut: 14,
  armRise: 80,
  armBackRise: 0.25,
  /** Klay leans this far (rad) the way he faces, about his soles, while he walks. */
  lean: 0.08,
  /** The walk ends `rise` × the walker's width under his place in the island. */
  rise: 0.3,
  /** The hop into the island: its duration (s) and how high it rises above the line (pt). */
  hopDuration: 0.34,
  hopHeight: 18,
} as const;

// ── Plan ──────────────────────────────────────────────────────────────────────

/** A walk in a straight line from `from` to `to` (points, any y direction). */
export interface WalkPlan {
  from: P;
  to: P;
  /** Seconds; 0 when the walk is too short to take (WALK.minDistance). */
  duration: number;
  /** How long his speed takes to rise from 0 (and to fall back): one step, or half the walk if shorter. */
  ramp: number;
  /** +1 when Klay walks right (or straight up or down), −1 when he walks left. */
  facing: 1 | -1;
  /** Unit vector from `from` to `to`, in the coordinates' own axes; (0, 0) when they meet. */
  heading: P;
}

/** How long a walk of `distance` points lasts (s): 0 at WALK.minDistance or closer. */
export function walkDuration(distance: number): number {
  if (!(distance > WALK.minDistance)) return 0;
  return clamp(distance / WALK.speed, WALK.minDuration, WALK.maxDuration);
}

export function walkPlan(from: P, to: P): WalkPlan {
  const dx = to.x - from.x;
  const dy = to.y - from.y;
  const d = Math.hypot(dx, dy);
  const duration = walkDuration(d);
  return {
    from,
    to,
    duration,
    ramp: Math.min(1 / WALK.cadence, duration / 2),
    facing: dx < 0 ? -1 : 1,
    heading: d > 0 ? { x: dx / d, y: dy / d } : { x: 0, y: 0 },
  };
}

/**
 * How far along the walk Klay is (0…1) `t` seconds in. His speed rises from 0 over the first
 * step and falls back to 0 over the last one (a half cosine), and stays even in between.
 * Without a walk (dropped within WALK.minDistance), 0: he stays where he was dropped.
 */
export function walkProgress(plan: WalkPlan, t: number): number {
  const T = plan.duration;
  if (T <= 0 || t <= 0) return 0;
  if (t >= T) return 1;
  const r = plan.ramp;
  const v = 1 / (T - r);
  // Distance covered `u` seconds into a ramp from rest.
  const ramp = (u: number) => v * (u / 2 - (r / (2 * Math.PI)) * Math.sin((Math.PI * u) / r));
  if (t < r) return ramp(t);
  if (t > T - r) return 1 - ramp(T - t);
  return v * (r / 2 + (t - r));
}

/** Where Klay is `t` seconds into the walk: on the straight line from `from` to `to`. */
export function walkPosition(plan: WalkPlan, t: number): P {
  const k = walkProgress(plan, t);
  return { x: plan.from.x + (plan.to.x - plan.from.x) * k, y: plan.from.y + (plan.to.y - plan.from.y) * k };
}

/** His speed as a fraction of the even walking speed (0…1): it scales the gait. */
export function walkAmount(plan: WalkPlan, t: number): number {
  const T = plan.duration;
  if (T <= 0 || t <= 0 || t >= T) return 0;
  const r = plan.ramp;
  const u = Math.min(t, T - t);
  return u >= r ? 1 : (1 - Math.cos((Math.PI * u) / r)) / 2;
}

/**
 * The stride phase (0…1) `t` seconds into the walk, at WALK.cadence: a stride is two steps, the
 * left foot swings in its first half and the right foot in its second. 0 at the start.
 */
export function walkPhase(plan: WalkPlan, t: number): number {
  if (plan.duration <= 0) return 0;
  const steps = clamp(t, 0, plan.duration) * WALK.cadence;
  return (((steps / 2) % 1) + 1) % 1;
}

/**
 * Where the hop starts: where the walk leaves him, the doorstep, or where he was dropped when
 * there is no walk (no jump to the doorstep first).
 */
export function walkHopStart(plan: WalkPlan): P {
  return walkPosition(plan, plan.duration);
}

/** How far into the hop he is (0…1) `t` seconds after the walk started: null while he walks. */
export function walkHopProgress(plan: WalkPlan, t: number): number | null {
  if (t < plan.duration) return null;
  return clamp((t - plan.duration) / WALK.hopDuration, 0, 1);
}

// ── Gait ──────────────────────────────────────────────────────────────────────

/** A foot: how far forward it is (along the way Klay faces) and how high it is lifted. */
export interface FootGait { fwd: number; lift: number }
/** A hand: how far it has come towards Klay's middle (below 0, away from it) and how high it rises. */
export interface HandGait { inward: number; rise: number }

/** The walk at one instant, in glyph units: feet, hands, and the body's drop (y down). */
export interface Gait {
  lf: FootGait;
  rf: FootGait;
  lh: HandGait;
  rh: HandGait;
  bob: number;
}

/**
 * A foot swinging `s` (−1…1), unscaled. While `s` is above 0 the foot is in the air: lifted by
 * `s`, reaching forward by `s`. Below 0 it is on the ground, pushing back by push × `s`.
 */
function footCycle(s: number): FootGait {
  return s > 0 ? { fwd: s, lift: s } : { fwd: WALK.push * s, lift: 0 };
}

/** A hand swinging `s` (−1 back … 1 front), in glyph units: it rises at both ends of its swing. */
function handCycle(s: number): HandGait {
  return s > 0
    ? { inward: s * WALK.armIn, rise: s * s * WALK.armRise }
    : { inward: s * WALK.armOut, rise: s * s * WALK.armRise * WALK.armBackRise };
}

/**
 * The gait at stride phase `phase`, scaled by `amount` (0 standing … 1 walking). The left foot
 * swings, lifted forward, in the first half of the stride while the right one pushes back, then
 * the other way round; the hand opposite the lifted foot swings forward and up, the other back;
 * the body is lowest on each contact (phase 0 and ½) and highest mid-stride (¼ and ¾).
 */
export function walkGait(phase: number, amount = 1): Gait {
  const p = ((phase % 1) + 1) % 1;
  const k = clamp(amount, 0, 1);
  const swing = Math.sin(2 * Math.PI * p);
  const l = footCycle(swing);
  const r = footCycle(-swing);
  const lh = handCycle(-swing);
  const rh = handCycle(swing);
  return {
    lf: { fwd: l.fwd * WALK.stride * k, lift: l.lift * WALK.lift * k },
    rf: { fwd: r.fwd * WALK.stride * k, lift: r.lift * WALK.lift * k },
    lh: { inward: lh.inward * k, rise: lh.rise * k },
    rh: { inward: rh.inward * k, rise: rh.rise * k },
    bob: Math.cos(4 * Math.PI * p) * WALK.bob * k,
  };
}

/**
 * Hands and feet for a gait, in Klay's frame (glyph units), around their rest places: the feet
 * forward along `facing` (±1), lifted, and set against the bob so a planted foot stays put while
 * the body drops and rises; the hands in and up. `handRest` and `footRest` are the right side's.
 */
export function walkLimbs(g: Gait, facing: number, handRest: P, footRest: P): { lh: P; rh: P; lf: P; rf: P } {
  return {
    lf: { x: -footRest.x + facing * g.lf.fwd, y: footRest.y - g.lf.lift - g.bob },
    rf: { x: footRest.x + facing * g.rf.fwd, y: footRest.y - g.rf.lift - g.bob },
    lh: { x: -handRest.x + g.lh.inward, y: handRest.y - g.lh.rise },
    rh: { x: handRest.x - g.rh.inward, y: handRest.y - g.rh.rise },
  };
}

// ── The end of the walk ───────────────────────────────────────────────────────

/**
 * Where the walk ends, y up (AppKit): `rise` × the walker's width under Klay's place in the
 * island (`place`, his centre), or under the notch's bottom edge when his place is in the notch.
 */
export function walkDoorstep(place: P, notchBottom: number, walkerWidth: number): P {
  return { x: place.x, y: Math.min(place.y, notchBottom) - WALK.rise * walkerWidth };
}

/** One instant of the hop: the walker's centre (y up), width and opacity. */
export interface HopFrame { center: P; width: number; alpha: number }

/**
 * The hop into the island, `u` (0…1) into it: from the end of the walk `from` (walker width
 * `fromWidth`) to Klay's place `to` (canvas width `toWidth`), rising WALK.hopHeight above the
 * line at mid-hop, y up. When his place is hidden (`fades`, the closed island over the notch),
 * he fades out over the last 40 %.
 */
export function walkHop(u: number, from: P, to: P, fromWidth: number, toWidth: number, fades: boolean): HopFrame {
  const k = clamp(u, 0, 1);
  const e = smooth(k);
  return {
    center: {
      x: from.x + (to.x - from.x) * e,
      y: from.y + (to.y - from.y) * e + Math.sin(Math.PI * k) * WALK.hopHeight,
    },
    width: fromWidth + (toWidth - fromWidth) * e,
    alpha: fades ? 1 - smooth((k - 0.6) / 0.4) : 1,
  };
}
