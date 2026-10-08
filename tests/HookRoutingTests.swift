import Foundation

/// Which sessions the island answers, and which pill owns their request (Task 10). Claude Code
/// (no `klayer_agent`) and the Claude desktop app (`claude-desktop`) both get their permission
/// and question cards in the island; any other agent is answered "ask" and keeps asking itself.
@main
enum HookRoutingTests {
    static func main() {
        let cases: [(String, () -> Void)] = [
            ("claude_code_is_handled_in_the_island", claudeCodeIsHandledInTheIsland),
            ("claude_desktop_is_handled_in_the_island", claudeDesktopIsHandledInTheIsland),
            ("another_agent_is_not_handled", anotherAgentIsNotHandled),
            ("an_unknown_name_is_not_handled", anUnknownNameIsNotHandled),
            ("claude_desktop_has_its_own_pill", claudeDesktopHasItsOwnPill),
            ("claude_code_uses_the_workspace_pill", claudeCodeUsesTheWorkspacePill),
            ("desktop_pill_id_is_the_routed_one", desktopPillIdIsTheRoutedOne),
            ("a_pill_with_nothing_waiting_may_be_removed", aPillWithNothingWaitingMayBeRemoved),
            ("a_pill_with_its_own_approval_waiting_stays", aPillWithItsOwnApprovalWaitingStays),
            ("a_pill_with_its_own_question_waiting_stays", aPillWithItsOwnQuestionWaitingStays),
            ("another_pills_card_does_not_keep_it", anotherPillsCardDoesNotKeepIt),
            ("another_session_never_acts_on_a_pill_under_its_question", anotherSessionNeverActsOnAPillUnderItsQuestion),
            ("the_question_owner_and_other_pills_go_on", theQuestionOwnerAndOtherPillsGoOn),
            ("a_card_keeps_its_pill_after_a_stop", aCardKeepsItsPillAfterAStop),
            ("a_pill_that_moved_on_is_left_alone_after_a_stop", aPillThatMovedOnIsLeftAloneAfterAStop),
            ("the_desktop_pill_waits_for_its_finished_view", theDesktopPillWaitsForItsFinishedView),
        ]
        for (name, run) in cases {
            run()
            print("  ok  \(name)")
        }
        print("Hook routing: \(cases.count) cases passed")
    }

    static func claudeCodeIsHandledInTheIsland() {
        precondition(HookRouting.handledInIsland(agent: ""),
                     "Claude Code sends no klayer_agent: its cards show in the island")
    }

    static func claudeDesktopIsHandledInTheIsland() {
        precondition(HookRouting.handledInIsland(agent: "claude-desktop"),
                     "the Claude desktop app shows its permissions and questions in the island")
    }

    static func anotherAgentIsNotHandled() {
        precondition(!HookRouting.handledInIsland(agent: "codex"),
                     "an agent Klayer Island no longer follows keeps asking in its own window")
    }

    static func anUnknownNameIsNotHandled() {
        precondition(!HookRouting.handledInIsland(agent: "x"))
        // Near misses of the desktop tag are not the desktop tag
        for near in ["Claude-Desktop", "claude", "claude-desktop2", " claude-desktop"] {
            precondition(!HookRouting.handledInIsland(agent: near), "\(near) must not be handled")
        }
    }

    static func claudeDesktopHasItsOwnPill() {
        precondition(HookRouting.pillId(agent: "claude-desktop") == "agent_claude-desktop")
    }

    static func claudeCodeUsesTheWorkspacePill() {
        precondition(HookRouting.pillId(agent: "") == "integration_claude")
        // Never a pill of its own for an agent the island does not follow
        precondition(HookRouting.pillId(agent: "codex") == "integration_claude")
    }

    static func desktopPillIdIsTheRoutedOne() {
        precondition(HookRouting.desktopPillId == HookRouting.pillId(agent: "claude-desktop"))
        precondition(HookRouting.desktopPillId == "agent_claude-desktop",
                     "the pill ID is a stable contract value (Keychain, preferences, hook routing)")
    }

    // All sessions of the Claude app share one pill: a Stop (5.2 s later) or a SessionEnd of one
    // session must not remove the pill while a card of another session waits on it.
    static func aPillWithNothingWaitingMayBeRemoved() {
        precondition(HookRouting.mayRemovePill(HookRouting.desktopPillId,
                                               pendingApprovalPill: nil, pendingQuestionPill: nil))
    }

    static func aPillWithItsOwnApprovalWaitingStays() {
        precondition(!HookRouting.mayRemovePill(HookRouting.desktopPillId,
                                                pendingApprovalPill: HookRouting.desktopPillId,
                                                pendingQuestionPill: nil))
    }

    static func aPillWithItsOwnQuestionWaitingStays() {
        precondition(!HookRouting.mayRemovePill(HookRouting.desktopPillId,
                                                pendingApprovalPill: nil,
                                                pendingQuestionPill: HookRouting.desktopPillId))
        // Both kinds of card waiting on it, same answer
        precondition(!HookRouting.mayRemovePill(HookRouting.desktopPillId,
                                                pendingApprovalPill: HookRouting.desktopPillId,
                                                pendingQuestionPill: HookRouting.desktopPillId))
    }

    static func anotherPillsCardDoesNotKeepIt() {
        let claudeCode = HookRouting.pillId(agent: "")
        precondition(HookRouting.mayRemovePill(HookRouting.desktopPillId,
                                               pendingApprovalPill: claudeCode,
                                               pendingQuestionPill: claudeCode),
                     "a card waiting on the Claude Code pill does not hold the desktop pill")
        precondition(!HookRouting.mayRemovePill(claudeCode,
                                                pendingApprovalPill: claudeCode,
                                                pendingQuestionPill: nil))
    }

    // MARK: - A question card keeps its pill (review M4)

    static func anotherSessionNeverActsOnAPillUnderItsQuestion() {
        // Two Claude app sessions share the desktop pill; A asks a question. B's PreToolUse,
        // UserPromptSubmit or Stop must not put the pill on working, rename it, or open a view
        // over the card: B's row is updated, the pill only badged for an end of turn.
        let desktop = HookRouting.desktopPillId
        precondition(!HookRouting.eventReachesPill(desktop, sessionId: "B",
                                                   questionPill: desktop, questionSession: "A"))
        let claudeCode = HookRouting.pillId(agent: "")
        precondition(!HookRouting.eventReachesPill(claudeCode, sessionId: "term-2",
                                                   questionPill: claudeCode, questionSession: "term-1"),
                     "two terminal sessions share the Claude Code pill the same way")
    }

    static func theQuestionOwnerAndOtherPillsGoOn() {
        let desktop = HookRouting.desktopPillId
        precondition(HookRouting.eventReachesPill(desktop, sessionId: "A",
                                                  questionPill: desktop, questionSession: "A"),
                     "the session that owns the question goes on")
        precondition(HookRouting.eventReachesPill(HookRouting.pillId(agent: ""), sessionId: "B",
                                                  questionPill: desktop, questionSession: "A"),
                     "another pill is not held by the question")
        precondition(HookRouting.eventReachesPill(desktop, sessionId: "B", questionPill: nil, questionSession: nil),
                     "no question waiting: every event goes on")
    }

    // MARK: - 5.2 s after a Stop (ledger, Tasks 10 and 11a)

    static func aCardKeepsItsPillAfterAStop() {
        // The Claude Code pill used to go back to idle under a card that came in since the Stop:
        // Klay lost the request's pose. Same guard as the desktop pill.
        precondition(HookRouting.stopCleanup(removesPill: false, cardWaits: true, showingFinished: false,
                                             stillFinished: true) == .keep)
        precondition(HookRouting.stopCleanup(removesPill: true, cardWaits: true, showingFinished: true,
                                             stillFinished: true) == .keep)
    }

    static func aPillThatMovedOnIsLeftAloneAfterAStop() {
        // Another session of the Claude app started on the shared pill before the first tick: it
        // must not be removed under it (before, only the repeats checked).
        precondition(HookRouting.stopCleanup(removesPill: true, cardWaits: false, showingFinished: false,
                                             stillFinished: false) == .keep)
        // A new turn of Claude Code started within 5.2 s: it is not put back on idle.
        precondition(HookRouting.stopCleanup(removesPill: false, cardWaits: false, showingFinished: false,
                                             stillFinished: false) == .keep)
        precondition(HookRouting.stopCleanup(removesPill: true, cardWaits: false, showingFinished: false,
                                             stillFinished: true) == .remove)
        precondition(HookRouting.stopCleanup(removesPill: false, cardWaits: false, showingFinished: true,
                                             stillFinished: true) == .idle,
                     "the Claude Code pill goes idle even under the finished view, which reads its session")
    }

    static func theDesktopPillWaitsForItsFinishedView() {
        precondition(HookRouting.stopCleanup(removesPill: true, cardWaits: false, showingFinished: true,
                                             stillFinished: true) == .again)
        precondition(HookRouting.stopCleanup(removesPill: true, cardWaits: false, showingFinished: true,
                                             stillFinished: false) == .again,
                     "the view on screen still needs its pill")
    }
}
