import Foundation

/// A Notification hook of Claude Code that says Claude waits for the user, and what the island does
/// with it (lot 6 spec §5). Foundation only, tested by scripts/test-code-notification.sh.
///
/// The input of a Notification hook (Claude Code hooks reference): the common fields, then
/// `message` (the notification text), an optional `title`, and `notification_type`, the type that
/// fired. The types that ask the user something:
/// - `permission_prompt`: Claude needs approval for a tool use. A session hosted by the Claude app
///   (the Agent SDK's `canUseTool`) sends it about 6 s after the request, and not at all when the
///   user or a PermissionRequest hook answered sooner;
/// - `idle_prompt`: Claude finished about 60 s ago and nothing was typed since;
/// - `elicitation_dialog`, `elicitation_url_dialog`: an MCP server asks the user a form or a URL.
/// The other types (`auth_success`, `elicitation_complete`, `elicitation_response`,
/// `agent_needs_input`, `agent_completed`, `quota_auto_resume_*`) ask the user nothing here.
/// Claude Code before `notification_type` sent the message only (« Claude needs your permission to
/// use Bash », « Claude is waiting for your input »): read as a fallback.
///
/// Only a session of the Claude app opens the island from a notification. The terminal does not
/// change: its notifications keep their earlier effect (the rate limit, a question in the text).
enum CodeNotification {
    /// What Claude asks of the user.
    enum Kind: Equatable {
        /// A tool use waits for the user's approval.
        case permission
        /// An MCP server waits for the user's answer (its form, or a URL to open).
        case waiting
        /// Claude finished its turn and waits for the next message (`idle_prompt`, about 60 s later).
        /// Told apart from `waiting` because the end of the turn may already have been shown by the
        /// finished view: the island then does not open a second time for it (`shouldOpen`).
        case idle
    }

    /// The request a notification carries, nil when it asks the user nothing. `notificationType`
    /// is the `notification_type` field, nil or blank for a Claude Code that does not send it: the
    /// message is then read. A type that is there decides, whatever the message says: a type the
    /// hooks reference does not list asks nothing.
    static func alert(message: String, notificationType: String?) -> Kind? {
        let type = (notificationType ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !type.isEmpty {
            switch type {
            case "permission_prompt":
                return .permission
            case "idle_prompt":
                return .idle
            case "elicitation_dialog", "elicitation_url_dialog":
                return .waiting
            default:
                return nil
            }
        }
        let lower = message.lowercased()
        if lower.contains("needs your permission") { return .permission }
        // The text older Claude Code sent for the idle prompt.
        if lower.contains("waiting for your input") { return .idle }
        return nil
    }

    /// Whether the notification opens the island on its session: only a session of the Claude app
    /// (`agent` is the `klayer_agent` of the event, "claude-desktop"), and only when no card of that
    /// session is held (`sessionHasCard`: its permission or its question is already on screen, or
    /// waits for the pointer). Never for the terminal, which sends no `klayer_agent`. An idle prompt
    /// after a finish that was shown (`currentPhase`, the phase the session's row has before the
    /// notification, is finished or failed, and `finishShown`: its finished or error view opened,
    /// `ShownFinishes`) opens nothing: the finished view was the notification. A finish that was only
    /// badged (the island was busy) was not shown: the idle prompt is its second chance and opens. A
    /// session with no row yet, or still running, was shown nothing, so it opens; so does a permission
    /// or an MCP server's form, whatever the row.
    static func shouldOpen(kind: Kind, sessionHasCard: Bool, agent: String, currentPhase: SessionPhase?,
                           finishShown: Bool) -> Bool {
        guard validateAgent(agent) != nil, !sessionHasCard else { return false }
        if kind == .idle, let currentPhase, currentPhase.isEnded, finishShown { return false }
        return true
    }

    /// Whether a card of session `sessionId` is held: its permission (`approvalSession`, the session
    /// of the pending approval, nil when none), or its question while one is pending
    /// (`questionPending`, with `questionSession`, the session that owns it: it may outlive the
    /// question, so it counts only while one is pending). What Claude asks is then already on screen
    /// or waiting for the pointer, and a tool that finishes does not answer it.
    static func holdsCard(sessionId: String, approvalSession: String?, questionPending: Bool,
                          questionSession: String?) -> Bool {
        approvalSession == sessionId || (questionPending && questionSession == sessionId)
    }

    /// The phase the session's row takes in the home's list, nil when the row stays as it is. A
    /// permission puts it on `approval`; Claude waiting (an MCP form, or idle) puts it on `question`,
    /// except a session that already ended (`current` finished or failed): that row stays in the
    /// day's history, grey, with its end time.
    static func rowPhase(for kind: Kind, current: SessionPhase?) -> SessionPhase? {
        switch kind {
        case .permission:
            return .approval
        case .waiting, .idle:
            if let current, current.isEnded { return nil }
            return .question
        }
    }
}


/// The sessions whose last end of turn the island showed: a Stop that opened the finished view, or a
/// StopFailure that opened the error view. A finish that was only badged (a card waited, the chat or
/// a mail draft was open, the island was pinned) was not shown, so the idle prompt that follows it
/// about 60 s later opens the note (`CodeNotification.shouldOpen`). The latest end of a session
/// decides. HookServer fills it; Foundation only, tested by scripts/test-code-notification.sh.
struct ShownFinishes: Equatable, Sendable {
    private(set) var sessions: Set<String> = []

    init() {}

    /// Session `sessionId` ended its turn; `shown`: its finished (or error) view opened.
    mutating func ended(_ sessionId: String, shown: Bool) {
        if shown { sessions.insert(sessionId) } else { sessions.remove(sessionId) }
    }

    /// The session left (SessionEnd): no idle prompt follows.
    mutating func forget(_ sessionId: String) {
        sessions.remove(sessionId)
    }

    /// Only the sessions the roster still has a row for (`ids`): the set never outgrows the day.
    mutating func keep(only ids: Set<String>) {
        sessions.formIntersection(ids)
    }

    func wasShown(_ sessionId: String) -> Bool {
        sessions.contains(sessionId)
    }
}
