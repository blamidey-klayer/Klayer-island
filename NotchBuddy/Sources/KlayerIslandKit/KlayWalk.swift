import Foundation
// On macOS, Foundation alone gives CGPoint no geometry accessors: they come from CoreGraphics.
// On Linux, Foundation already has them and CoreGraphics does not exist.
#if canImport(CoreGraphics)
import CoreGraphics
#endif

// Klay's walk back into the island. After a drag, and on every way home from the desktop, Klay
// walks from where he is to just under his place in the island, then hops in (KlayWalker).
//
// The plan (how long, how far at each instant, which way he faces) is in points and seconds;
// the gait (feet, bob, arms) is in glyph units, in Klay's frame (y down), as a function of the
// stride phase. Pure functions, no clock, Foundation only, so scripts/test-klay-walk.sh tests
// them without the app. Mirror of tools/klay-preview/src/walk.ts: same constants, same formulas
// (WALK → KlayWalk, walkPlan → Plan, walkGait → gait, walkLimbs → limbs, walkDoorstep →
// doorstep, walkHop → hop).

enum KlayWalk {

    // MARK: - Constants

    /// Walking speed (pt/s): the walk lasts distance / speed, kept within [minDuration, maxDuration] s.
    static let speed: CGFloat = 650
    static let minDuration: Double = 0.7
    static let maxDuration: Double = 2.2
    /// Closer than this to the end of the walk (pt): no walk, Klay hops straight in.
    static let minDistance: CGFloat = 40
    /// Steps per second (a step is half a stride). His speed eases in over the first step and
    /// out over the last.
    static let cadence: Double = 2.5
    /// Klay is drawn from the front, so the walk reads in height: a swinging foot is lifted by up
    /// to `lift` and reaches `stride` forward (the way he faces) at the top of its swing, while
    /// the foot on the ground pushes back by stride × push.
    static let stride: CGFloat = 20
    static let push: CGFloat = 0.5
    static let lift: CGFloat = 72
    /// The body drops by `bob` on each contact and rises by `bob` mid-stride.
    static let bob: CGFloat = 20
    /// Seen from the front, a hand swinging forward comes in front of the body: the hand opposite
    /// the lifted foot moves up to armIn towards Klay's middle and rises by up to armRise; the
    /// other hand swings back, up to armOut away from his middle, rising by armRise × armBackRise.
    static let armIn: CGFloat = 34
    static let armOut: CGFloat = 14
    static let armRise: CGFloat = 80
    static let armBackRise: CGFloat = 0.25
    /// Klay leans this far (rad) the way he faces, about his soles, while he walks.
    static let lean: CGFloat = 0.08
    /// The walk ends `rise` × the walker's width under his place in the island.
    static let rise: CGFloat = 0.3
    /// The hop into the island: its duration (s) and how high it rises above the line (pt).
    static let hopDuration: Double = 0.34
    static let hopHeight: CGFloat = 18

    private static func clamp<T: Comparable>(_ v: T, _ lo: T, _ hi: T) -> T { max(lo, min(hi, v)) }

    private static func smooth(_ t: CGFloat) -> CGFloat {
        let k = clamp(t, 0, 1)
        return k * k * (3 - 2 * k)
    }

    // MARK: - Plan

    /// How long a walk of `distance` points lasts (s): 0 at minDistance or closer.
    static func duration(distance: CGFloat) -> Double {
        guard distance > minDistance else { return 0 }
        return clamp(Double(distance / speed), minDuration, maxDuration)
    }

    /// Klay walking, as the engine reads it every frame (BotEngine.walk).
    struct Pose: Equatable, Sendable {
        /// Stride phase, 0…1: the left foot swings in the first half, the right in the second.
        var phase: Double
        /// 0 standing … 1 walking: it scales the stride, the bob, the swing and the lean.
        var amount: CGFloat
        /// +1 walking right (or straight up or down), −1 walking left.
        var facing: CGFloat
    }

    /// A walk in a straight line from `from` to `to` (points, any y direction; AppKit's on the Mac).
    struct Plan: Equatable, Sendable {
        let from: CGPoint
        let to: CGPoint
        /// Seconds; 0 when the walk is too short to take (minDistance).
        let duration: Double
        /// How long his speed takes to rise from 0 (and to fall back): one step, or half the walk
        /// if shorter.
        let ramp: Double
        /// +1 when Klay walks right (or straight up or down), −1 when he walks left.
        let facing: CGFloat
        /// Unit vector from `from` to `to`, in the coordinates' own axes; (0, 0) when they meet.
        let heading: CGPoint

        init(from: CGPoint, to: CGPoint) {
            let dx = to.x - from.x
            let dy = to.y - from.y
            let d = hypot(dx, dy)
            self.from = from
            self.to = to
            duration = KlayWalk.duration(distance: d)
            ramp = min(1 / KlayWalk.cadence, duration / 2)
            facing = dx < 0 ? -1 : 1
            heading = d > 0 ? CGPoint(x: dx / d, y: dy / d) : .zero
        }

        /// The walk and the hop that ends it (s).
        var total: Double { duration + KlayWalk.hopDuration }

        /// Where the hop starts: where the walk leaves him, the doorstep, or where he was dropped
        /// when there is no walk (no jump to the doorstep first).
        var hopStart: CGPoint { position(at: duration) }

        /// How far along the walk Klay is (0…1) `t` seconds in. His speed rises from 0 over the
        /// first step and falls back to 0 over the last one (a half cosine), and stays even in
        /// between. Without a walk (dropped within minDistance), 0: he stays where he was dropped.
        func progress(at t: Double) -> CGFloat {
            let T = duration
            if T <= 0 || t <= 0 { return 0 }
            if t >= T { return 1 }
            let r = ramp
            let v = 1 / (T - r)
            // Distance covered `u` seconds into a ramp from rest.
            func covered(_ u: Double) -> Double { v * (u / 2 - r / (2 * .pi) * sin(.pi * u / r)) }
            if t < r { return CGFloat(covered(t)) }
            if t > T - r { return CGFloat(1 - covered(T - t)) }
            return CGFloat(v * (r / 2 + (t - r)))
        }

        /// Where Klay is `t` seconds into the walk: on the straight line from `from` to `to`.
        func position(at t: Double) -> CGPoint {
            let k = progress(at: t)
            return CGPoint(x: from.x + (to.x - from.x) * k, y: from.y + (to.y - from.y) * k)
        }

        /// His speed as a fraction of the even walking speed (0…1): it scales the gait.
        func amount(at t: Double) -> CGFloat {
            let T = duration
            guard T > 0, t > 0, t < T else { return 0 }
            let u = min(t, T - t)
            return u >= ramp ? 1 : CGFloat((1 - cos(.pi * u / ramp)) / 2)
        }

        /// The stride phase (0…1) `t` seconds into the walk, at `cadence`: a stride is two steps,
        /// the left foot swings in its first half and the right foot in its second. 0 at the start.
        func phase(at t: Double) -> Double {
            guard duration > 0 else { return 0 }
            let steps = KlayWalk.clamp(t, 0, duration) * KlayWalk.cadence
            let p = (steps / 2).truncatingRemainder(dividingBy: 1)
            return p < 0 ? p + 1 : p
        }

        /// The engine's pose `t` seconds into the walk.
        func pose(at t: Double) -> Pose {
            Pose(phase: phase(at: t), amount: amount(at: t), facing: facing)
        }

        /// How far into the hop he is (0…1) `t` seconds after the walk started: nil while he walks.
        func hopProgress(at t: Double) -> Double? {
            guard t >= duration else { return nil }
            return KlayWalk.clamp((t - duration) / KlayWalk.hopDuration, 0, 1)
        }
    }

    // MARK: - Gait

    /// A foot: how far forward it is (along the way Klay faces) and how high it is lifted.
    struct FootGait: Equatable, Sendable {
        var fwd: CGFloat
        var lift: CGFloat
    }

    /// A hand: how far it has come towards Klay's middle (below 0, away from it) and how high it rises.
    struct HandGait: Equatable, Sendable {
        var inward: CGFloat
        var rise: CGFloat
    }

    /// The walk at one instant, in glyph units: feet, hands, and the body's drop (y down).
    struct Gait: Equatable, Sendable {
        var lf: FootGait
        var rf: FootGait
        var lh: HandGait
        var rh: HandGait
        var bob: CGFloat
    }

    /// A foot swinging `s` (−1…1), unscaled. While `s` is above 0 the foot is in the air: lifted
    /// by `s`, reaching forward by `s`. Below 0 it is on the ground, pushing back by push × `s`.
    private static func footCycle(_ s: CGFloat) -> FootGait {
        s > 0 ? FootGait(fwd: s, lift: s) : FootGait(fwd: push * s, lift: 0)
    }

    /// A hand swinging `s` (−1 back … 1 front), in glyph units: it rises at both ends of its swing.
    private static func handCycle(_ s: CGFloat) -> HandGait {
        s > 0
            ? HandGait(inward: s * armIn, rise: s * s * armRise)
            : HandGait(inward: s * armOut, rise: s * s * armRise * armBackRise)
    }

    /// The gait at stride phase `phase`, scaled by `amount` (0 standing … 1 walking). The left
    /// foot swings, lifted forward, in the first half of the stride while the right one pushes
    /// back, then the other way round; the hand opposite the lifted foot swings forward and up,
    /// the other back; the body is lowest on each contact (phase 0 and ½) and highest
    /// mid-stride (¼ and ¾).
    static func gait(phase: Double, amount: CGFloat = 1) -> Gait {
        var p = phase.truncatingRemainder(dividingBy: 1)
        if p < 0 { p += 1 }
        let k = clamp(amount, 0, 1)
        let swing = CGFloat(sin(2 * .pi * p))
        let l = footCycle(swing)
        let r = footCycle(-swing)
        let lh = handCycle(-swing)
        let rh = handCycle(swing)
        return Gait(
            lf: FootGait(fwd: l.fwd * stride * k, lift: l.lift * lift * k),
            rf: FootGait(fwd: r.fwd * stride * k, lift: r.lift * lift * k),
            lh: HandGait(inward: lh.inward * k, rise: lh.rise * k),
            rh: HandGait(inward: rh.inward * k, rise: rh.rise * k),
            bob: CGFloat(cos(4 * .pi * p)) * bob * k)
    }

    /// Hands and feet for a gait, in Klay's frame (glyph units), around their rest places: the
    /// feet forward along `facing` (±1), lifted, and set against the bob so a planted foot stays
    /// put while the body drops and rises; the hands in and up. `handRest` and `footRest` are the
    /// right side's (KlayPaint.handRest, KlayPaint.footRest).
    static func limbs(_ g: Gait, facing: CGFloat, handRest: CGPoint, footRest: CGPoint)
        -> (lh: CGPoint, rh: CGPoint, lf: CGPoint, rf: CGPoint) {
        (lh: CGPoint(x: -handRest.x + g.lh.inward, y: handRest.y - g.lh.rise),
         rh: CGPoint(x: handRest.x - g.rh.inward, y: handRest.y - g.rh.rise),
         lf: CGPoint(x: -footRest.x + facing * g.lf.fwd, y: footRest.y - g.lf.lift - g.bob),
         rf: CGPoint(x: footRest.x + facing * g.rf.fwd, y: footRest.y - g.rf.lift - g.bob))
    }

    // MARK: - The end of the walk

    /// Where the walk ends, y up (AppKit): `rise` × the walker's width under Klay's place in the
    /// island (`place`, his centre), or under the notch's bottom edge when his place is in the notch.
    static func doorstep(place: CGPoint, notchBottom: CGFloat, walkerWidth: CGFloat) -> CGPoint {
        CGPoint(x: place.x, y: min(place.y, notchBottom) - rise * walkerWidth)
    }

    /// One instant of the hop: the walker's centre (y up), width and opacity.
    struct HopFrame: Equatable, Sendable {
        var center: CGPoint
        var width: CGFloat
        var alpha: CGFloat
    }

    /// The hop into the island, `u` (0…1) into it: from the end of the walk `from` (walker width
    /// `fromWidth`) to Klay's place `to` (canvas width `toWidth`), rising hopHeight above the line
    /// at mid-hop, y up. When his place is hidden (`fades`, the closed island over the notch), he
    /// fades out over the last 40 %.
    static func hop(_ u: Double, from: CGPoint, to: CGPoint, fromWidth: CGFloat, toWidth: CGFloat,
                    fades: Bool) -> HopFrame {
        let k = CGFloat(clamp(u, 0, 1))
        let e = smooth(k)
        return HopFrame(
            center: CGPoint(x: from.x + (to.x - from.x) * e,
                            y: from.y + (to.y - from.y) * e + sin(.pi * k) * hopHeight),
            width: fromWidth + (toWidth - fromWidth) * e,
            alpha: fades ? 1 - smooth((k - 0.6) / 0.4) : 1)
    }
}
