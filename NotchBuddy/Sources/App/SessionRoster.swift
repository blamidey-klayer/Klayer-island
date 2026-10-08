import Foundation

// MARK: - Roster of the running Claude sessions
// One row per session, for the open island (spec §6). A pill carries one session at a time,
// the roster keeps them all: Claude Code sessions in several folders share one pill, so do
// the sessions of the Claude desktop app. Foundation only (tested by
// scripts/test-session-roster.sh, with HookRouting for the desktop pill): no AppKit, no
// BotState, the views map `SessionPhase`.

/// What a session is doing. Same raw values as `BotState`, for the phases a session reports.
enum SessionPhase: String, Equatable, CaseIterable {
    case idle, thinking, working, approval, question, ratelimit, error, finished

    /// The phase in plain French, as a row of the open island says it (spec §6).
    var label: String {
        switch self {
        case .idle:      return "En attente"
        case .thinking:  return "Réfléchit"
        case .working:   return "Travaille"
        case .approval:  return "Attend ton accord"
        case .question:  return "Te pose une question"
        case .ratelimit: return "Limite atteinte"
        case .error:     return "Erreur"
        case .finished:  return "Terminé"
        }
    }
}

/// One running session. `id` is the hook's session id, `pillId` the pill that routes it,
/// `title` the project folder name, `lastAction` one short line (empty until there is one),
/// `hostBundleId` the app the session runs in (a terminal or an editor), nil when unknown.
struct SessionRow: Equatable, Identifiable {
    let id: String
    var pillId: String
    var title: String
    var phase: SessionPhase
    var lastAction: String
    var updatedAt: Date
    var hostBundleId: String? = nil
}

/// What a click on a row of the open island opens.
enum SessionOpenTarget: Equatable {
    /// The Claude app (`claude://`).
    case claudeApp
    /// The running app the session runs in, brought forward.
    case host(bundleId: String)
}

extension SessionRow {
    /// A session of the Claude app opens the Claude app. A Claude Code session brings forward the
    /// terminal or editor it runs in, when that app is still running (`running`: the bundle ids
    /// of the running apps), and the Claude app otherwise.
    func openTarget(running: Set<String>) -> SessionOpenTarget {
        if pillId != HookRouting.desktopPillId, let host = hostBundleId, running.contains(host) {
            return .host(bundleId: host)
        }
        return .claudeApp
    }
}

/// The sessions seen by the hooks, most recent activity first. A value type: AppState owns the
/// instance on the main actor. Nothing here reads the clock, callers pass the date, and nothing
/// runs on a timer: AppState prunes on every update, so a hidden island costs no CPU.
struct SessionRoster {
    /// Longest `lastAction`, in characters.
    static let lastActionLimit = 80
    /// A finished, failed or idle session with no activity for this long leaves the roster.
    static let endedLifetime: TimeInterval = 30 * 60
    /// Any other session with no activity for this long leaves too (it ended without telling us),
    /// except a session waiting for an answer.
    static let silentLifetime: TimeInterval = 2 * 60 * 60

    /// Most recent activity first. At equal dates the latest `update` comes first.
    private(set) var rows: [SessionRow] = []

    /// Creates or updates the row of `sessionId` and moves it to the top. A nil `lastAction`
    /// keeps the previous one (empty for a new row); a given one is cut to 80 characters. A nil
    /// `hostBundleId` keeps the host the session had (none for a new row).
    mutating func update(sessionId: String, pillId: String, title: String, phase: SessionPhase,
                         lastAction: String?, hostBundleId: String? = nil, at date: Date) {
        let previous = rows.first { $0.id == sessionId }
        let action: String
        if let lastAction {
            action = String(lastAction.prefix(Self.lastActionLimit))
        } else {
            action = previous?.lastAction ?? ""
        }
        rows.removeAll { $0.id == sessionId }
        let row = SessionRow(id: sessionId, pillId: pillId, title: title, phase: phase,
                             lastAction: action, updatedAt: date,
                             hostBundleId: hostBundleId ?? previous?.hostBundleId)
        rows.insert(row, at: rows.firstIndex { $0.updatedAt <= date } ?? rows.count)
    }

    /// Removes the row of a session that ended. Unknown ids change nothing.
    mutating func end(sessionId: String) {
        rows.removeAll { $0.id == sessionId }
    }

    /// Removes the rows nobody needs any more: a `finished`, `error` or `idle` row after 30 minutes
    /// without activity, any other row after 2 hours, never an `approval` or a `question` (the
    /// user is still expected to answer). The age counts from the row's last update, a row is
    /// pruned once it reaches the limit.
    mutating func prune(now: Date) {
        rows.removeAll { row in
            let silence = now.timeIntervalSince(row.updatedAt)
            switch row.phase {
            case .approval, .question:
                return false
            case .finished, .error, .idle:
                return silence >= Self.endedLifetime
            case .thinking, .working, .ratelimit:
                return silence >= Self.silentLifetime
            }
        }
    }

    /// The `limit` most recent rows, nothing for a limit of 0 or less. Does not remove anything.
    func visible(limit: Int) -> [SessionRow] {
        Array(rows.prefix(max(0, limit)))
    }

    /// A text as the one line of a row: line breaks and tabs become one space, and a text longer
    /// than 80 characters is cut to 79 followed by « … », so `update` keeps it whole. Nil when
    /// nothing is left, so the row keeps its last action.
    static func line(_ text: String) -> String? {
        let collapsed = text.split(whereSeparator: { $0.isNewline || $0 == "\t" })
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        guard !collapsed.isEmpty else { return nil }
        return collapsed.count > lastActionLimit
            ? String(collapsed.prefix(lastActionLimit - 1)) + "…"
            : collapsed
    }

    /// The app a session runs in, from its hook event: the terminal the routing found (from the
    /// bundle id or TERM_PROGRAM), else the bundle id the hook reported (an editor, the Claude
    /// app), nil when there is none.
    static func host(routed: String?, bundleId: String) -> String? {
        if let routed { return routed }
        let trimmed = bundleId.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

// MARK: - What a finished session does to the island
// Spec §4: when Claude finishes a session the island opens on its end, and on an error (Stop and
// StopFailure). It must not take over what the user is doing, so the decision is made here, in
// plain values (tested), and HookServer applies it.

enum FinishPresentation: Equatable {
    /// The island opens, or switches, on the finished view of the pill.
    case open
    /// Only the pill is badged and the roster updated: the island, its view and its focus stay.
    case badgeOnly

    /// The raw values of `IslandView` that a finish may replace: nothing the user is in the
    /// middle of. Any other view (a draft in the chat or the mail, a file being sent, a result,
    /// Settings, a permission or a question, or a view added later) is kept.
    static let replaceableViews: Set<String> = [
        "overview", "empty", "note", "greeting", "confused", "finished", "error",
    ]

    /// `expanded`: the island is open. `view`: the raw value of the `IslandView` on screen.
    /// `pinned`: pinned with ⌘P. `requestPending`: a permission or a question waits.
    /// A waiting request is never covered. A hidden or compact island opens. An open island
    /// gives way only on a resting view, and not when pinned.
    static func decide(expanded: Bool, view: String, pinned: Bool, requestPending: Bool) -> FinishPresentation {
        if requestPending { return .badgeOnly }
        guard expanded else { return .open }
        return replaceableViews.contains(view) && !pinned ? .open : .badgeOnly
    }
}
