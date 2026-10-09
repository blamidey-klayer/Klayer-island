import Foundation

// MARK: - Chat and Cowork in the Claude app (lot 6 spec §6, experimental)
//
// The Claude app emits no hook for Chat and Cowork, so the island reads the buttons of its interface
// through macOS Accessibility (ClaudeAppWatcher). This file holds what that reading may conclude:
// the labels it knows (the only place they live), the rules, the state machine and the diagnostic.
// Foundation only, tested on Linux (scripts/test-claude-app-watch.sh). Only the role and the label
// of buttons are ever read: never a message's text, never AXValue.

/// One button of the Claude app's interface: its accessibility role (AXButton, AXMenuButton,
/// AXPopUpButton) and its label (AXDescription, else AXTitle, else AXHelp; never AXValue).
struct AXNodeSummary: Equatable, Sendable {
    let role: String
    let label: String
}

/// What the watch tells the island.
enum ClaudeAppEvent: Equatable, Sendable {
    /// A stop button seen at an earlier read is gone, the Claude app not in front.
    case answerFinished
    /// An allow button and a deny button appeared, the Claude app not in front.
    case permissionRequested
}

/// What one read of the Claude app's interface saw. Sendable: it leaves the reading queue for the
/// main actor; the accessibility elements themselves never do.
struct ClaudeAppSnapshot: Equatable, Sendable {
    /// False when macOS refused the reading (Accessibility access not granted).
    var trusted: Bool = true
    /// False when the read says nothing (the Claude app did not answer in time, or shows no window):
    /// not « no button », so an answer under way is not taken for finished.
    var complete: Bool = true
    var buttons: [AXNodeSummary] = []
    var nodesRead: Int = 0
    var windows: Int = 0
    /// The walk met nodes deeper than `maxDepth` and did not enter them.
    var depthLimited: Bool = false
    /// The walk stopped at `maxNodes`.
    var nodeLimited: Bool = false
    /// The title of the Claude app's main window, for the alert's line only (never the diagnostic).
    var windowTitle: String? = nil
    var milliseconds: Int = 0

    var stopVisible: Bool { ClaudeAppWatchRules.stopVisible(buttons) }
    var permissionVisible: Bool { ClaudeAppWatchRules.hasPermissionPrompt(buttons) }
}

enum ClaudeAppWatchRules {

    // MARK: Labels (English and French interface; the diagnostic corrects them on a real Mac)

    /// The button that stops an answer under way: seen, then gone, is a finished answer.
    static let stopLabels: [String] = [
        "Stop response", "Stop", "Arrêter la réponse", "Arrêter",
    ]
    /// The allow side of a permission prompt.
    static let permissionAllowLabels: [String] = [
        "Allow", "Allow once", "Always allow", "Allow always",
        "Autoriser", "Autoriser une fois", "Toujours autoriser",
    ]
    /// The deny side of a permission prompt: a prompt needs one of each.
    static let permissionDenyLabels: [String] = [
        "Deny", "Don't allow", "Refuser", "Ne pas autoriser",
    ]
    static let permissionLabels: [String] = permissionAllowLabels + permissionDenyLabels

    /// The only roles read. Static text, text areas, links and values are never read.
    static let buttonRoles: Set<String> = ["AXButton", "AXMenuButton", "AXPopUpButton"]

    // MARK: Bounds of the reading

    /// Seconds between two reads, only while `ClaudeAppWatchState.needsPolling`.
    static let pollInterval: TimeInterval = 2
    static let maxDepth = 30
    static let maxNodes = 5_000
    /// Unreadable reads in a row, behind, after which an answer under way is dropped (30 s).
    static let unreadableReadLimit = 15
    /// Seconds an answer is followed from behind before it is dropped: a generic « Stop » button
    /// that never leaves (dictation, a long task) does not keep the reading on for good.
    static let answerBehindLimit: TimeInterval = 3_600
    /// Seconds an accessibility call to the Claude app may take before it is given up.
    static let messagingTimeout: Float = 0.5

    // MARK: Matching

    /// Case-insensitive, trimmed, typographic apostrophe as a straight one. Exact match only.
    static func normalized(_ label: String) -> String {
        label.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .lowercased()
    }

    static func matches(_ label: String, _ list: [String]) -> Bool {
        let key = normalized(label)
        guard !key.isEmpty else { return false }
        return list.contains { normalized($0) == key }
    }

    static func isButton(_ n: AXNodeSummary) -> Bool { buttonRoles.contains(n.role) }

    static func isStop(_ n: AXNodeSummary) -> Bool { isButton(n) && matches(n.label, stopLabels) }
    static func isPermissionAllow(_ n: AXNodeSummary) -> Bool { isButton(n) && matches(n.label, permissionAllowLabels) }
    static func isPermissionDeny(_ n: AXNodeSummary) -> Bool { isButton(n) && matches(n.label, permissionDenyLabels) }

    static func stopVisible(_ nodes: [AXNodeSummary]) -> Bool { nodes.contains(where: isStop) }

    /// True only when an allow-type and a deny-type button are both visible: a lone « Allow » (a
    /// notification banner, a setting) is no permission asked.
    static func hasPermissionPrompt(_ nodes: [AXNodeSummary]) -> Bool {
        nodes.contains(where: isPermissionAllow) && nodes.contains(where: isPermissionDeny)
    }

    /// The attributes a button's label is read from, in this order. Never AXValue.
    static let labelAttributes = ["AXDescription", "AXTitle", "AXHelp"]

    /// A button's label: the first of `labelAttributes` that is not blank, trimmed; "" when none.
    /// `read` is asked for one attribute at a time and no further than the first label found.
    static func label(reading read: (String) -> String?) -> String {
        for attribute in labelAttributes {
            let trimmed = (read(attribute) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        return ""
    }

    static func label(description: String?, title: String?, help: String?) -> String {
        label { attribute in
            switch attribute {
            case "AXDescription": return description
            case "AXTitle": return title
            default: return help
            }
        }
    }

    // MARK: The Code tab

    /// Seconds after a hook of a Claude app session (`klayer_agent: claude-desktop`) during which the
    /// watch stays quiet: a Code tab session runs inside the Claude app, its stop and permission
    /// buttons show there, and its hooks already tell the island.
    static let codeHookQuiet: TimeInterval = 15

    static func suppressedByCodeHook(lastHookAt: Date?, now: Date) -> Bool {
        guard let lastHookAt else { return false }
        return now.timeIntervalSince(lastHookAt) <= codeHookQuiet
    }

    // MARK: The alert, the permission, the test launch

    /// The alert's line: the Claude app's window title when it says more than « Claude », else nil
    /// (the caller then writes « Dans l'app Claude »).
    static func conversationTitle(windowTitle: String?) -> String? {
        let title = (windowTitle ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, title.lowercased() != "claude" else { return nil }
        return title
    }

    /// The Accessibility prompt shows on its own at most once per build: the first time the watch is
    /// on and the Claude app is seen running without access, for a build (`currentBuild`, its
    /// CFBundleVersion) other than the one it last showed for (`promptedBuild`, nil when never). An
    /// ad hoc signed build loses the access at each update. Afterwards only from Settings.
    static func promptsForAccess(trusted: Bool, promptedBuild: String?, currentBuild: String) -> Bool {
        !trusted && promptedBuild != currentBuild
    }

    /// The app launched by the end-to-end test (`KLAYER_ISLAND_TEST=1`): no watch, no prompt.
    static func isTestLaunch(environment: [String: String]) -> Bool {
        environment["KLAYER_ISLAND_TEST"] == "1"
    }

    // MARK: Diagnostic (copied by an explicit click only, never stored)

    static let diagnosticLineLimit = 300
    /// A label is copied only when it is short, as the stop, allow and deny labels are: in a web
    /// app a button's name is often its text (a card, a tool summary, « More options for <title> »).
    static let diagnosticLabelMaxCharacters = 30
    static let diagnosticLabelMaxWords = 5

    /// A button's label as the diagnostic writes it: on one line, « (sans libellé) » when blank,
    /// « (libellé long, N caractères) » past 30 characters or 5 words. The alerts match on the full
    /// label; only the copied text is hidden.
    static func diagnosticLabel(_ label: String) -> String {
        let flat = label.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        let line = flat.joined(separator: " ")
        if line.isEmpty { return "(sans libellé)" }
        if line.count > diagnosticLabelMaxCharacters || flat.count > diagnosticLabelMaxWords {
            return "(libellé long, \(line.count) caractères)"
        }
        return line
    }

    /// Every unique `role | label` line, in reading order, at most 300 lines.
    static func diagnosticLines(_ buttons: [AXNodeSummary]) -> [String] {
        Array(allDiagnosticLines(buttons).prefix(diagnosticLineLimit))
    }

    private static func allDiagnosticLines(_ buttons: [AXNodeSummary]) -> [String] {
        var seen = Set<String>()
        var lines: [String] = []
        for b in buttons {
            let line = "\(b.role) | \(diagnosticLabel(b.label))"
            if seen.insert(line).inserted { lines.append(line) }
        }
        return lines
    }

    /// The text copied by « Copier le diagnostic de l'app Claude »: the Claude app's version, whether
    /// access is granted, the counts, then the button lines. Never the window title, never a value.
    static func diagnostic(appVersion: String?, running: Bool, trusted: Bool, snapshot: ClaudeAppSnapshot?) -> String {
        func yes(_ b: Bool) -> String { b ? "oui" : "non" }
        var out = ["Diagnostic de l'app Claude (Klayer Island)"]
        if running {
            out.append("App Claude : lancée, version \(appVersion ?? "inconnue")")
        } else {
            out.append("App Claude : non lancée")
        }
        out.append("Accès Accessibilité : \(yes(trusted))")
        guard running, trusted, let s = snapshot else { return out.joined(separator: "\n") }
        let all = allDiagnosticLines(s.buttons)
        let lines = Array(all.prefix(diagnosticLineLimit))
        out.append("Fenêtres : \(s.windows), nœuds lus : \(s.nodesRead), "
                   + "limite de profondeur atteinte : \(yes(s.depthLimited)), "
                   + "limite de nœuds atteinte : \(yes(s.nodeLimited))")
        out.append("Lecture : \(s.milliseconds) ms, complète : \(yes(s.complete))")
        out.append("Boutons : \(s.buttons.count), lignes : \(lines.count) sur \(all.count)")
        out.append("Bouton d'arrêt reconnu : \(yes(s.stopVisible)), autorisation reconnue : \(yes(s.permissionVisible))")
        out.append("")
        out.append(contentsOf: lines)
        return out.joined(separator: "\n")
    }
}

/// The watch's state between two reads (pure, tested). The watcher calls `observe` with each read
/// it could make, `observeUnreadable` with each one that said nothing; it reads again only while
/// `needsPolling`.
struct ClaudeAppWatchState: Equatable, Sendable {
    /// The first read without the stop button of an answer under way, waiting for a second one.
    struct Miss: Equatable, Sendable {
        /// That read was made with the Claude app in front.
        var inFront: Bool
        /// A permission prompt showed at that read.
        var prompt: Bool
    }

    /// The Claude app was in front at the last read, readable or not.
    private(set) var appFrontmost = false
    /// A stop button was seen and is not confirmed gone yet.
    private(set) var answerInProgress = false
    /// The stop button was missing at one read: a second read in a row confirms the end.
    private(set) var pendingMiss: Miss? = nil
    /// Since when the answer under way is followed from behind (reset in front).
    private(set) var behindSince: Date? = nil
    /// Unreadable reads in a row while behind.
    private(set) var unreadableStreak = 0
    /// An answer was dropped (60 min behind, or unreadable): the same stop button is not followed
    /// again from behind until a read is in front or sees no stop button.
    private(set) var droppedStop = false
    /// The permission prompt on screen was already handled (alerted, seen in front, or kept quiet).
    private(set) var permissionSeen = false
    /// Reads in a row without the permission prompt: two re-arm it.
    private(set) var permissionAbsentReads = 0

    init() {}

    /// Read again in 2 s only while the Claude app is in front or an answer is under way and still
    /// readable: nothing otherwise (0 % CPU with the Claude app behind and no answer under way).
    var needsPolling: Bool {
        appFrontmost || (answerInProgress && unreadableStreak < ClaudeAppWatchRules.unreadableReadLimit)
    }

    /// One read. `lastCodeHookAt`: the last hook of a Claude app session (Code tab); within 15 s
    /// of it an event is consumed without an alert.
    mutating func observe(stopVisible: Bool, permissionVisible: Bool, appFrontmost: Bool, now: Date,
                          lastCodeHookAt: Date? = nil) -> [ClaudeAppEvent] {
        self.appFrontmost = appFrontmost
        unreadableStreak = 0
        let quiet = ClaudeAppWatchRules.suppressedByCodeHook(lastHookAt: lastCodeHookAt, now: now)
        var events: [ClaudeAppEvent] = []

        // A permission prompt: once per appearance, and only when the user is elsewhere. One that
        // appeared in front was seen, even if it is still there once the app is behind. It counts
        // as gone after two reads in a row without it (a flicker is the same prompt).
        if permissionVisible {
            permissionAbsentReads = 0
            if !permissionSeen {
                permissionSeen = true
                if !appFrontmost && !quiet { events.append(.permissionRequested) }
            }
        } else if permissionSeen {
            permissionAbsentReads += 1
            if permissionAbsentReads >= 2 {
                permissionSeen = false
                permissionAbsentReads = 0
            }
        }

        // A dropped answer's stop button is not followed again from behind.
        if droppedStop && (appFrontmost || !stopVisible) { droppedStop = false }

        if stopVisible {
            guard !droppedStop else { return events }
            answerInProgress = true
            pendingMiss = nil
            if appFrontmost {
                behindSince = nil
            } else if let since = behindSince {
                if now.timeIntervalSince(since) > ClaudeAppWatchRules.answerBehindLimit {
                    dropAnswer()   // silently: no event
                }
            } else {
                behindSince = now
            }
        } else if answerInProgress {
            if let miss = pendingMiss {
                // Gone at two reads in a row: the end. Nothing when either read was in front (the
                // user saw it), when a permission prompt showed (Claude waits, it has not
                // finished), or within 15 s of a Code tab hook at this confirming read.
                forgetAnswer()
                if !miss.inFront && !appFrontmost && !miss.prompt && !permissionVisible && !quiet {
                    events.append(.answerFinished)
                }
            } else {
                pendingMiss = Miss(inFront: appFrontmost, prompt: permissionVisible)
            }
        }
        return events
    }

    /// A read that said nothing (no window, the Claude app did not answer in time). `appFrontmost`
    /// is taken from the system at that time. Behind, 15 of them in a row drop the answer.
    mutating func observeUnreadable(appFrontmost: Bool) {
        self.appFrontmost = appFrontmost
        guard !appFrontmost else {
            unreadableStreak = 0
            return
        }
        unreadableStreak += 1
        if answerInProgress && unreadableStreak >= ClaudeAppWatchRules.unreadableReadLimit {
            dropAnswer()
        }
    }

    /// The Claude app quit, or the watch was turned off.
    mutating func reset() { self = ClaudeAppWatchState() }

    private mutating func forgetAnswer() {
        answerInProgress = false
        pendingMiss = nil
        behindSince = nil
    }

    private mutating func dropAnswer() {
        forgetAnswer()
        droppedStop = true
    }
}
