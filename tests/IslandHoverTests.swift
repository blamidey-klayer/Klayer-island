import Foundation

/// Hover-only island (spec §4): the pointer near the notch brings Klay out and greets,
/// resting on the notch opens the island after 250 ms, a click outside closes it.
/// no_click_api: nothing here calls `click()`, the island never opens on a click
/// (checked at compile time, the API no longer exists).
@main
enum IslandHoverTests {
    @MainActor
    static func main() async throws {
        let cases: [(String, @MainActor () async throws -> Void)] = [
            ("near_then_far_greets_once_and_never_opens", nearThenFarGreetsOnceAndNeverOpens),
            ("a_new_approach_greets_again", aNewApproachGreetsAgain),
            ("near_keeps_petit_on_screen", nearKeepsPetitOnScreen),
            ("approaching_a_compact_klay_greets_once_per_approach", approachingACompactKlayGreetsOncePerApproach),
            ("near_does_nothing_on_a_hidden_held_island", nearDoesNothingOnAHiddenHeldIsland),
            ("hover_opens_after_250ms", hoverOpensAfter250ms),
            ("leaving_before_250ms_cancels_opening", leavingBefore250msCancelsOpening),
            ("a_cancelled_opening_never_fires_later", aCancelledOpeningNeverFiresLater),
            ("hover_opened_folds_shortly_after_leaving", hoverOpenedFoldsShortlyAfterLeaving),
            ("coming_back_before_the_fold_keeps_it_open", comingBackBeforeTheFoldKeepsItOpen),
            ("click_inside_uses_the_normal_auto_close", clickInsideUsesTheNormalAutoClose),
            ("click_outside_closes", clickOutsideCloses),
            ("click_outside_with_pending_request_folds_to_petit", clickOutsideWithPendingRequestFoldsToPetit),
            ("click_outside_does_nothing_unless_open", clickOutsideDoesNothingUnlessOpen),
            ("click_outside_folds_a_held_greeting", clickOutsideFoldsAHeldGreeting),
            ("a_held_greeting_does_not_fold_on_its_own", aHeldGreetingDoesNotFoldOnItsOwn),
            ("pending_request_holds_the_island", pendingRequestHoldsTheIsland),
            ("hover_on_hidden_held_island_syncs_to_home", hoverOnHiddenHeldIslandSyncsToHome),
            ("finished_stays_until_hover_then_leave", finishedStaysUntilHoverThenLeave),
            ("a_finish_over_a_hover_opened_island_waits_for_a_new_hover", aFinishOverAHoverOpenedIslandWaitsForANewHover),
            ("a_compact_island_shown_by_the_app_hides_like_any_other", aCompactIslandShownByTheAppHidesLikeAnyOther),
            ("an_alert_during_the_greeting_leaves_the_greeting", anAlertDuringTheGreetingLeavesTheGreeting),
        ]
        for (name, run) in cases {
            try await run()
            print("  ok  \(name)")
        }
        print("Island open on hover: \(cases.count) cases passed")
    }

    // MARK: - Proximity

    @MainActor
    static func nearThenFarGreetsOnceAndNeverOpens() async throws {
        let m = IslandStateMachine()
        let log = Log(m)
        m.petitToHiddenDelay = 0.05
        m.pointerNear()
        precondition(m.state == .petit && log.greets == 1, "pointerNear must peek and greet")
        m.pointerNear()
        precondition(m.state == .petit && log.greets == 1, "same approach must not greet twice")
        m.pointerFar()
        try await waitFor(.hidden, m, timeout: 2)
        precondition(log.greets == 1)
        precondition(!log.states.contains(.home), "proximity must never open the island")
    }

    @MainActor
    static func aNewApproachGreetsAgain() async throws {
        let m = IslandStateMachine()
        let log = Log(m)
        m.petitToHiddenDelay = 0.05
        m.pointerNear()
        m.pointerFar()
        try await waitFor(.hidden, m, timeout: 2)
        m.pointerNear()
        precondition(m.state == .petit && log.greets == 2, "a new approach greets again")
    }

    @MainActor
    static func nearKeepsPetitOnScreen() async throws {
        let m = IslandStateMachine()
        let log = Log(m)
        m.petitToHiddenDelay = 0.05
        m.pointerNear()
        m.mouseEntered()
        m.mouseLeft()                                    // leaves the notch, still near it
        try await Task.sleep(for: .milliseconds(500))
        precondition(m.state == .petit, "Klay stays out while the pointer is near")
        m.hiddenExternally()
        m.reveal()                                       // a work event starts the hide timer, pointer still near
        try await Task.sleep(for: .milliseconds(300))
        precondition(m.state == .petit, "the hide timer must not fire while the pointer is near")
        m.pointerFar()
        try await waitFor(.hidden, m, timeout: 2)
        precondition(!log.states.contains(.home))
    }

    @MainActor
    static func approachingACompactKlayGreetsOncePerApproach() async throws {
        // Klay is already out (a work event revealed it): each approach waves again.
        let m = IslandStateMachine()
        let log = Log(m)
        m.reveal()
        precondition(m.state == .petit && log.greets == 0, "a work event peeks without a greeting")
        m.pointerNear()
        precondition(m.state == .petit && log.greets == 1, "approaching a compact Klay must greet")
        m.pointerNear()
        precondition(log.greets == 1, "same approach must not greet twice")
        m.pointerFar()
        m.pointerNear()
        precondition(m.state == .petit && log.greets == 2, "a new approach greets again")
        try await openByHover(m)
        m.pointerFar()
        m.pointerNear()                                  // a new approach while the island is open
        precondition(m.state == .home && log.greets == 2, "no greeting while the island is open")
        let g = IslandStateMachine()
        let glog = Log(g)
        g.launch()
        g.pointerNear()
        precondition(g.state == .klayer && glog.greets == 0, "no greeting during the launch greeting")
    }

    @MainActor
    static func nearDoesNothingOnAHiddenHeldIsland() async throws {
        // Hidden but held: the app expanded the island for a request without telling the
        // FSM, so an approach must not fold it to compact nor greet over it.
        let m = IslandStateMachine()
        let log = Log(m)
        m.isHeldOpen = { true }
        m.pointerNear()
        precondition(m.state == .hidden && log.states.isEmpty && log.greets == 0)
    }

    // MARK: - Hover opens

    @MainActor
    static func hoverOpensAfter250ms() async throws {
        let m = IslandStateMachine()
        m.mouseEntered()
        precondition(m.state == .petit, "hovering peeks at once")
        try await Task.sleep(for: .milliseconds(100))
        precondition(m.state == .petit, "opened before 250 ms")
        try await Task.sleep(for: .milliseconds(300))   // 0.4 s total
        precondition(m.state == .home, "state \(m.state) at 0.4 s, expected home")
    }

    @MainActor
    static func leavingBefore250msCancelsOpening() async throws {
        let m = IslandStateMachine()
        let log = Log(m)
        m.mouseEntered()
        try await Task.sleep(for: .milliseconds(100))
        m.mouseLeft()
        try await Task.sleep(for: .milliseconds(400))   // 0.5 s total
        precondition(m.state == .petit && !log.states.contains(.home), "leaving early must cancel the opening")
    }

    @MainActor
    static func aCancelledOpeningNeverFiresLater() async throws {
        let m = IslandStateMachine()
        m.mouseEntered()                                 // first opening due at 0.25 s
        m.mouseLeft()
        try await Task.sleep(for: .milliseconds(200))
        m.mouseEntered()                                 // second opening due at 0.45 s
        try await Task.sleep(for: .milliseconds(150))    // 0.35 s total
        precondition(m.state == .petit, "the cancelled first opening fired")
        try await waitFor(.home, m, timeout: 2)
    }

    // MARK: - Hover-opened island folds

    @MainActor
    static func hoverOpenedFoldsShortlyAfterLeaving() async throws {
        let m = IslandStateMachine()
        m.hoverCloseDelay = 0.3
        try await openByHover(m)
        m.mouseLeft()
        precondition(m.state == .home, "folds after the grace period, not at once")
        try await Task.sleep(for: .milliseconds(100))
        precondition(m.state == .home)
        try await waitFor(.petit, m, timeout: 2)
    }

    @MainActor
    static func comingBackBeforeTheFoldKeepsItOpen() async throws {
        let m = IslandStateMachine()
        m.hoverCloseDelay = 0.3
        try await openByHover(m)
        m.mouseLeft()
        m.mouseEntered()
        try await Task.sleep(for: .milliseconds(600))   // well past the 0.3 s grace period
        precondition(m.state == .home)
    }

    @MainActor
    static func clickInsideUsesTheNormalAutoClose() async throws {
        // A click inside turns it into a normal open island: the auto-close delay applies,
        // so typing in the chat after the pointer leaves does not fold it.
        let m = IslandStateMachine()
        m.hoverCloseDelay = 0.3
        m.homeToPetitDelay = 3
        try await openByHover(m)
        m.userInteracted()
        m.mouseLeft()
        try await Task.sleep(for: .milliseconds(800))   // past the hover grace, far from 3 s
        precondition(m.state == .home)
        m.homeToPetitDelay = 0.05
        try await waitFor(.petit, m, timeout: 2)
    }

    // MARK: - Click outside

    @MainActor
    static func clickOutsideCloses() async throws {
        let m = IslandStateMachine()
        let log = Log(m)
        m.pointerNear()
        try await openByHover(m)
        m.mouseLeft()
        m.clickedOutside()
        precondition(m.state == .hidden, "state \(m.state) after a click outside, expected hidden")
        m.pointerNear()                                  // same approach: no new peek, no new greeting
        precondition(m.state == .hidden && log.greets == 1)
    }

    @MainActor
    static func clickOutsideWithPendingRequestFoldsToPetit() async throws {
        let m = IslandStateMachine()
        m.isHeldOpen = { true }
        m.openedExternally()
        precondition(m.state == .home)
        m.clickedOutside()
        precondition(m.state == .petit, "a pending request folds to petit, not hidden")
        m.mouseEntered()
        precondition(m.state == .petit)
        try await Task.sleep(for: .milliseconds(400))
        precondition(m.state == .home, "hovering a held petit reopens it")
    }

    @MainActor
    static func clickOutsideDoesNothingUnlessOpen() async throws {
        // The click monitor only runs while the island is open, but a stray call must not
        // move a hidden or compact island, nor cut the launch greeting short.
        let m = IslandStateMachine()
        let log = Log(m)
        m.clickedOutside()
        precondition(m.state == .hidden && log.states.isEmpty, "a hidden island must stay hidden")
        m.reveal()
        m.clickedOutside()
        precondition(m.state == .petit && log.states == [.petit], "a compact island must stay compact")
        let g = IslandStateMachine()
        let glog = Log(g)
        g.launch()
        g.clickedOutside()
        precondition(g.state == .klayer && glog.states == [.klayer], "the launch greeting plays to its end")
    }

    @MainActor
    static func clickOutsideFoldsAHeldGreeting() async throws {
        // A request arrived during the launch greeting: a click outside folds it like any
        // open island holding a request, and hovering reopens it.
        let m = IslandStateMachine()
        m.isHeldOpen = { true }
        m.launch()
        m.openedExternally()                             // the request shows its card in place of the greeting
        precondition(m.state == .home, "state \(m.state): the card replaced the greeting, the FSM follows")
        m.clickedOutside()
        precondition(m.state == .petit, "state \(m.state) after a click outside a held greeting, expected petit")
        m.mouseEntered()
        try await waitFor(.home, m, timeout: 2)
    }

    @MainActor
    static func aHeldGreetingDoesNotFoldOnItsOwn() async throws {
        // A permission or a question arrived during the launch greeting: it stays open until
        // answered. Neither the end of the greeting nor a hover on it folds it.
        let m = IslandStateMachine()
        var pending = true
        m.isHeldOpen = { pending }
        m.greetAutoCollapseDelay = 0.05
        m.greetHoverCollapseDelay = 0.05
        m.launch()
        m.greetComplete()
        try await Task.sleep(for: .milliseconds(300))
        precondition(m.state == .klayer, "state \(m.state): the end of the greeting folded a held request")
        m.mouseEntered()
        try await Task.sleep(for: .milliseconds(300))
        precondition(m.state == .klayer, "state \(m.state): a hover folded a held request")
        pending = false                                  // answered: the greeting folds again
        m.mouseEntered()
        try await waitFor(.petit, m, timeout: 2)
    }

    // MARK: - Held and external openings

    @MainActor
    static func pendingRequestHoldsTheIsland() async throws {
        // Timers and pointer-leave never fold or hide an island holding a pending request.
        let m = IslandStateMachine()
        m.isHeldOpen = { true }
        m.hoverCloseDelay = 0.05
        m.homeToPetitDelay = 0.05
        m.petitToHiddenDelay = 0.05
        m.openedExternally()
        m.mouseEntered()
        m.userInteracted()
        m.mouseLeft()
        try await Task.sleep(for: .milliseconds(300))
        precondition(m.state == .home, "a held island must not fold")
        m.clickedOutside()
        m.pointerNear()
        m.pointerFar()
        m.mouseEntered()
        m.mouseLeft()                                    // starts the petit → hidden timer, pointer far
        try await Task.sleep(for: .milliseconds(300))
        precondition(m.state == .petit, "a held petit must not hide")
    }

    @MainActor
    static func hoverOnHiddenHeldIslandSyncsToHome() async throws {
        // The app expanded the island for a request without telling the FSM:
        // hovering syncs the state instead of folding it to petit.
        let m = IslandStateMachine()
        let log = Log(m)
        m.isHeldOpen = { true }
        m.mouseEntered()
        precondition(m.state == .home && log.states.isEmpty, "sync to home without a transition")
    }

    @MainActor
    static func finishedStaysUntilHoverThenLeave() async throws {
        let m = IslandStateMachine()
        m.openedExternally()
        m.mouseLeft()                                    // the pointer leaves without a hover since the opening
        try await Task.sleep(for: .seconds(1))
        precondition(m.state == .home, "an island opened by the app has no timer")
        m.mouseEntered()
        m.mouseLeft()
        try await Task.sleep(for: .milliseconds(300))
        precondition(m.state == .home, "folds after the 0.6 s grace period, not before")
        try await Task.sleep(for: .milliseconds(700))   // 1 s after leaving
        precondition(m.state == .petit, "state \(m.state) 1 s after hover then leave, expected petit")
    }

    @MainActor
    static func aFinishOverAHoverOpenedIslandWaitsForANewHover() async throws {
        // Opened by hovering the 220 pt home, pointer low on it. A session ends: HookServer opens the
        // finished view through hookExpand (openedExternally). The view is 160 pt tall, the pointer is
        // now below it: the pointer "leaves" without having seen the finish.
        let m = IslandStateMachine()
        m.hoverCloseDelay = 0.3
        try await openByHover(m)
        m.openedExternally()
        m.mouseLeft()
        try await Task.sleep(for: .milliseconds(800))   // well past the 0.3 s hover grace
        precondition(m.state == .home, "the finish must stay open after the island shrank under the pointer")
        // Seen, then left: it folds after the hover grace.
        m.mouseEntered()
        m.mouseLeft()
        try await waitFor(.petit, m, timeout: 2)
    }

    @MainActor
    static func aCompactIslandShownByTheAppHidesLikeAnyOther() async throws {
        // AppState used to turn hidden into compact on its own (a Claude app pill created or
        // removed) while the FSM stayed hidden: Klay then stayed out for good. The window
        // controller now syncs it: the FSM takes it as petit, with the 60 s hide timer.
        let m = IslandStateMachine()
        let log = Log(m)
        m.petitToHiddenDelay = 0.05
        m.shownExternally()
        precondition(m.state == .petit && log.states.isEmpty, "synced without a transition (mode is already compact)")
        try await waitFor(.hidden, m, timeout: 2)
        precondition(log.states == [.hidden], "it hides after the delay, got \(log.states)")

        // The pointer near the notch keeps it out until it goes away, as for any compact Klay.
        let n = IslandStateMachine()
        n.petitToHiddenDelay = 0.05
        n.pointerNear()
        n.hiddenExternally()
        n.shownExternally()
        try await Task.sleep(for: .milliseconds(300))
        precondition(n.state == .petit, "no hiding while the pointer is near")
        n.pointerFar()
        try await waitFor(.hidden, n, timeout: 2)

        // Only from hidden: an open island is left alone.
        let o = IslandStateMachine()
        o.openedExternally()
        o.shownExternally()
        precondition(o.state == .home)
    }

    @MainActor
    static func anAlertDuringTheGreetingLeavesTheGreeting() async throws {
        // A session finishes (or fails) in the first 4.6 s after launch: its view replaces the
        // greeting. The FSM used to stay in .klayer, so neither a click elsewhere nor Escape
        // closed it. It now follows the view: an island opened by the app.
        let m = IslandStateMachine()
        let log = Log(m)
        m.greetHoverCollapseDelay = 0.05
        m.launch()
        m.mouseEntered()                                 // a greeting collapse timer is running
        m.mouseLeft()
        m.launch()
        m.mouseEntered()
        m.openedExternally()
        precondition(m.state == .home, "state \(m.state) after an alert during the greeting, expected home")
        m.mouseLeft()
        try await Task.sleep(for: .milliseconds(300))
        precondition(m.state == .home, "the greeting's timers are gone and the view waits for a hover")
        m.greetComplete()                                // the greeting canvas left: its end changes nothing
        precondition(m.state == .home)
        m.clickedOutside()
        precondition(m.state == .hidden, "a click elsewhere closes it, got \(m.state)")
        precondition(log.states.last == .hidden)
    }

    // MARK: - Helpers

    /// Records transitions and greetings of one machine.
    @MainActor
    final class Log {
        var states: [IslandStateMachine.State] = []
        var greets = 0
        init(_ m: IslandStateMachine) {
            m.onTransition = { [weak self] _, to in self?.states.append(to) }
            m.onGreet = { [weak self] in self?.greets += 1 }
        }
    }

    @MainActor
    private static func openByHover(_ m: IslandStateMachine) async throws {
        m.mouseEntered()
        try await waitFor(.home, m, timeout: 2)
    }

    @MainActor
    private static func waitFor(_ s: IslandStateMachine.State, _ m: IslandStateMachine, timeout: TimeInterval) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while m.state != s && Date() < deadline { try await Task.sleep(for: .milliseconds(10)) }
        precondition(m.state == s, "state \(m.state) after \(timeout) s, expected \(s)")
    }
}
