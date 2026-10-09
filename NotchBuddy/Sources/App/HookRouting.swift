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

    /// The pill of the Claude desktop app: "agent_claude-desktop". All its sessions share it.
    static let desktopPillId = pillId(agent: "claude-desktop")

    /// The Claude desktop app's bundle id: what « Ouvrir Claude » opens, and the app whose Chat and
    /// Cowork the island follows (ClaudeAppWatcher).
    static let desktopBundleId = "com.anthropic.claudefordesktop"

    /// False while a card of this pill waits for an answer. Removing the pill then resets the
    /// focus and leaves the card without its session, which happens when a Stop (5.2 s later)
    /// or a SessionEnd of one Claude app session reaches the pill all its sessions share. The
    /// pill goes on its next event.
    static func mayRemovePill(_ pillId: String, pendingApprovalPill: String?,
                              pendingQuestionPill: String?) -> Bool {
        pillId != pendingApprovalPill && pillId != pendingQuestionPill
    }

    /// What the 5.2 s timer after a Stop does to the pill of that session.
    enum StopCleanup: Equatable {
        /// The pill stays as it is: a card of that pill waits, or it moved on to another turn.
        case keep
        /// Look again 5.2 s later: the finished view on screen still tells about a session of it.
        case again
        /// The Claude Code pill goes back to idle, its badge cleared.
        case idle
        /// The Claude app pill goes away.
        case remove
    }

    /// `removesPill`: the Claude app pill, which goes away (the Claude Code pill only goes idle).
    /// `cardWaits`: a permission or question card of that pill waits. `showingFinished`: the open
    /// island shows the finished view of a session of that pill. `stillFinished`: the pill is still
    /// on finished (no other turn started on it since the Stop), checked from the first tick on.
    static func stopCleanup(removesPill: Bool, cardWaits: Bool, showingFinished: Bool,
                            stillFinished: Bool) -> StopCleanup {
        if cardWaits { return .keep }
        if removesPill {
            if showingFinished { return .again }
            return stillFinished ? .remove : .keep
        }
        return stillFinished ? .idle : .keep
    }

    /// Whether an event of session `sessionId` may act on its pill `pillId` (its state, its name
    /// and steps, the focus, a view it opens) while a question card may wait (`questionPill`,
    /// `questionSession`, nil when none). Not when the card waits on that pill for another session:
    /// that event only updates its own row (and badges the pill for an end of turn), so the pill
    /// keeps the question's pose and name under the card, as it does under a permission card. The
    /// session that owns the question, and the other pills, go on.
    static func eventReachesPill(_ pillId: String, sessionId: String,
                                 questionPill: String?, questionSession: String?) -> Bool {
        guard let questionPill, let questionSession, pillId == questionPill else { return true }
        return sessionId == questionSession
    }
}
