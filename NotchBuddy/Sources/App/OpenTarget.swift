import Foundation

// MARK: - What the open buttons open, and where a session comes from (Task 27)
// Baptiste, 9 October 2026: « Quand il me dit "Claude t'a répondu" etc., le bouton ne doit pas être
// "Ouvrir Claude" mais "Ouvrir ce chat" ». A note of Chat or Cowork opens « ce chat », the note of a
// Code tab session and the finished or error view of a Claude Code session open « cette session ».
// Documented (code.claude.com/docs/en/vs-code, « Launch a VS Code tab from other tools »):
// `vscode://anthropic.claude-code/open?session=<id>` opens or focuses that session in VS Code. Not
// documented: a link to a given Code tab session or Cowork task of the Claude app, to a Cursor
// session, to a terminal tab. Those bring their app forward. `claude --desktop --resume` is never
// used (documented for CLI sessions only). Foundation only, tested by scripts/test-open-target.sh;
// SessionOpener (ConversationsView.swift) opens what this decides, never through a shell.

/// Where a session lives, for what opens it.
enum SessionSource: Equatable, Sendable {
    /// The Claude app: a Code tab session (its pill), Chat and Cowork.
    case claudeApp
    /// Claude Code anywhere else: the VS Code extension, an editor's terminal, a terminal.
    case code

    /// The source of a session routed to `pillId`.
    static func of(pillId: String) -> SessionSource {
        pillId == HookRouting.desktopPillId ? .claudeApp : .code
    }
}

/// What an open button (or a row) opens.
enum OpenTarget: Equatable, Sendable {
    /// A documented link, opened with NSWorkspace (never a shell).
    case url(URL)
    /// The app with this bundle id, brought forward (launched when it is not running).
    case activate(bundleId: String)

    /// The label of the open button of the finished and error views and of the Code tab note.
    static let sessionLabel = "Ouvrir cette session"
    /// VS Code's bundle id: the only editor with a documented link to a session.
    static let vsCodeBundleId = "com.microsoft.VSCode"
    /// The `CLAUDE_CODE_ENTRYPOINT` of the VS Code extension's sessions (seen as `app.entrypoint` in
    /// Claude Code's telemetry; the variable itself is not documented: an empirical hint).
    static let vsCodeEntrypoint = "claude-vscode"
    /// The `CLAUDE_CODE_ENTRYPOINT` of the Claude app's sessions (its Code tab).
    static let claudeAppEntrypoint = "claude-desktop"
    /// Longest session id put in a link.
    static let sessionIdLimit = 200

    /// What opens a session: the Claude app for its sessions; the VS Code tab of a VS Code extension
    /// session (entrypoint `claude-vscode`, host VS Code, a session id); otherwise its host app by
    /// bundle id. Nil when nothing is known (the caller keeps its fallback).
    static func of(source: SessionSource, entrypoint: String?, hostBundleId: String?, sessionId: String?) -> OpenTarget? {
        if source == .claudeApp || entrypoint == claudeAppEntrypoint {
            return .activate(bundleId: HookRouting.desktopBundleId)
        }
        let host = hostBundleId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if entrypoint == vsCodeEntrypoint, host.caseInsensitiveCompare(vsCodeBundleId) == .orderedSame,
           let id = sessionId, let url = vsCodeSession(id) {
            return .url(url)
        }
        return host.isEmpty ? nil : .activate(bundleId: host)
    }

    /// `vscode://anthropic.claude-code/open?session=<id>`, built with URLComponents, the id
    /// percent-encoded (every character but A-Z, a-z, 0-9 and `-._~`). Nil for an id that is blank,
    /// longer than 200 characters, or the island's own stand-in « unknown » (a hook without
    /// session_id): an unknown id would start a fresh conversation.
    static func vsCodeSession(_ sessionId: String) -> URL? {
        let id = sessionId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty, id.count <= sessionIdLimit, id != "unknown",
              let encoded = id.addingPercentEncoding(withAllowedCharacters: unreserved) else { return nil }
        var components = URLComponents()
        components.scheme = "vscode"
        components.host = "anthropic.claude-code"
        components.path = "/open"
        components.percentEncodedQueryItems = [URLQueryItem(name: "session", value: encoded)]
        return components.url
    }

    /// RFC 3986's unreserved characters, ASCII only.
    private static let unreserved = CharacterSet(charactersIn:
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
}

extension SessionRow {
    /// What a click on the row opens (`OpenTarget.of`).
    var openTarget: OpenTarget? {
        OpenTarget.of(source: SessionSource.of(pillId: pillId), entrypoint: entrypoint,
                      hostBundleId: hostBundleId, sessionId: id)
    }

    /// The icon at the left of the row: every row is a Claude Code session (VS Code, the Code tab, a
    /// terminal).
    var sourceIcon: SourceIcon { .code }
}

// MARK: - Source icons

/// The neutral mark that stands for the Claude app on the Chat and Cowork notes. The official
/// Claude logo is Anthropic's trademark: using it waits for a founder, and it would come from the
/// official file, never redrawn. Until then a neutral SF Symbol, in this one constant, the only
/// place to change (SourceIconView draws it).
enum ClaudeMark {
    static let symbolName = "sparkle"
}

/// The icon that says where a row or a note comes from, tinted with the colour of its state.
enum SourceIcon: Equatable, Sendable {
    /// A Claude Code session: `</>`.
    case code
    /// The Claude app's Chat and Cowork: the Claude mark.
    case claudeApp

    /// The SF Symbol drawn.
    var symbolName: String {
        switch self {
        case .code:      return "chevron.left.forwardslash.chevron.right"
        case .claudeApp: return ClaudeMark.symbolName
        }
    }

    /// What VoiceOver says (a French key of the catalogue).
    var accessibilityLabel: String {
        switch self {
        case .code:      return "Session Code"
        case .claudeApp: return "App Claude"
        }
    }
}

/// Where a note of the Claude app comes from (`AppState.showClaudeAppAlert`): a Notification hook of
/// a Code tab session (it has a session id), or the Chat and Cowork watch (none).
enum ClaudeAppNoteSource: Equatable, Sendable {
    case codeSession
    case chat

    static func of(sessionId: String?) -> ClaudeAppNoteSource {
        sessionId == nil ? .chat : .codeSession
    }

    var icon: SourceIcon { self == .chat ? .claudeApp : .code }

    /// The label of its open button, which brings the Claude app forward.
    var openLabel: String { self == .chat ? "Ouvrir ce chat" : OpenTarget.sessionLabel }
}
