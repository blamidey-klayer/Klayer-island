import Foundation

/// The drop sequence (lot 6 spec §4): one Klay, the island's own, at his place of the Déposer
/// tab. He opens his arms when a file comes, follows it with his eyes and swallows it (squashed,
/// eyes shut), then the upload bar and the choice as before. No mailbox, no second figure.
/// The engine reads the wall clock from the moment the file enters: frames are asked at dates
/// counted from that moment.
@main
@MainActor
enum UploadSequenceTests {
    static func main() {
        let cases: [(String, @MainActor () -> Void)] = [
            ("klay_starts_where_the_drop_tab_draws_him", { klayStartsWhereTheDropTabDrawsHim() }),
            ("one_size_rule_for_the_island_and_the_canvas", { oneSizeRuleForTheIslandAndTheCanvas() }),
            ("the_text_sits_under_klay_inside_both_cards", { theTextSitsUnderKlayInsideBothCards() }),
            ("arms_open_and_eyes_widen_when_a_file_comes", { armsOpenAndEyesWidenWhenAFileComes() }),
            ("his_eyes_follow_the_file", { hisEyesFollowTheFile() }),
            ("he_blinks_while_the_file_hovers", { heBlinksWhileTheFileHovers() }),
            ("the_text_stays_while_he_follows_the_file", { theTextStaysWhileHeFollowsTheFile() }),
            ("a_file_that_leaves_lets_him_rest_again", { aFileThatLeavesLetsHimRestAgain() }),
            ("a_file_that_comes_back_finds_him_where_he_stands", { aFileThatComesBackFindsHimWhereHeStands() }),
            ("he_swallows_the_file_squashed_eyes_shut", { heSwallowsTheFileSquashedEyesShut() }),
            ("arms_back_at_rest_after_the_gulp", { armsBackAtRestAfterTheGulp() }),
            ("then_the_bar_and_the_choice", { thenTheBarAndTheChoice() }),
            ("a_long_pause_costs_one_short_frame", { aLongPauseCostsOneShortFrame() }),
        ]
        for (name, run) in cases {
            run()
            print("  ok  \(name)")
        }
        print("Upload sequence: \(cases.count) cases passed")
    }

    static let upload = IslandConst.viewLayouts[.upload]!

    /// The frame at `date` after the frames the display asks before it, 60 a second from `from`. The
    /// canvas's timeline asks one per frame of the screen, and since 0.3.6 one frame steps the springs
    /// through 0.1 s at most (`USC.MAX_CATCH_UP`): a test that follows Klay's moves asks its frames
    /// the same way.
    static func frame(_ e: UploadSequenceEngine, at date: Date, from: Date) -> USFrame {
        var t = from
        while date.timeIntervalSince(t) > 1.0 / 60 {
            _ = e.frame(at: t)
            t = t.addingTimeInterval(1.0 / 60)
        }
        return e.frame(at: date)
    }

    /// A fresh engine with a file that entered the island at (x, y), and the moment it entered.
    static func entered(x: CGFloat = 320, y: CGFloat = 70) -> (UploadSequenceEngine, Date) {
        let e = UploadSequenceEngine()
        let start = Date()
        e.enterZone(x: x, y: y)
        return (e, start)
    }

    // MARK: - One Klay, at the drop tab's place

    static func klayStartsWhereTheDropTabDrawsHim() {
        precondition(USC.REST_X == Double(upload.botX) && USC.REST_Y == Double(upload.botY ?? -1),
                     "the canvas Klay starts on the island's Klay of the Déposer tab")
        precondition(USC.D_KLAY == Double(upload.botDiameter), "at the same size")
        precondition(USC.REST_X == USC.CARD_X + USC.CARD_W / 2, "in the middle of the card")
        let (e, start) = entered()
        let f = e.frame(at: start)
        precondition(abs(f.x - USC.REST_X) < 0.5 && abs(f.y - USC.REST_Y) < 0.5 && f.d == USC.D_KLAY,
                     "no jump when the file enters: \(f.x), \(f.y), \(f.d)")
        precondition(f.arms < 0.05 && f.eye == .pill, "his arms still at rest, his eyes as in the tab")
    }

    /// BotPlacement draws the island's Klay in a canvas d / 0.6 wide, his glyph spanning 0.62 of it;
    /// the drop canvas draws his at KlayPaint.glyphScale(diameter:), built on the same rule.
    static func oneSizeRuleForTheIslandAndTheCanvas() {
        precondition(KlaySize.canvasWidth(diameter: 62) == 62 / 0.6 && KlaySize.glyphSpan == 0.62,
                     "Klay of diameter d: canvas d / 0.6, glyph 0.62 of its width")
    }

    static func theTextSitsUnderKlayInsideBothCards() {
        // The drag-over card spans island y 42…166, the Déposer tab's 98 pt card 55…153.
        precondition(USC.TEXT_Y > USC.REST_Y + 30, "under Klay (25 pt below his middle for 62 pt)")
        precondition(USC.TEXT_Y + 8 <= 153 - 8 && USC.TEXT_Y - 8 >= 55, "inside the smaller card, with a margin")
        precondition(USC.REST_Y - 26 >= 55 + 8, "Klay inside the smaller card too")
    }

    // MARK: - The file comes

    static func armsOpenAndEyesWidenWhenAFileComes() {
        let (e, start) = entered()
        let f = e.frame(at: start.addingTimeInterval(0.5))
        precondition(f.arms > 0.95 && f.arms <= 1.08, "arms open within 0.4 s: \(f.arms)")
        precondition(f.eye == .wide, "wide eyes for the file")
        precondition(f.fileVisible && f.suck == 0, "the file is still in the pointer")
    }

    static func hisEyesFollowTheFile() {
        let (right, r0) = entered(x: 560, y: 60)
        precondition(right.frame(at: r0.addingTimeInterval(0.05)).yaw > 0.3, "file on the right: he looks right")
        let (left, l0) = entered(x: 80, y: 60)
        precondition(left.frame(at: l0.addingTimeInterval(0.05)).yaw < -0.3, "file on the left: he looks left")
        let (above, a0) = entered(x: 320, y: 20)
        precondition(above.frame(at: a0.addingTimeInterval(0.05)).pitch > 0.1, "file above: he looks up")
        // The island Klay's rule (BotEngine), so his eyes stay put at the hand-over.
        let f = right.frame(at: r0.addingTimeInterval(0.05))
        let expected = KlayMotion.pointerCurve(CGFloat(tanh((560 - f.x) / 260))) * KlayMotion.yawRange
        precondition(abs(f.yaw - Double(expected)) < 1e-9, "yaw = pointerCurve(tanh(dx / 260)) × yawRange")
    }

    static func heBlinksWhileTheFileHovers() {
        let (e, start) = entered()
        precondition(e.frame(at: start.addingTimeInterval(1)).open == 1, "eyes open")
        precondition(e.frame(at: start.addingTimeInterval(3.53)).open < 0.2, "a blink every 3.6 s")
        precondition(e.frame(at: start.addingTimeInterval(3.7)).open == 1, "and open again")
    }

    static func theTextStaysWhileHeFollowsTheFile() {
        let (e, start) = entered(x: 560, y: 80)
        let f = frame(e, at: start.addingTimeInterval(1.5), from: start)
        precondition(f.x > USC.REST_X + 100, "he goes to catch the file: \(f.x)")
        precondition(f.textAlpha == 1 && f.zoneAlpha == 1, "« Dépose ton fichier » stays")
    }

    static func aFileThatLeavesLetsHimRestAgain() {
        let (e, start) = entered(x: 560, y: 60)
        let over = frame(e, at: start.addingTimeInterval(0.8), from: start)
        precondition(over.arms > 0.95 && over.eye == .wide && over.zoneOver, "arms open for the file")
        e.exitZone(at: start.addingTimeInterval(0.8))
        let leaving = frame(e, at: start.addingTimeInterval(0.9), from: start.addingTimeInterval(0.8))
        precondition(leaving.arms > 0.05 && leaving.arms < 0.95, "his arms come down, not at once: \(leaving.arms)")
        let left = frame(e, at: start.addingTimeInterval(1.2), from: start.addingTimeInterval(0.9))
        precondition(left.arms < 0.01, "arms at rest: \(left.arms)")
        precondition(left.eye == .pill && abs(left.yaw) < 1e-9 && abs(left.pitch) < 1e-9,
                     "eyes back to rest, looking ahead, not at the stale pointer")
        precondition(!left.zoneOver, "no green zone without a file")
        let rested = frame(e, at: start.addingTimeInterval(3.5), from: start.addingTimeInterval(1.2))
        precondition(abs(rested.x - USC.REST_X) < 2 && abs(rested.y - USC.REST_Y) < 2,
                     "back at his resting place: \(rested.x)")
        precondition(rested.textAlpha == 1, "the text stays")
    }

    static func aFileThatComesBackFindsHimWhereHeStands() {
        let (e, start) = entered(x: 560, y: 60)
        _ = frame(e, at: start.addingTimeInterval(1.0), from: start)
        e.exitZone(at: start.addingTimeInterval(1.0))
        let before = frame(e, at: start.addingTimeInterval(1.05), from: start.addingTimeInterval(1.0))
        precondition(before.x > USC.REST_X + 100, "he had gone to catch it: \(before.x)")
        e.enterZone(x: 100, y: 60)
        let after = e.frame(at: Date())
        precondition(abs(after.x - before.x) < 3, "no jump back to rest: \(before.x) → \(after.x)")
        precondition(after.zoneOver, "the file is over the island again")
    }

    // MARK: - The gulp

    static func dropped() -> (UploadSequenceEngine, Date) {
        let (e, start) = entered()
        _ = e.frame(at: start.addingTimeInterval(0.5))
        let drop = Date()
        e.performDrop(uploadDuration: 2.4)
        return (e, drop)
    }

    static func heSwallowsTheFileSquashedEyesShut() {
        let (e, drop) = dropped()
        let sucking = e.frame(at: drop.addingTimeInterval(USC.T_SUCK_START - USC.T_DROP + 0.15))
        precondition(sucking.suck > 0 && sucking.fileVisible, "the file goes into him")
        precondition(sucking.eye == .wide, "eyes wide on the file coming in")
        let gulp = e.frame(at: drop.addingTimeInterval(USC.T_SUCK_END - USC.T_DROP + 0.07))
        precondition(!gulp.fileVisible, "the file is gone")
        precondition(gulp.eye == .closed, "eyes shut while he swallows")
        precondition(gulp.sy < 0.9 && gulp.sx > 1.1, "squashed: \(gulp.sx) × \(gulp.sy)")
        precondition(gulp.d == USC.D_KLAY, "at his own size, where the mailbox was")
    }

    static func armsBackAtRestAfterTheGulp() {
        let (e, drop) = dropped()
        let f = e.frame(at: drop.addingTimeInterval(USC.T_CHEW1 - USC.T_DROP + 0.01))
        precondition(f.arms < 0.01, "arms down once swallowed: \(f.arms)")
        precondition(f.eye == .closed, "eyes still shut, savouring")
    }

    static func thenTheBarAndTheChoice() {
        let (e, drop) = dropped()
        let bar = e.frame(at: drop.addingTimeInterval(USC.T_PROG_START - USC.T_DROP + 1))
        precondition(bar.d == 14 && bar.y == USC.BAR_Y && bar.progress > 0, "a small Klay rides the bar")
        precondition(bar.zoneAlpha == 0, "the drop zone is gone")
        let choose = e.frame(at: drop.addingTimeInterval(e.growEnd - USC.T_DROP + 0.5))
        precondition(choose.chooseAlpha == 1 && choose.d == USC.CHOOSE_D, "Klay back at the choice")
        precondition(choose.arms == 0 && choose.eye == .pill, "as himself, arms at rest")
    }
}

extension UploadSequenceTests {
    // MARK: - A long pause (0.3.6)
    // A canvas left on screen across a long display sleep used to step its springs through the whole
    // pause at 240 steps a second on its next frame: 1.35 s of main thread for a day. One frame now
    // steps through 0.1 s at most.

    static func aLongPauseCostsOneShortFrame() {
        precondition(USC.catchUpStart(simT: 1.0, target: 1.0 + 1.0 / 60) == 1.0, "a frame at the display's rate: all of it")
        precondition(USC.catchUpStart(simT: 1.0, target: 1.1) == 1.0, "0.1 s: all of it")
        precondition(USC.catchUpStart(simT: 1.0, target: 86_401) == 86_401 - USC.MAX_CATCH_UP, "a day: its last 0.1 s")
        precondition(USC.catchUpStart(simT: 5.0, target: 4.0) == 5.0, "never back in time")

        let (e, start) = entered(x: 560, y: 60)
        let follow = frame(e, at: start.addingTimeInterval(0.5), from: start)
        let clock = Date()
        let late = e.frame(at: start.addingTimeInterval(86_400))
        let spent = Date().timeIntervalSince(clock)
        precondition(spent < 0.25, "the frame after a day's pause is short: \(spent) s")
        precondition(late.x.isFinite && late.y.isFinite, "Klay is somewhere: \(late.x), \(late.y)")
        precondition(abs(late.x - follow.x) < 60, "he goes on from where he was, no jump: \(follow.x) → \(late.x)")
    }
}

/// IslandTypes.swift (compiled here for `IslandConst`) names `EyeShape`, which BotEngine.swift
/// defines with SwiftUI. This stand-in lets it build with Foundation only.
enum EyeShape: Equatable {}
