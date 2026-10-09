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
        /// Claude waits for an answer or a next message (idle, or an MCP server's form).
        case waiting
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
            case "idle_prompt", "elicitation_dialog", "elicitation_url_dialog":
                return .waiting
            default:
                return nil
            }
        }
        let lower = message.lowercased()
        if lower.contains("needs your permission") { return .permission }
        if lower.contains("waiting for your input") { return .waiting }
        return nil
    }

    /// Whether the notification opens the island on its session: only a session of the Claude app
    /// (`agent` is the `klayer_agent` of the event, "claude-desktop"), and only when no card of that
    /// session is held (`sessionHasCard`: its permission or its question is already on screen, or
    /// waits for the pointer). Never for the terminal, which sends no `klayer_agent`.
    static func shouldOpen(kind: Kind, sessionHasCard: Bool, agent: String) -> Bool {
        validateAgent(agent) != nil && !sessionHasCard
    }

    /// The phase the session's row takes in the home's list, nil when the row stays as it is. A
    /// permission puts it on `approval`; Claude waiting puts it on `question`, except a session
    /// that already ended (`current` finished or failed): an idle prompt comes about 60 s after the
    /// end of a turn, and that row stays in the day's history, grey, with its end time.
    static func rowPhase(for kind: Kind, current: SessionPhase?) -> SessionPhase? {
        switch kind {
        case .permission:
            return .approval
        case .waiting:
            if let current, current.isEnded { return nil }
            return .question
        }
    }
}
