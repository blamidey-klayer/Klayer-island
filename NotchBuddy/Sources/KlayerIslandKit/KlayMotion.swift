import Foundation
// On macOS, Foundation alone gives CGPoint and CGRect no geometry accessors: they come from
// CoreGraphics. On Linux, Foundation already has them and CoreGraphics does not exist.
#if canImport(CoreGraphics)
import CoreGraphics
#endif

// Klay's motion: damped springs, the gaze, the lean towards the pointer and the idle
// fidgets. Pure functions of time and dt (seconds), never of the frame count, so Klay moves
// the same at 30, 60 or 120 Hz. Foundation only, so scripts/test-klay-motion.sh tests it
// without the app. Mirror of tools/klay-preview/src/motion.ts: same constants, same
// formulas (MOTION → KlayMotion, GAZE → KlayMotion.Eyes, klayGaze → KlayMotion.gaze).

// MARK: - Springs

/// A damped spring of mass 1: its value and its velocity (units per second).
struct KlaySpring: Equatable, Sendable {
    var value: CGFloat
    var velocity: CGFloat = 0

    /// Moves towards `target` over `dt` seconds. ω₀ = 2π / response, ζ = damping (below 1 it
    /// overshoots, then settles). Semi-implicit Euler, cut into KlayMotion.substep slices so a
    /// slow frame never destabilises it. A frame with no time (0, negative, NaN) does nothing;
    /// a frame longer than KlayMotion.maxDt (a pause) counts as maxDt.
    mutating func step(towards target: CGFloat, dt: Double, response: CGFloat, damping: CGFloat) {
        guard dt > 0 else { return }
        let span = min(dt, KlayMotion.maxDt)
        let w = 2 * .pi / response
        let n = max(1, Int((span / KlayMotion.substep).rounded(.up)))
        let h = CGFloat(span / Double(n))
        for _ in 0..<n {
            let acc = w * w * (target - value) - 2 * damping * w * velocity
            velocity += acc * h
            value += velocity * h
        }
    }
}

/// A spring for each axis of a point.
struct KlaySpring2: Equatable, Sendable {
    var x: KlaySpring
    var y: KlaySpring

    init(_ p: CGPoint) {
        x = KlaySpring(value: p.x)
        y = KlaySpring(value: p.y)
    }

    var point: CGPoint { CGPoint(x: x.value, y: y.value) }

    mutating func step(towards target: CGPoint, dt: Double, response: CGFloat, damping: CGFloat) {
        x.step(towards: target.x, dt: dt, response: response, damping: damping)
        y.step(towards: target.y, dt: dt, response: response, damping: damping)
    }

    /// Moves the point by (dx, dy), keeping its velocity.
    mutating func shift(dx: CGFloat, dy: CGFloat) {
        x.value += dx
        y.value += dy
    }

    /// Turns the point by `a` radians about `c`, keeping its velocity.
    mutating func rotate(about c: CGPoint, by a: CGFloat) {
        guard a != 0 else { return }
        let dx = x.value - c.x
        let dy = y.value - c.y
        x.value = c.x + dx * cos(a) - dy * sin(a)
        y.value = c.y + dx * sin(a) + dy * cos(a)
    }
}

// MARK: - Gaze

/// Where the eyes and pupils sit for a gaze. Glyph units, y down, before the eyes' `mult`.
struct KlayGaze: Equatable, Sendable {
    /// Shift of both eye whites.
    var eye: CGPoint
    /// Shift of the pupils inside the eyes.
    var pupil: CGPoint
    /// Factor on the eye spacing.
    var spacing: CGFloat
    /// Horizontal scale of the left and the right eye.
    var squeezeL: CGFloat
    var squeezeR: CGFloat

    /// Horizontal scale of the eye on side `sd` (-1 left, +1 right).
    func squeeze(side sd: CGFloat) -> CGFloat { sd < 0 ? squeezeL : squeezeR }
}

// MARK: - Constants and helpers

enum KlayMotion {
    /// Integration step: a long frame is cut into steps no longer than this (s).
    static let substep: Double = 1.0 / 240
    /// Longest time a spring integrates in one call (s): a longer frame is a pause.
    static let maxDt: Double = 0.1

    /// A limb's spring and how much of the body's motion it keeps (inertia).
    struct Limb: Sendable {
        let response: CGFloat
        let damping: CGFloat
        let inertia: CGFloat
    }

    /// The gaze (yaw, pitch) springs towards where Klay looks: quick, a touch of overshoot.
    static let gazeResponse: CGFloat = 0.2
    static let gazeDamping: CGFloat = 0.6

    /// Hands and feet are damped springs in Klay's frame. When the body moves (hops, shakes,
    /// dance, lean), `inertia` of that motion is taken out of them, so they lag, overshoot and
    /// settle. Feet are stiffer and mostly follow the body.
    static let hand = Limb(response: 0.22, damping: 0.45, inertia: 0.85)
    static let foot = Limb(response: 0.14, damping: 0.6, inertia: 0.4)
    /// Largest body motion fed to the limbs in one frame (glyph units, rad): snaps are not motion.
    static let maxStep: CGFloat = 60
    static let maxTurn: CGFloat = 0.2

    /// Kicks (units per second) given to the hands: a squash pushes them down, a slap flings
    /// them, the perk-up of a hover lifts them.
    enum Kick {
        static let squash: CGFloat = 420
        static let slapUp: CGFloat = 900
        static let slapSide: CGFloat = 500
        static let slapFeet: CGFloat = 300
        static let perk: CGFloat = 350
    }

    /// The lean: the whole figure turns towards where Klay looks, more slowly than the eyes.
    /// x (−1…1, from the yaw): a turn of `tilt` rad about the soles and a shift of `shift`
    /// units. y (−1…1, from the pitch): looking up lifts him by `rise` units and stretches him
    /// by `stretch` about the soles; looking down does the opposite.
    enum Lean {
        static let response: CGFloat = 0.6
        static let damping: CGFloat = 0.5
        static let tilt: CGFloat = 0.06
        static let shift: CGFloat = 16
        static let rise: CGFloat = 10
        static let stretch: CGFloat = 0.02
    }

    /// Largest yaw and pitch the pointer gives (lookX × 0.62, lookY × 0.5, as in the original).
    static let yawRange: CGFloat = 0.62
    static let pitchRange: CGFloat = 0.5
    /// The pointer (lookX, lookY, −1…1 from tanh of the distance) goes through
    /// sign(l)·|l|^curve, so small moves near Klay show in his eyes.
    static let curve: CGFloat = 0.75

    /// Hover (the island sets tgEs above 1 while the pointer is on Klay): the gaze gain is
    /// multiplied by `gain` (the pointer is close, his eyes follow it closely), he lifts by
    /// `rise` units towards it, and perks up as the pointer arrives.
    enum Hover {
        static let gain: CGFloat = 2.4
        static let rise: CGFloat = 8
    }

    /// Awake breathing of the main Klay (sleeping keeps its own, deeper one).
    enum Breath {
        static let speed: CGFloat = 1.9
        static let amp: CGFloat = 0.012
    }

    enum Idle {
        /// Pointer still this long (s, random in range) → Klay looks around.
        static let stillLook: ClosedRange<Double> = 3.5...6
        /// Each glance lasts (s); `back` is the chance a glance returns to the pointer.
        static let glance: ClosedRange<Double> = 0.6...1.6
        static let back: Double = 0.3
        /// Where a glance goes: x within ±glanceX, y from glanceDown (down) to glanceUp (up).
        static let glanceX: CGFloat = 0.9
        static let glanceDown: CGFloat = -0.35
        static let glanceUp: CGFloat = 0.55
        /// Time between two fidgets while idle (s).
        static let fidget: ClosedRange<Double> = 5...12
        /// Pointer still this long (s) before a stretch or a yawn, then one every `longEvery` s.
        static let longAfter: Double = 25
        static let longEvery: ClosedRange<Double> = 35...70
    }

    /// Foot tap: taps at `hz` over `dur` s, the toe lifting `lift` units.
    enum Tap {
        static let dur: Double = 0.9
        static let hz: Double = 3.3
        static let lift: CGFloat = 20
    }

    /// Stretch: both hands up to (±x, y) and the body stretched, eyes closed in the middle.
    /// Up in `up` s, held until `hold`, down by `dur`.
    enum Stretch {
        static let dur: Double = 1.8
        static let up: Double = 0.45
        static let hold: Double = 1.3
        static let hands = CGPoint(x: 130, y: -215)
        static let eyesFrom: Double = 0.35
        static let eyesTo: Double = 1.35
    }

    /// The gaze geometry.
    enum Eyes {
        /// Eye whites shift by yaw × eyeX and −pitch × eyeY (glyph units, before `mult`).
        static let eyeX: CGFloat = 48
        static let eyeY: CGFloat = 30
        /// Pupils shift further inside the eye by yaw × pupilX and −pitch × pupilY.
        static let pupilX: CGFloat = 40
        static let pupilY: CGFloat = 32
        /// The pupil never leaves this ellipse around the eye centre (it stays inside the white).
        static let pupilMaxX: CGFloat = 26
        static let pupilMaxY: CGFloat = 18
        /// Turning, the eye on that side narrows (head turn) and the two eyes come closer.
        static let squeeze: CGFloat = 0.16
        static let spacing: CGFloat = 0.08
    }

    // MARK: Pointer, gaze

    /// The pointer response curve: odd, monotonic, 0 → 0 and ±1 → ±1, steeper near 0.
    static func pointerCurve(_ l: CGFloat) -> CGFloat {
        let k = max(-1, min(1, l))
        return k < 0 ? -pow(-k, curve) : pow(k, curve)
    }

    /// The gaze for a yaw and a pitch (each −1…1; pitch > 0 looks up, yaw > 0 looks right).
    static func gaze(yaw: CGFloat, pitch: CGFloat) -> KlayGaze {
        let k = max(-1, min(1, yaw))
        let p = max(-1, min(1, pitch))
        var px = k * Eyes.pupilX
        var py = -p * Eyes.pupilY
        let e = hypot(px / Eyes.pupilMaxX, py / Eyes.pupilMaxY)
        if e > 1 {
            px /= e
            py /= e
        }
        return KlayGaze(eye: CGPoint(x: k * Eyes.eyeX, y: -p * Eyes.eyeY),
                        pupil: CGPoint(x: px, y: py),
                        spacing: 1 - Eyes.spacing * abs(k),
                        squeezeL: 1 - Eyes.squeeze * max(0, -k),
                        squeezeR: 1 - Eyes.squeeze * max(0, k))
    }

    // MARK: Fidgets

    private static func smooth(_ t: Double) -> Double {
        let k = max(0, min(1, t))
        return k * k * (3 - 2 * k)
    }

    /// How high the tapping toe is lifted (glyph units, ≥ 0) `ft` seconds into a foot tap.
    static func footTapLift(_ ft: Double) -> CGFloat {
        guard ft > 0, ft < Tap.dur else { return 0 }
        // Fades in and out over the first and last tenth so the foot never jumps.
        let env = min(1, ft / (Tap.dur * 0.1), (Tap.dur - ft) / (Tap.dur * 0.1))
        return CGFloat(max(0, sin(2 * .pi * Tap.hz * ft)) * env) * Tap.lift
    }

    /// How far the hands are into the stretch pose (0…1) `ft` seconds into a stretch.
    static func stretchAmount(_ ft: Double) -> CGFloat {
        guard ft > 0, ft < Stretch.dur else { return 0 }
        if ft < Stretch.up { return CGFloat(smooth(ft / Stretch.up)) }
        if ft < Stretch.hold { return 1 }
        return CGFloat(1 - smooth((ft - Stretch.hold) / (Stretch.dur - Stretch.hold)))
    }

    // MARK: Dance, frame delta

    /// One instant of the dance.
    struct Dance: Sendable {
        /// Sway and hop, in R (R = 0.3 × canvas width), y down.
        let dx: CGFloat
        let dy: CGFloat
        /// Sway angle (rad).
        let rot: CGFloat
        /// Squash on each landing.
        let sx: CGFloat
        let sy: CGFloat
    }

    /// The dance at 112 BPM, `level` 0…1, at `time` (s): a hop and a sway around the soles,
    /// a squash on each landing.
    static func dance(time: Double, level l: CGFloat) -> Dance {
        let beat = CGFloat(time) * 112 / 60
        let sw = sin(.pi * beat)
        let hop = abs(sw)
        let land = pow(1 - hop, 6)
        return Dance(dx: 0.08 * sw * l, dy: -0.20 * hop * l, rot: 0.10 * sw * l,
                     sx: 1 + 0.045 * land * l, sy: 1 - 0.06 * land * l)
    }

    /// The frame's dt (s) from two readings of the same clock: never negative, at most 0.05.
    static func frameDelta(now: Double, last: Double) -> Double {
        min(0.05, max(0, now - last))
    }
}
