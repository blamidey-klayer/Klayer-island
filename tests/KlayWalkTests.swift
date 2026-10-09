import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// Klay's walk back into the island (KlayWalk.swift): the plan of the walk (how long from the
/// distance, where he is at each instant, the step phase, which way he faces), the gait (feet,
/// bob, arms as functions of the stride phase), the limbs it gives, where the walk ends and the
/// hop into the island. Mirror of tools/klay-preview/src/walk.ts.
@main
enum KlayWalkTests {
    static func main() {
        let cases: [(String, () -> Void)] = [
            ("duration_follows_the_distance_at_650_pt_per_second", durationFollowsTheDistance),
            ("duration_stays_between_0_7_and_2_2_s", durationStaysInItsBounds),
            ("no_walk_within_40_pt", noWalkWithin40Pt),
            ("he_starts_where_he_was_dropped_and_ends_at_the_doorstep", startsAtTheDropEndsAtTheDoorstep),
            ("he_walks_a_straight_line_never_backwards", walksAStraightLine),
            ("he_eases_in_on_the_first_step_and_out_on_the_last", easesInAndOut),
            ("even_speed_between_the_first_and_the_last_step", evenSpeedInBetween),
            ("two_and_a_half_steps_per_second", twoAndAHalfStepsPerSecond),
            ("he_faces_the_way_he_walks", facesTheWayHeWalks),
            ("one_foot_lifted_forward_while_the_other_pushes_back", oneFootLiftedWhileTheOtherPushes),
            ("the_feet_take_turns_never_both_in_the_air", feetTakeTurns),
            ("the_body_drops_on_contact_and_rises_mid_stride", bodyBobs),
            ("the_arms_swing_opposite_to_the_legs", armsSwingOppositeToTheLegs),
            ("the_gait_has_no_jump_and_repeats_every_stride", gaitIsContinuousAndPeriodic),
            ("standing_still_the_gait_is_the_rest_pose", standingStillIsRest),
            ("a_planted_foot_stays_put_while_the_body_bobs", plantedFootStaysPut),
            ("the_feet_step_the_way_he_faces", feetStepTheWayHeFaces),
            ("the_hands_come_in_and_up_from_their_rest", handsComeInAndUp),
            ("the_walk_ends_just_under_his_place_or_under_the_notch", doorstep),
            ("the_hop_rises_and_shrinks_into_his_place", hopIntoThePlace),
            ("the_hop_fades_only_into_a_hidden_place", hopFadesOnlyWhenHidden),
            ("the_hop_follows_the_walk", hopFollowsTheWalk),
        ]
        for (name, run) in cases {
            run()
            print("  ok  \(name)")
        }
        print("Klay walk: \(cases.count) cases passed")
    }

    static func close(_ a: CGFloat, _ b: CGFloat, _ eps: CGFloat = 1e-6) -> Bool { abs(a - b) <= eps }
    static func close(_ a: Double, _ b: Double, _ eps: Double = 1e-9) -> Bool { abs(a - b) <= eps }
    static func close(_ a: CGPoint, _ b: CGPoint, _ eps: CGFloat = 1e-6) -> Bool {
        abs(a.x - b.x) <= eps && abs(a.y - b.y) <= eps
    }

    /// A walk of `distance` points up and to the right (AppKit, y up).
    static func plan(_ distance: CGFloat, angle: CGFloat = .pi / 3) -> KlayWalk.Plan {
        let from = CGPoint(x: 300, y: 200)
        return KlayWalk.Plan(from: from, to: CGPoint(x: from.x + cos(angle) * distance,
                                                     y: from.y + sin(angle) * distance))
    }

    // MARK: - Plan

    static func durationFollowsTheDistance() {
        precondition(close(KlayWalk.duration(distance: 650), 1.0), "650 pt take 1 s")
        precondition(close(KlayWalk.duration(distance: 975), 1.5), "975 pt take 1.5 s")
        let p = plan(1040)
        precondition(close(p.duration, 1.6), "a 1 040 pt walk lasts 1.6 s, got \(p.duration)")
        precondition(close(1040 / p.duration, 650, 1e-6), "650 pt/s on average")
    }

    static func durationStaysInItsBounds() {
        precondition(close(KlayWalk.duration(distance: 100), 0.7), "a short walk still lasts 0.7 s")
        precondition(close(KlayWalk.duration(distance: 455), 0.7), "455 pt: exactly 0.7 s")
        precondition(close(KlayWalk.duration(distance: 1430), 2.2), "1 430 pt: exactly 2.2 s")
        precondition(close(KlayWalk.duration(distance: 5000), 2.2), "a long walk never lasts more than 2.2 s")
        for d in stride(from: CGFloat(41), through: 6000, by: 37) {
            let t = KlayWalk.duration(distance: d)
            precondition(t >= 0.7 && t <= 2.2, "\(d) pt: \(t) s is outside 0.7…2.2 s")
        }
    }

    static func noWalkWithin40Pt() {
        for d: CGFloat in [0, 10, 39.9, 40] {
            precondition(KlayWalk.duration(distance: d) == 0, "\(d) pt: no walk")
        }
        precondition(close(KlayWalk.duration(distance: 40.5), 0.7), "just over 40 pt: a short walk")
        let p = plan(30)
        precondition(p.duration == 0, "dropped 30 pt from the doorstep: no walk")
        precondition(close(p.position(at: 0), p.to), "he is at the doorstep at once, ready to hop")
        precondition(p.amount(at: 0) == 0 && p.pose(at: 0).amount == 0, "no gait without a walk")
        precondition(p.hopProgress(at: 0) == 0, "the hop starts at once")
    }

    static func startsAtTheDropEndsAtTheDoorstep() {
        let p = plan(800)
        precondition(close(p.position(at: 0), p.from), "the walk starts where he was dropped")
        precondition(close(p.position(at: -1), p.from), "before the start: where he was dropped")
        precondition(close(p.position(at: p.duration), p.to, 1e-6), "the walk ends at the doorstep")
        precondition(close(p.position(at: p.duration + 5), p.to), "after the end: at the doorstep")
    }

    static func walksAStraightLine() {
        let p = plan(1200, angle: 2.2)
        var last: CGFloat = -1
        for i in 0...200 {
            let t = p.duration * Double(i) / 200
            let k = p.progress(at: t)
            precondition(k >= last - 1e-12, "progress never goes back (\(t) s)")
            last = k
            let q = p.position(at: t)
            let cross = (q.x - p.from.x) * (p.to.y - p.from.y) - (q.y - p.from.y) * (p.to.x - p.from.x)
            precondition(abs(cross) < 1e-6 * 1200 * 1200, "on the straight line at \(t) s")
        }
    }

    static func easesInAndOut() {
        let p = plan(1300)   // 2 s
        let r = p.ramp
        precondition(close(r, 0.4), "speed rises over the first step (0.4 s), got \(r)")
        precondition(p.amount(at: 0) == 0 && p.amount(at: p.duration) == 0, "from standing, to standing")
        precondition(p.amount(at: 0.1) > 0 && p.amount(at: 0.1) < 0.5, "slow at first")
        precondition(close(p.amount(at: r), 1) && close(p.amount(at: 1), 1), "full speed after the first step")
        precondition(p.amount(at: p.duration - 0.1) < 0.5, "slowing down on the last step")
        // Speed at the very start and end is close to 0: a few ms move him almost nothing.
        let cruise = p.progress(at: 1.01) - p.progress(at: 1.0)
        precondition(p.progress(at: 0.01) < cruise * 0.05, "he starts from rest")
        precondition(1 - p.progress(at: p.duration - 0.01) < cruise * 0.05, "he ends at rest")
        // The ease is symmetric.
        for t in [0.05, 0.2, 0.37, 0.9] {
            precondition(close(p.progress(at: p.duration - t), 1 - p.progress(at: t), 1e-9),
                         "the last step mirrors the first (\(t) s)")
        }
        // A walk shorter than two steps eases in over its first half and out over its second.
        let short = plan(200)
        precondition(close(short.ramp, short.duration / 2), "0.7 s walk: ramps of 0.35 s")
        precondition(close(short.progress(at: short.duration / 2), 0.5, 1e-9), "halfway at mid-time")
    }

    static func evenSpeedInBetween() {
        let p = plan(1300)   // 2 s, ramps of 0.4 s
        let v1 = (p.progress(at: 0.6) - p.progress(at: 0.5)) / 0.1
        let v2 = (p.progress(at: 1.5) - p.progress(at: 1.4)) / 0.1
        precondition(close(v1, v2, 1e-9), "even speed between the first and the last step")
        precondition(close(v1, 1 / (p.duration - p.ramp), 1e-9), "the speed that covers the rest of the way")
    }

    static func twoAndAHalfStepsPerSecond() {
        let p = plan(1300)
        precondition(p.phase(at: 0) == 0, "the stride starts with the left foot's swing")
        // One step (half a stride) every 0.4 s.
        for t in [0.0, 0.13, 0.4, 0.71, 1.2] {
            let a = p.phase(at: t)
            let b = p.phase(at: t + 0.4)
            let d = (b - a + 1).truncatingRemainder(dividingBy: 1)
            precondition(close(d, 0.5, 1e-9), "a step every 0.4 s (at \(t) s: \(d))")
            precondition(a >= 0 && a < 1, "the phase stays within 0…1")
        }
        precondition(close(p.phase(at: 0.2), 0.25, 1e-9), "mid-swing of the left foot at 0.2 s")
        precondition(close(KlayWalk.cadence, 2.5), "2.5 steps per second")
    }

    static func facesTheWayHeWalks() {
        precondition(plan(500, angle: 0.3).facing == 1, "walking right: faces right")
        precondition(plan(500, angle: 2.5).facing == -1, "walking left: faces left")
        precondition(plan(500, angle: .pi / 2).facing == 1, "straight up: faces right")
        let h = plan(500, angle: 2.5).heading
        precondition(close(hypot(h.x, h.y), 1) && h.x < 0 && h.y > 0, "heading: a unit vector, up and left")
        let pose = plan(500, angle: 2.5).pose(at: 0.3)
        precondition(pose.facing == -1, "the pose carries the facing")
    }

    // MARK: - Gait

    static func oneFootLiftedWhileTheOtherPushes() {
        let g = KlayWalk.gait(phase: 0.25)
        precondition(close(g.lf.lift, KlayWalk.lift) && close(g.lf.fwd, KlayWalk.stride),
                     "a quarter in: the left foot is lifted forward")
        precondition(g.rf.lift == 0 && close(g.rf.fwd, -KlayWalk.stride * KlayWalk.push),
                     "while the right foot, on the ground, pushes back")
        let h = KlayWalk.gait(phase: 0.75)
        precondition(close(h.rf.lift, KlayWalk.lift) && close(h.rf.fwd, KlayWalk.stride),
                     "three quarters in: the right foot is lifted forward")
        precondition(h.lf.lift == 0 && h.lf.fwd < 0, "and the left one pushes back")
        precondition(KlayWalk.lift >= 60, "a lift that reads at the ghost's size")
    }

    static func feetTakeTurns() {
        for i in 0..<400 {
            let p = Double(i) / 400
            let g = KlayWalk.gait(phase: p)
            precondition(g.lf.lift == 0 || g.rf.lift == 0, "never both feet in the air (\(p))")
            if p > 0 && p < 0.5 { precondition(g.lf.lift > 0 && g.rf.lift == 0, "left swings first (\(p))") }
            if p > 0.5 { precondition(g.rf.lift > 0 && g.lf.lift == 0, "then the right (\(p))") }
        }
        for p in [0.0, 0.5] {
            let g = KlayWalk.gait(phase: p)
            precondition(close(g.lf.lift, 0, 1e-9) && close(g.rf.lift, 0, 1e-9), "both feet down on contact (\(p))")
        }
    }

    static func bodyBobs() {
        precondition(close(KlayWalk.gait(phase: 0).bob, KlayWalk.bob), "down on the contact at 0")
        precondition(close(KlayWalk.gait(phase: 0.5).bob, KlayWalk.bob, 1e-9), "down on the contact at ½")
        precondition(close(KlayWalk.gait(phase: 0.25).bob, -KlayWalk.bob, 1e-9), "up mid-stride at ¼")
        precondition(close(KlayWalk.gait(phase: 0.75).bob, -KlayWalk.bob, 1e-9), "up mid-stride at ¾")
        precondition(KlayWalk.bob > 0, "y down: a positive bob drops the body")
    }

    static func armsSwingOppositeToTheLegs() {
        // Left foot lifted: the right hand swings forward (in and up), the left one back.
        let g = KlayWalk.gait(phase: 0.25)
        precondition(close(g.rh.rise, KlayWalk.armRise) && close(g.rh.inward, KlayWalk.armIn),
                     "left foot up: right hand forward, in and up")
        precondition(g.lh.inward < 0 && g.lh.rise < g.rh.rise, "left hand back, out, lower")
        let h = KlayWalk.gait(phase: 0.75)
        precondition(close(h.lh.rise, KlayWalk.armRise) && h.rh.inward < 0, "right foot up: left hand forward")
        // Over the whole stride, each hand rises highest when the other side's foot is highest.
        for i in 0..<100 {
            let p = Double(i) / 100
            let k = KlayWalk.gait(phase: p)
            if k.lf.lift > 0 { precondition(k.rh.inward > 0 && k.lh.inward < 0, "right hand with the left foot (\(p))") }
            if k.rf.lift > 0 { precondition(k.lh.inward > 0 && k.rh.inward < 0, "left hand with the right foot (\(p))") }
        }
    }

    static func gaitIsContinuousAndPeriodic() {
        func dist(_ a: KlayWalk.Gait, _ b: KlayWalk.Gait) -> CGFloat {
            [a.lf.fwd - b.lf.fwd, a.lf.lift - b.lf.lift, a.rf.fwd - b.rf.fwd, a.rf.lift - b.rf.lift,
             a.lh.inward - b.lh.inward, a.lh.rise - b.lh.rise, a.rh.inward - b.rh.inward,
             a.rh.rise - b.rh.rise, a.bob - b.bob].map(abs).max()!
        }
        for i in 0..<1000 {
            let p = Double(i) / 1000
            precondition(dist(KlayWalk.gait(phase: p), KlayWalk.gait(phase: p + 0.001)) < 1,
                         "no jump at \(p)")
            precondition(dist(KlayWalk.gait(phase: p), KlayWalk.gait(phase: p + 1)) < 1e-6,
                         "the same every stride (\(p))")
            precondition(dist(KlayWalk.gait(phase: p), KlayWalk.gait(phase: p - 3)) < 1e-6,
                         "negative phases too (\(p))")
        }
    }

    static func standingStillIsRest() {
        for p in [0.0, 0.1, 0.25, 0.6, 0.75] {
            let g = KlayWalk.gait(phase: p, amount: 0)
            precondition([g.lf.fwd, g.lf.lift, g.rf.fwd, g.rf.lift, g.lh.inward, g.lh.rise,
                          g.rh.inward, g.rh.rise, g.bob].allSatisfy { $0 == 0 }, "amount 0: rest (\(p))")
            let half = KlayWalk.gait(phase: p, amount: 0.5)
            let full = KlayWalk.gait(phase: p)
            precondition(close(half.lf.lift, full.lf.lift / 2) && close(half.bob, full.bob / 2)
                         && close(half.rh.rise, full.rh.rise / 2), "the amount scales the gait (\(p))")
            let over = KlayWalk.gait(phase: p, amount: 3)
            precondition(close(over.bob, full.bob), "never more than the full gait")
        }
    }

    // MARK: - Limbs

    static let handRest = CGPoint(x: 168, y: 150)
    static let footRest = CGPoint(x: 36, y: 212)

    static func plantedFootStaysPut() {
        for i in 0..<100 {
            let p = Double(i) / 100
            let g = KlayWalk.gait(phase: p)
            let l = KlayWalk.limbs(g, facing: 1, handRest: handRest, footRest: footRest)
            // Drawn in a body moved down by `bob`, the foot's place on screen is y + bob.
            if g.lf.lift == 0 { precondition(close(l.lf.y + g.bob, footRest.y), "left foot stays on the ground (\(p))") }
            if g.rf.lift == 0 { precondition(close(l.rf.y + g.bob, footRest.y), "right foot stays on the ground (\(p))") }
        }
        let up = KlayWalk.limbs(KlayWalk.gait(phase: 0.25), facing: 1, handRest: handRest, footRest: footRest)
        let g = KlayWalk.gait(phase: 0.25)
        precondition(close(up.lf.y + g.bob, footRest.y - KlayWalk.lift), "the lifted foot rises by the lift")
    }

    static func feetStepTheWayHeFaces() {
        let g = KlayWalk.gait(phase: 0.25)
        let right = KlayWalk.limbs(g, facing: 1, handRest: handRest, footRest: footRest)
        let left = KlayWalk.limbs(g, facing: -1, handRest: handRest, footRest: footRest)
        precondition(close(right.lf.x, -footRest.x + KlayWalk.stride), "facing right, the lifted foot reaches right")
        precondition(close(left.lf.x, -footRest.x - KlayWalk.stride), "facing left, it reaches left")
        precondition(right.rf.x < footRest.x && left.rf.x > footRest.x, "the planted foot pushes the other way")
        precondition(close(right.lf.y, left.lf.y) && close(right.lh.x, left.lh.x),
                     "facing changes only where the feet step")
    }

    static func handsComeInAndUp() {
        let rest = KlayWalk.limbs(KlayWalk.gait(phase: 0.3, amount: 0), facing: 1, handRest: handRest, footRest: footRest)
        precondition(close(rest.lh, CGPoint(x: -168, y: 150)) && close(rest.rh, handRest)
                     && close(rest.lf, CGPoint(x: -36, y: 212)) && close(rest.rf, footRest),
                     "standing: hands and feet at rest")
        let l = KlayWalk.limbs(KlayWalk.gait(phase: 0.25), facing: 1, handRest: handRest, footRest: footRest)
        precondition(close(l.rh, CGPoint(x: handRest.x - KlayWalk.armIn, y: handRest.y - KlayWalk.armRise)),
                     "the forward hand comes in towards his middle and up")
        precondition(l.lh.x < -handRest.x && l.lh.y < handRest.y && l.lh.y > l.rh.y,
                     "the back hand goes out, a little up")
    }

    // MARK: - End of the walk, hop

    static func doorstep() {
        let w: CGFloat = 40 / 0.6
        // Open island: his place is below the notch; the walk ends rise × width under it.
        let open = KlayWalk.doorstep(place: CGPoint(x: 500, y: 851), notchBottom: 950, walkerWidth: w)
        precondition(close(open, CGPoint(x: 500, y: 851 - 0.3 * w)), "just under his place in the open island")
        // Closed island: his place is in the notch; the walk ends under the notch.
        let shut = KlayWalk.doorstep(place: CGPoint(x: 756, y: 966), notchBottom: 950, walkerWidth: w)
        precondition(close(shut, CGPoint(x: 756, y: 950 - 0.3 * w)), "just under the notch")
        // The walker's top (half his figure's height, 0.244 of his width) stays under it.
        precondition(950 - 0.3 * w + 0.244 * w < 950, "his head stays under the notch")
    }

    static func hopIntoThePlace() {
        let a = CGPoint(x: 700, y: 900)
        let b = CGPoint(x: 640, y: 966)
        let start = KlayWalk.hop(0, from: a, to: b, fromWidth: 67, toWidth: 33, fades: false)
        precondition(close(start.center, a) && close(start.width, 67) && start.alpha == 1, "from the doorstep, at his size")
        let end = KlayWalk.hop(1, from: a, to: b, fromWidth: 67, toWidth: 33, fades: false)
        precondition(close(end.center, b, 1e-9) && close(end.width, 33) && end.alpha == 1,
                     "into his place, at the island Klay's size")
        let mid = KlayWalk.hop(0.5, from: a, to: b, fromWidth: 67, toWidth: 33, fades: false)
        precondition(close(mid.center.y, (a.y + b.y) / 2 + KlayWalk.hopHeight, 1e-9), "a hop up, above the line")
        precondition(mid.width < 67 && mid.width > 33, "shrinking on the way")
        precondition(close(KlayWalk.hop(-1, from: a, to: b, fromWidth: 67, toWidth: 33, fades: false).center, a)
                     && close(KlayWalk.hop(2, from: a, to: b, fromWidth: 67, toWidth: 33, fades: false).center, b, 1e-9),
                     "outside 0…1 it holds its ends")
    }

    static func hopFadesOnlyWhenHidden() {
        let a = CGPoint(x: 700, y: 900)
        let b = CGPoint(x: 756, y: 966)
        precondition(KlayWalk.hop(0.5, from: a, to: b, fromWidth: 67, toWidth: 0, fades: true).alpha == 1,
                     "visible for most of the hop")
        precondition(KlayWalk.hop(1, from: a, to: b, fromWidth: 67, toWidth: 0, fades: true).alpha == 0,
                     "gone into the closed notch at the end")
        precondition(KlayWalk.hop(1, from: a, to: b, fromWidth: 67, toWidth: 33, fades: false).alpha == 1,
                     "into a shown place he never fades: the island Klay takes over")
    }

    static func hopFollowsTheWalk() {
        let p = plan(900)
        precondition(p.hopProgress(at: 0) == nil && p.hopProgress(at: p.duration - 0.01) == nil, "walking: no hop yet")
        precondition(p.hopProgress(at: p.duration) == 0, "the hop starts as the walk ends")
        precondition(close(p.hopProgress(at: p.duration + KlayWalk.hopDuration / 2)!, 0.5, 1e-9), "halfway")
        precondition(p.hopProgress(at: p.total + 3) == 1, "then he is home")
        precondition(close(p.total, p.duration + KlayWalk.hopDuration), "walk then hop")
        precondition(KlayWalk.hopDuration > 0.2 && KlayWalk.hopDuration < 0.5, "a small hop")
    }
}
