import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// Klay's motion helpers (KlayMotion.swift): springs, gaze, pointer curve, fidgets, dance,
/// frame delta. Mirror of tools/klay-preview/src/motion.ts.
@main
enum KlayMotionTests {
    static func main() {
        testSpringSettles()
        testSpringOvershootsOnlyWhenUnderdamped()
        testSpringIsFrameRateIndependent()
        testSpringStaysStableOnLongFrames()
        testSpringIgnoresEmptyFrames()
        testSpring2RotateKeepsDistance()
        testGazeAtRest()
        testGazeDirections()
        testPupilStaysInsideTheEye()
        testGazeIsWide()
        testPointerCurve()
        testFootTapLift()
        testStretchAmount()
        testDance()
        testFrameDelta()
        print("KlayMotion: all cases passed")
    }

    static func close(_ a: CGFloat, _ b: CGFloat, _ eps: CGFloat = 1e-6) -> Bool { abs(a - b) <= eps }

    /// Runs a spring from 0 to 1 at `hz` for `seconds`; returns the value at the end and the peak.
    static func run(hz: Double, seconds: Double, response: CGFloat, damping: CGFloat) -> (value: CGFloat, peak: CGFloat, velocity: CGFloat) {
        var s = KlaySpring(value: 0)
        var peak: CGFloat = 0
        let frames = Int((seconds * hz).rounded())
        for _ in 0..<frames {
            s.step(towards: 1, dt: 1 / hz, response: response, damping: damping)
            peak = max(peak, s.value)
        }
        return (s.value, peak, s.velocity)
    }

    // MARK: - Springs

    static func testSpringSettles() {
        let r = run(hz: 60, seconds: 2, response: KlayMotion.hand.response, damping: KlayMotion.hand.damping)
        precondition(close(r.value, 1, 1e-3), "a hand spring must settle on its target within 2 s (got \(r.value))")
        precondition(abs(r.velocity) < 0.01, "a settled spring must be at rest (velocity \(r.velocity))")
    }

    static func testSpringOvershootsOnlyWhenUnderdamped() {
        let hand = run(hz: 60, seconds: 1, response: KlayMotion.hand.response, damping: KlayMotion.hand.damping)
        precondition(hand.peak > 1.1, "hands overshoot their pose (inertia), peak \(hand.peak)")
        precondition(hand.peak < 1.35, "the overshoot stays small, peak \(hand.peak)")
        let critical = run(hz: 60, seconds: 1, response: 0.3, damping: 1)
        precondition(critical.peak <= 1 + 1e-6, "a critically damped spring never overshoots, peak \(critical.peak)")
    }

    static func testSpringIsFrameRateIndependent() {
        // Same spring, same 0.5 s, at 30, 60, 120 and 144 Hz: the same motion.
        let c = KlayMotion.hand
        let ref = run(hz: 120, seconds: 0.25, response: c.response, damping: c.damping).value
        for hz in [30.0, 60.0, 144.0] {
            let v = run(hz: hz, seconds: 0.25, response: c.response, damping: c.damping).value
            precondition(close(v, ref, 0.01), "the spring must not depend on the frame rate: \(hz) Hz gives \(v), 120 Hz \(ref)")
        }
    }

    static func testSpringStaysStableOnLongFrames() {
        // The stiffest spring (feet) on frames at the 0.05 s cap: no blow-up.
        let f = KlayMotion.foot
        let r = run(hz: 20, seconds: 3, response: f.response, damping: f.damping)
        precondition(close(r.value, 1, 1e-3), "a long frame must not destabilise the spring (got \(r.value))")
    }

    static func testSpringIgnoresEmptyFrames() {
        var s = KlaySpring(value: 0.3, velocity: 2)
        s.step(towards: 1, dt: 0, response: 0.2, damping: 0.5)
        s.step(towards: 1, dt: -0.1, response: 0.2, damping: 0.5)
        s.step(towards: 1, dt: .nan, response: 0.2, damping: 0.5)
        precondition(s.value == 0.3 && s.velocity == 2, "a frame with no time must not move the spring")
        // A pause (huge or infinite dt) counts as KlayMotion.maxDt: no hang, no crash.
        var a = KlaySpring(value: 0)
        a.step(towards: 1, dt: .infinity, response: 0.2, damping: 0.5)
        var b = KlaySpring(value: 0)
        b.step(towards: 1, dt: KlayMotion.maxDt, response: 0.2, damping: 0.5)
        precondition(a == b && a.value.isFinite, "a pause counts as maxDt")
    }

    static func testSpring2RotateKeepsDistance() {
        var p = KlaySpring2(CGPoint(x: 100, y: 0))
        p.rotate(about: CGPoint(x: 0, y: 227), by: 0.1)
        let d = hypot(p.point.x, p.point.y - 227)
        precondition(close(d, hypot(100, 227), 1e-6), "a turn keeps the distance to the pivot")
        p.shift(dx: 5, dy: -3)
        precondition(close(hypot(p.point.x - 5, p.point.y + 3 - 227), hypot(100, 227), 1e-6), "a shift moves the point as a whole")
    }

    // MARK: - Gaze

    static func testGazeAtRest() {
        let g = KlayMotion.gaze(yaw: 0, pitch: 0)
        precondition(g.eye == .zero && g.pupil == .zero, "no gaze, no offset")
        precondition(g.spacing == 1 && g.squeeze(side: -1) == 1 && g.squeeze(side: 1) == 1, "no gaze, round eyes")
    }

    static func testGazeDirections() {
        let right = KlayMotion.gaze(yaw: 0.5, pitch: 0)
        precondition(right.eye.x > 0 && right.pupil.x > 0, "looking right moves the eyes and pupils right")
        precondition(right.squeeze(side: 1) < 1 && right.squeeze(side: -1) == 1, "the eye on the side he turns to narrows")
        precondition(right.spacing < 1, "turning brings the eyes closer")
        let up = KlayMotion.gaze(yaw: 0, pitch: 0.5)
        precondition(up.eye.y < 0 && up.pupil.y < 0, "pitch > 0 looks up (y down in the drawing)")
        let left = KlayMotion.gaze(yaw: -0.5, pitch: -0.5)
        precondition(left.eye.x < 0 && left.eye.y > 0, "looking down-left moves the eyes down-left")
        precondition(left.squeeze(side: -1) < 1 && left.squeeze(side: 1) == 1, "the left eye narrows when he turns left")
    }

    static func testPupilStaysInsideTheEye() {
        // KlayPaint: eye radius 52, rim 9; the widest pupil ("wide") is 33 × 1.16 by 52 × 1.12.
        let inner: CGFloat = 52 - 9 / 2
        let halfW: CGFloat = 33 * 1.16 / 2
        let halfH: CGFloat = 52 * 1.12 / 2
        precondition(KlayMotion.Eyes.pupilMaxX + halfW <= inner, "the pupil's horizontal travel fits inside the white")
        precondition(KlayMotion.Eyes.pupilMaxY + halfH <= inner, "the pupil's vertical travel fits inside the white")
        var yaw: CGFloat = -1
        while yaw <= 1 {
            var pitch: CGFloat = -1
            while pitch <= 1 {
                let g = KlayMotion.gaze(yaw: yaw, pitch: pitch)
                let e = hypot(g.pupil.x / KlayMotion.Eyes.pupilMaxX, g.pupil.y / KlayMotion.Eyes.pupilMaxY)
                precondition(e <= 1 + 1e-9, "the pupil stays inside its ellipse at yaw \(yaw), pitch \(pitch)")
                pitch += 0.125
            }
            yaw += 0.125
        }
        let far = KlayMotion.gaze(yaw: 5, pitch: -5)
        precondition(far == KlayMotion.gaze(yaw: 1, pitch: -1), "yaw and pitch are clamped to ±1")
    }

    static func testGazeIsWide() {
        // The pointer's widest look (yaw 0.62, pitch 0.5): the pupil travels at least 40 units
        // sideways and 20 up (the old gaze moved it 16.8 and 14.4).
        let g = KlayMotion.gaze(yaw: KlayMotion.yawRange, pitch: KlayMotion.pitchRange)
        precondition(g.eye.x + g.pupil.x >= 40, "the gaze must be wide sideways (\(g.eye.x + g.pupil.x))")
        precondition(-(g.eye.y + g.pupil.y) >= 20, "the gaze must be wide upwards (\(-(g.eye.y + g.pupil.y)))")
    }

    static func testPointerCurve() {
        precondition(KlayMotion.pointerCurve(0) == 0, "0 maps to 0")
        precondition(close(KlayMotion.pointerCurve(1), 1) && close(KlayMotion.pointerCurve(-1), -1), "±1 map to ±1")
        precondition(close(KlayMotion.pointerCurve(3), 1), "the curve is clamped")
        precondition(KlayMotion.pointerCurve(0.1) > 0.15, "small moves near Klay are amplified")
        var last: CGFloat = -2
        var l: CGFloat = -1
        while l <= 1 {
            let v = KlayMotion.pointerCurve(l)
            precondition(v > last, "the curve is monotonic")
            precondition(close(KlayMotion.pointerCurve(-l), -v), "the curve is odd")
            last = v
            l += 0.05
        }
    }

    // MARK: - Fidgets

    static func testFootTapLift() {
        let T = KlayMotion.Tap.self
        precondition(KlayMotion.footTapLift(0) == 0 && KlayMotion.footTapLift(T.dur) == 0, "the foot starts and ends down")
        var peak: CGFloat = 0
        var last: CGFloat = 0
        var ft = 0.0
        while ft <= T.dur + 0.1 {
            let v = KlayMotion.footTapLift(ft)
            precondition(v >= 0, "the foot never goes through the floor")
            precondition(abs(v - last) < 1, "the foot moves continuously (1 ms steps)")
            peak = max(peak, v)
            last = v
            ft += 0.001
        }
        precondition(peak > T.lift * 0.8 && peak <= T.lift, "the toe lifts by about \(T.lift) units (peak \(peak))")
    }

    static func testStretchAmount() {
        let S = KlayMotion.Stretch.self
        precondition(KlayMotion.stretchAmount(0) == 0 && KlayMotion.stretchAmount(S.dur) == 0, "the stretch starts and ends at rest")
        precondition(KlayMotion.stretchAmount((S.up + S.hold) / 2) == 1, "the stretch holds the pose")
        var last: CGFloat = 0
        var ft = 0.0
        while ft <= S.dur {
            let v = KlayMotion.stretchAmount(ft)
            precondition(v >= 0 && v <= 1, "the stretch amount stays within 0…1")
            precondition(abs(v - last) < 0.01, "the stretch moves continuously (1 ms steps)")
            if ft < S.up { precondition(v >= last, "up, the hands only rise") }
            if ft > S.hold { precondition(v <= last, "down, the hands only come down") }
            last = v
            ft += 0.001
        }
    }

    // MARK: - Dance, frame delta

    static func testDance() {
        let still = KlayMotion.dance(time: 12.34, level: 0)
        precondition(still.dx == 0 && still.dy == 0 && still.rot == 0 && still.sx == 1 && still.sy == 1,
                     "level 0 is no dance at all")
        var t = 0.0
        while t < 2 {
            let d = KlayMotion.dance(time: t, level: 1)
            precondition(d.dy <= 0 && d.dy >= -0.2, "the hop goes up, at most 0.2 R")
            precondition(abs(d.dx) <= 0.08 && abs(d.rot) <= 0.1, "the sway stays within 0.08 R and 0.1 rad")
            precondition(d.sx >= 1 && d.sy <= 1, "landing squashes")
            t += 0.01
        }
    }

    static func testFrameDelta() {
        precondition(close(KlayMotion.frameDelta(now: 100.016, last: 100), 0.016, 1e-9), "a normal frame keeps its length")
        precondition(KlayMotion.frameDelta(now: 100, last: 100.5) == 0, "a clock going back gives no time")
        precondition(KlayMotion.frameDelta(now: 200, last: 100) == 0.05, "a long pause is capped at 0.05 s")
    }
}
