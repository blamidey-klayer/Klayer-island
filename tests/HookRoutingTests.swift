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
}
