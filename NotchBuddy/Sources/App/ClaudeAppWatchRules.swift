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
    /// The walk stopped at its bound (depth or node count).
    var truncated: Bool = false
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

    /// The Accessibility prompt shows on its own at most once ever (the first time the watch is on
    /// and the Claude app is seen running); afterwards only from Settings.
    static func promptsForAccess(trusted: Bool, alreadyPrompted: Bool) -> Bool {
        !trusted && !alreadyPrompted
    }

    /// The app launched by the end-to-end test (`KLAYER_ISLAND_TEST=1`): no watch, no prompt.
    static func isTestLaunch(environment: [String: String]) -> Bool {
        environment["KLAYER_ISLAND_TEST"] == "1"
    }

    // MARK: Diagnostic (copied by an explicit click only, never stored)

    static let diagnosticLabelLimit = 60
    static let diagnosticLineLimit = 300

    /// Every unique `role | label` line, in reading order, labels on one line and cut at 60
    /// characters, at most 300 lines.
    static func diagnosticLines(_ buttons: [AXNodeSummary]) -> [String] {
        Array(allDiagnosticLines(buttons).prefix(diagnosticLineLimit))
    }

    private static func allDiagnosticLines(_ buttons: [AXNodeSummary]) -> [String] {
        var seen = Set<String>()
        var lines: [String] = []
        for b in buttons {
            let flat = b.label.components(separatedBy: .newlines).joined(separator: " ")
                .replacingOccurrences(of: "\t", with: " ")
                .trimmingCharacters(in: .whitespaces)
            let label = flat.isEmpty ? "(sans libellé)" : String(flat.prefix(diagnosticLabelLimit))
            let line = "\(b.role) | \(label)"
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
        out.append("Fenêtres : \(s.windows), nœuds lus : \(s.nodesRead), limite atteinte : \(yes(s.truncated))")
        out.append("Lecture : \(s.milliseconds) ms, complète : \(yes(s.complete))")
        out.append("Boutons : \(s.buttons.count), lignes : \(lines.count) sur \(all.count)")
        out.append("Bouton d'arrêt reconnu : \(yes(s.stopVisible)), autorisation reconnue : \(yes(s.permissionVisible))")
        out.append("")
        out.append(contentsOf: lines)
        return out.joined(separator: "\n")
    }
}

/// The watch's state between two reads (pure, tested). The watcher calls `observe` with each read;
/// it reads again only while `needsPolling`.
struct ClaudeAppWatchState: Equatable, Sendable {
    /// The Claude app was in front at the last read.
    private(set) var appFrontmost = false
    /// A stop button was seen and is not gone yet.
    private(set) var answerInProgress = false
    /// The permission prompt on screen was already handled (alerted, seen in front, or kept quiet).
    private(set) var permissionSeen = false

    init() {}

    /// Read again in 2 s only while the Claude app is in front or an answer is under way: nothing
    /// otherwise (0 % CPU with the Claude app behind and no answer under way).
    var needsPolling: Bool { appFrontmost || answerInProgress }

    /// One read. `lastCodeHookAt`: the last hook of a Claude app session (Code tab); within 15 s
    /// of it an event is consumed without an alert.
    mutating func observe(stopVisible: Bool, permissionVisible: Bool, appFrontmost: Bool, now: Date,
                          lastCodeHookAt: Date? = nil) -> [ClaudeAppEvent] {
        self.appFrontmost = appFrontmost
        let quiet = ClaudeAppWatchRules.suppressedByCodeHook(lastHookAt: lastCodeHookAt, now: now)
        var events: [ClaudeAppEvent] = []

        // A permission prompt: once per appearance, and only when the user is elsewhere. One that
        // appeared in front was seen, even if it is still there once the app is behind.
        if permissionVisible {
            if !permissionSeen {
                permissionSeen = true
                if !appFrontmost && !quiet { events.append(.permissionRequested) }
            }
        } else {
            permissionSeen = false
        }

        // An answer: a stop button seen at an earlier read and gone at this one. Gone while a
        // permission prompt shows: Claude waits for the user, it has not finished.
        if stopVisible {
            answerInProgress = true
        } else if answerInProgress {
            answerInProgress = false
            if !appFrontmost && !permissionVisible && !quiet { events.append(.answerFinished) }
        }
        return events
    }

    /// The Claude app quit, or the watch was turned off.
    mutating func reset() { self = ClaudeAppWatchState() }
}
