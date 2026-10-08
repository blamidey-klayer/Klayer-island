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
}
