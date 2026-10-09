import Foundation

// MARK: - Roster of the running Claude sessions
// One row per session, for the open island (spec §6). A pill carries one session at a time,
// the roster keeps them all: Claude Code sessions in several folders share one pill, so do
// the sessions of the Claude desktop app. The sessions that finished or failed today stay, in
// grey with their end time, until midnight (lot 6 spec §2). Foundation only (tested by
// scripts/test-session-roster.sh, with HookRouting for the desktop pill): no AppKit, no
// BotState, the views map `SessionPhase`.

/// What a session is doing. Same raw values as `BotState`, for the phases a session reports.
enum SessionPhase: String, Equatable, CaseIterable {
    case idle, thinking, working, searching, approval, question, ratelimit, error, finished

    /// The phase in plain French, as a row of the open island says it (spec §6).
    var label: String {
        switch self {
        case .idle:      return "En attente"
        case .thinking:  return "Réfléchit"
        case .working:   return "Travaille"
        case .searching: return "Cherche"
        case .approval:  return "Attend ton accord"
        case .question:  return "Te pose une question"
        case .ratelimit: return "Limite atteinte"
        case .error:     return "Erreur"
        case .finished:  return "Terminé"
        }
    }

    /// The session is over (finished or failed): its row is the day's history, in grey with its
    /// end time, under the running sessions until midnight.
    var isEnded: Bool { self == .finished || self == .error }
}

/// One running session. `id` is the hook's session id, `pillId` the pill that routes it,
/// `title` what the session goes by (its name when one is known, `SessionName`, else its project
/// folder), `lastAction` one short line (empty until there is one), `hostBundleId` the app the
/// session runs in (a terminal or an editor), nil when unknown, `folder` the project folder name,
/// what the title falls back to.
struct SessionRow: Equatable, Identifiable {
    let id: String
    var pillId: String
    var title: String
    var phase: SessionPhase
    var lastAction: String
    var updatedAt: Date
    var hostBundleId: String? = nil
    var folder: String = ""
}

// MARK: - The name of a session (Task 25)
// The name the user sees in VS Code's session list and in the Claude app's Code tab, from the two
// documented sources: the `session_title` of a hook (SessionStart and UserPromptSubmit carry it when
// the session has a custom title: `--name`, `/rename`, a rename in the Claude app or VS Code) and the
// `session_name` of the status line (the custom name if set, otherwise the title Claude generated).
// The latest non-empty name wins, whatever its source: the status line carries the custom name as
// soon as it is set, so it is never staler than the hook's title. The transcript is never read.
// Held in memory with the row; nb.log never has it. A request answered from the island records its
// session by this name in the history of choices (choices.json, local), as it recorded the folder.

/// What the island knows of a session's name.
struct SessionName: Equatable {
    /// Longest name kept, in characters.
    static let limit = 120

    /// The name the session goes by: the latest non-empty one that arrived, from a hook or the
    /// status line.
    var name: String
    /// The last time a name arrived: a session with no row yet keeps it 30 min from then.
    var notedAt: Date
    /// The session had a row: the name goes when the row goes.
    var hadRow = false

    /// A name as the island keeps it: one line (each run of spaces, tabs and line breaks becomes one
    /// space), trimmed, cut to 120 characters. Nil for anything else than a string, or when nothing
    /// is left: an empty name never replaces a known one.
    static func clean(_ raw: Any?) -> String? {
        guard let text = raw as? String else { return nil }
        let line = text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        guard !line.isEmpty else { return nil }
        return String(line.prefix(limit)).trimmingCharacters(in: .whitespaces)
    }
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
    /// An idle session (started, nothing asked yet) with no activity for this long leaves the roster.
    static let idleLifetime: TimeInterval = 30 * 60
    /// A working session with no activity for this long leaves too (it ended without telling us),
    /// except a session waiting for an answer.
    static let silentLifetime: TimeInterval = 2 * 60 * 60
    /// Finished or failed rows kept at most, the most recent ends.
    static let endedLimit = 10

    /// Most recent activity first. At equal dates the latest `update` comes first.
    private(set) var rows: [SessionRow] = []

    /// The names of the sessions, by session id: those of the rows, and those that came before their
    /// session's row (kept 30 min). They leave with their row (`end`, `prune`).
    private(set) var names: [String: SessionName] = [:]

    /// Creates or updates the row of `sessionId` and moves it to the top. `folder` is the project
    /// folder name: the row goes by the session's name when one is known (`name`), else by it. A nil
    /// `lastAction` keeps the previous one (empty for a new row); a given one is cut to 80
    /// characters. A nil `hostBundleId` keeps the host the session had (none for a new row).
    mutating func update(sessionId: String, pillId: String, folder: String, phase: SessionPhase,
                         lastAction: String?, hostBundleId: String? = nil, at date: Date) {
        let previous = rows.first { $0.id == sessionId }
        let action: String
        if let lastAction {
            action = String(lastAction.prefix(Self.lastActionLimit))
        } else {
            action = previous?.lastAction ?? ""
        }
        names[sessionId]?.hadRow = true
        rows.removeAll { $0.id == sessionId }
        let row = SessionRow(id: sessionId, pillId: pillId, title: self.title(of: sessionId, folder: folder),
                             phase: phase, lastAction: action, updatedAt: date,
                             hostBundleId: hostBundleId ?? previous?.hostBundleId, folder: folder)
        rows.insert(row, at: rows.firstIndex { $0.updatedAt <= date } ?? rows.count)
    }

    /// A name of `sessionId` arrived (`raw`, as a hook's `session_title` or the status line's
    /// `session_name` gave it). The latest non-empty name wins, whatever its source. The row keeps
    /// its place, its date and everything else. A blank or non-string name changes nothing. A
    /// session with no row yet keeps its name for its row to come, 30 min from the last one noted.
    /// True when the name the session goes by changed (the same name again: false, nothing to log).
    @discardableResult
    mutating func name(sessionId: String, _ raw: Any?, at date: Date) -> Bool {
        dropNames(now: date)
        guard let clean = SessionName.clean(raw) else { return false }
        var known = names[sessionId] ?? SessionName(name: clean, notedAt: date)
        let before = names[sessionId]?.name
        known.name = clean
        known.notedAt = date
        if rows.contains(where: { $0.id == sessionId }) { known.hadRow = true }
        names[sessionId] = known
        guard known.name != before else { return false }
        if let index = rows.firstIndex(where: { $0.id == sessionId }) {
            rows[index].title = known.name
        }
        return true
    }

    /// What session `sessionId` goes by: its name when one is known, else `folder`.
    func title(of sessionId: String, folder: String) -> String {
        names[sessionId]?.name ?? folder
    }

    /// The names whose row left go with it. A name that came before its row stays 30 min after the
    /// last one noted (`now`; nil keeps them all, for `end`, which has no date).
    private mutating func dropNames(now: Date?) {
        guard !names.isEmpty else { return }
        let ids = Set(rows.map(\.id))
        names = names.filter { id, name in
            if ids.contains(id) { return true }
            if name.hadRow { return false }
            guard let now else { return true }
            return now.timeIntervalSince(name.notedAt) < Self.idleLifetime
        }
    }

    /// A session ended (SessionEnd): its row leaves, unless it finished or failed, the day's
    /// history that `prune` clears at midnight (Stop then quitting Claude Code is the usual end of
    /// a session), and its name with it. Unknown ids change nothing.
    mutating func end(sessionId: String) {
        rows.removeAll { $0.id == sessionId && !$0.phase.isEnded }
        dropNames(now: nil)
    }

    /// Removes the rows nobody needs any more. A `finished` or `error` row stays until midnight of
    /// the day it ended, in `calendar` (the user's), and only the 10 most recent ends are kept. An
    /// `idle` row goes after 30 minutes without activity, a working one (`thinking`, `working`,
    /// `searching`, `ratelimit`) after 2 hours, never an `approval` or a `question` (the user is
    /// still expected to answer). The age counts from the row's last update, a row is pruned once
    /// it reaches the limit. A clock set back (now before the row's date) removes nothing. The names
    /// of the rows removed go too, and a name without a row 30 min after it was last noted.
    mutating func prune(now: Date, calendar: Calendar) {
        rows.removeAll { row in
            let silence = now.timeIntervalSince(row.updatedAt)
            switch row.phase {
            case .approval, .question:
                return false
            case .finished, .error:
                // The end of its day: midnight, wherever the clocks change that day.
                guard let midnight = calendar.dateInterval(of: .day, for: row.updatedAt)?.end else { return false }
                return now >= midnight
            case .idle:
                return silence >= Self.idleLifetime
            case .thinking, .working, .searching, .ratelimit:
                return silence >= Self.silentLifetime
            }
        }
        // Rows are in activity order, and an ended row's last activity is its end: the first ten
        // ended rows are the ten most recent ends.
        var ended = 0
        rows.removeAll { row in
            guard row.phase.isEnded else { return false }
            ended += 1
            return ended > Self.endedLimit
        }
        // The names of the rows that left go with them.
        dropNames(now: now)
    }

    /// `listed(rows)` cut to `limit` rows, nothing for a limit of 0 or less. Does not remove anything.
    func visible(limit: Int) -> [SessionRow] {
        Array(Self.listed(rows).prefix(max(0, limit)))
    }

    /// The rows in the order of the home's list: the running sessions first, latest activity
    /// first, then the ended ones (finished or failed), latest end first. `rows` itself stays in
    /// activity order (⌃⌥T opens the session that acted last).
    static func listed(_ rows: [SessionRow]) -> [SessionRow] {
        rows.filter { !$0.phase.isEnded } + rows.filter { $0.phase.isEnded }
    }

    /// The time of `date` on a 24 hour clock, « 14:05 », in `calendar`'s time zone (the user's):
    /// the end time of a finished row (« Terminé à 14:05 »).
    static func clock(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        func twoDigits(_ n: Int?) -> String { let n = n ?? 0; return n < 10 ? "0\(n)" : "\(n)" }
        return twoDigits(parts.hour) + ":" + twoDigits(parts.minute)
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

    /// The name a request of `sessionId` goes by on its card and in the history: the title of that
    /// session's row, whatever its shared pill is called now; `fallback` (the pill's name) when the
    /// session has no row.
    static func title(of sessionId: String?, in rows: [SessionRow], fallback: String) -> String {
        guard let sessionId, let row = rows.first(where: { $0.id == sessionId }) else { return fallback }
        return row.title
    }

    /// What went wrong in a `StopFailure`, as one line of a row, nil when the hook says nothing.
    /// Its input (Claude Code hooks reference) carries `error`, the type (`rate_limit`,
    /// `server_error`…), and optionally `error_details` and `last_assistant_message`, the error text
    /// Claude shows in the conversation (« API Error: Rate limit reached »): that text first, then
    /// the details, then the type.
    static func failureText(of payload: [String: Any]) -> String? {
        for key in ["last_assistant_message", "error_details", "error"] {
            if let text = payload[key] as? String, let one = line(text) { return one }
        }
        return nil
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

// MARK: - What a tool call does to Klay (review I1, spec §7 « Cherche »)

/// The verb a shell command's first word suggests, for the step labels and the search pose.
enum BashVerb: Equatable {
    case reads, searches, tests, runs

    static func of(_ command: String) -> BashVerb {
        let first = command.split(whereSeparator: { $0.isWhitespace }).first.map(String.init) ?? ""
        switch first {
        case "cat", "bat", "head", "tail", "less", "more", "nl": return .reads
        case "rg", "grep", "find", "fd", "ls", "tree", "wc":    return .searches
        default: break
        }
        let testRunners = ["pytest", "vitest", "jest", "npm test", "npm run test",
                           "cargo test", "go test", "swift test", "make test",
                           "xcodebuild test", "unittest"]
        if testRunners.contains(where: { command.contains($0) }) { return .tests }
        return .runs
    }
}

extension SessionPhase {
    /// How long the binoculars stay up at least: a Grep lasts about 100 ms.
    static let searchDwell: TimeInterval = 1.5

    /// The phase a PreToolUse puts its session and its pill in: `searching` (Klay raises his
    /// binoculars) for Grep, Glob, LS, WebSearch, WebFetch and a shell search (`BashVerb.searches`),
    /// `working` for any other tool.
    static func of(tool: String, input: [String: Any]) -> SessionPhase {
        switch tool {
        case "Grep", "Glob", "LS", "WebSearch", "WebFetch":
            return .searching
        case "Bash":
            guard let command = input["command"] as? String else { return .working }
            return BashVerb.of(command) == .searches ? .searching : .working
        default:
            return .working
        }
    }

    /// Whether a PostToolUse leaves the binoculars up: yes until `searchDwell` has passed since the
    /// search started (`searchingSince`, nil when Klay is not searching). Then the next event
    /// decides. No timer: the PostToolUse compares the dates.
    static func postToolUseKeepsSearching(searchingSince: Date?, now: Date) -> Bool {
        guard let searchingSince else { return false }
        return now.timeIntervalSince(searchingSince) < searchDwell
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
    /// middle of. Any other view (a draft in the chat or the mail, a file being sent, Settings,
    /// a permission or a question, or a view added later) is kept.
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

    /// Whether a new prompt makes the finished view on screen stale: only when it comes from the
    /// session that view tells about (`finishedSessionId`), which works again. The state machine
    /// then folds it, unless the pointer is on the island or the user clicked in it.
    static func newPromptFoldsFinished(expanded: Bool, view: String, finishedSessionId: String?,
                                       promptSessionId: String) -> Bool {
        expanded && view == "finished" && finishedSessionId == promptSessionId
    }
}
