import Foundation

/// Which sessions the island answers, and which pill owns their request.
///
/// Claude Code (no `klayer_agent`) and the Claude desktop app (`claude-desktop`) get their
/// permission and question cards in the island: the user answers there, or in the app's own
/// prompt, and whichever answer comes first applies. Any other agent is answered "ask" so it
/// keeps asking in its own window. Built on `ClaudeHookDetection.swift`, which holds the one
/// rule that tells the agents apart.
enum HookRouting {
    /// True when a request from this `klayer_agent` shows as a card in the island.
    static func handledInIsland(agent: String) -> Bool {
        !isUnrecognisedAgent(agent)
    }

    /// The pill that owns a request from this `klayer_agent`: the Claude desktop pill for a
    /// desktop session, the Claude Code workspace pill otherwise.
    static func pillId(agent: String) -> String {
        validateAgent(agent).map { "agent_\($0)" } ?? "integration_claude"
    }
}
