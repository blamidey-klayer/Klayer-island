import Foundation

/// What « Ouvrir ce chat » and « Ouvrir cette session » open, and the source icons of the rows and
/// the notes (Task 27). Baptiste, 9 October 2026: « Quand il me dit "Claude t'a répondu" etc., le
/// bouton ne doit pas être "Ouvrir Claude" mais "Ouvrir ce chat" ». The VS Code link is documented
/// (code.claude.com/docs/en/vs-code, « Launch a VS Code tab from other tools »); nothing documented
/// opens a given Code tab session, Cowork task or terminal tab, so those bring their app forward.
@main
enum OpenTargetTests {
    static func main() {
        let cases: [(String, () -> Void)] = [
            ("the_claude_app_s_sessions_activate_the_claude_app", theClaudeAppsSessionsActivateTheClaudeApp),
            ("a_vs_code_extension_session_opens_its_tab", aVSCodeExtensionSessionOpensItsTab),
            ("the_session_id_is_percent_encoded", theSessionIdIsPercentEncoded),
            ("no_link_without_a_usable_session_id", noLinkWithoutAUsableSessionId),
            ("the_vs_code_link_is_only_for_vs_code", theVSCodeLinkIsOnlyForVSCode),
            ("any_other_session_activates_its_host", anyOtherSessionActivatesItsHost),
            ("nothing_known_opens_nothing", nothingKnownOpensNothing),
            ("a_row_opens_by_the_same_rule", aRowOpensByTheSameRule),
            ("the_source_of_a_session_is_its_pill", theSourceOfASessionIsItsPill),
            ("every_session_row_shows_the_code_icon", everySessionRowShowsTheCodeIcon),
            ("a_note_says_where_it_comes_from", aNoteSaysWhereItComesFrom),
            ("the_claude_mark_is_a_neutral_symbol", theClaudeMarkIsANeutralSymbol),
            ("labels_in_french_without_em_dash", labelsInFrenchWithoutEmDash),
        ]
        for (name, run) in cases {
            run()
            print("  ok  \(name)")
        }
        print("Open target: \(cases.count) cases passed")
    }

    static let claudeApp = HookRouting.desktopBundleId
    static let vsCode = "com.microsoft.VSCode"
    static let cursor = "com.todesktop.230313mzl4w4u92"
    static let sid = "96310fe8-60b7-452f-8cd7-a68a842ae8af"

    static func target(_ source: SessionSource, _ entrypoint: String?, _ host: String?, _ id: String? = sid) -> OpenTarget? {
        OpenTarget.of(source: source, entrypoint: entrypoint, hostBundleId: host, sessionId: id)
    }

    static func theClaudeAppsSessionsActivateTheClaudeApp() {
        precondition(target(.claudeApp, "claude-desktop", claudeApp) == .activate(bundleId: claudeApp), "a Code tab session")
        precondition(target(.claudeApp, nil, nil, nil) == .activate(bundleId: claudeApp), "Chat and Cowork: no id, no host")
        precondition(target(.claudeApp, "claude-vscode", vsCode) == .activate(bundleId: claudeApp),
                     "the Claude app's pill wins over anything else")
        precondition(target(.code, "claude-desktop", nil) == .activate(bundleId: claudeApp),
                     "the Claude app's entrypoint on another pill still opens the Claude app")
    }

    static func aVSCodeExtensionSessionOpensItsTab() {
        guard case .url(let url)? = target(.code, "claude-vscode", vsCode) else {
            preconditionFailure("a VS Code extension session opens its link")
        }
        precondition(url.absoluteString == "vscode://anthropic.claude-code/open?session=\(sid)",
                     "the documented link, got \(url.absoluteString)")
        precondition(target(.code, "claude-vscode", "COM.MICROSOFT.VSCODE") == .url(url), "bundle ids ignore case")
    }

    static func theSessionIdIsPercentEncoded() {
        let url = OpenTarget.vsCodeSession("a&b=c d/é")
        precondition(url?.absoluteString == "vscode://anthropic.claude-code/open?session=a%26b%3Dc%20d%2F%C3%A9",
                     "every reserved character encoded, got \(String(describing: url?.absoluteString))")
        precondition(URLComponents(url: url!, resolvingAgainstBaseURL: false)?.queryItems?.first?.value == "a&b=c d/é",
                     "the link gives the id back whole")
    }

    static func noLinkWithoutAUsableSessionId() {
        precondition(OpenTarget.vsCodeSession("") == nil && OpenTarget.vsCodeSession("   ") == nil, "no id")
        precondition(OpenTarget.vsCodeSession(String(repeating: "a", count: 201)) == nil, "200 characters at most")
        precondition(target(.code, "claude-vscode", vsCode, nil) == .activate(bundleId: vsCode),
                     "without an id, VS Code is brought forward")
        precondition(target(.code, "claude-vscode", vsCode, "unknown") == .activate(bundleId: vsCode),
                     "the island never sends a made-up id: « unknown » is no session")
    }

    static func theVSCodeLinkIsOnlyForVSCode() {
        precondition(target(.code, "claude-vscode", cursor) == .activate(bundleId: cursor),
                     "Cursor has no documented link: it comes forward")
        precondition(target(.code, "claude-vscode", nil) == nil, "no host known: no link to an editor that may not be VS Code")
        precondition(target(.code, "claude-vscode", "com.microsoft.VSCodeInsiders")
                     == .activate(bundleId: "com.microsoft.VSCodeInsiders"), "Insiders comes forward")
    }

    static func anyOtherSessionActivatesItsHost() {
        precondition(target(.code, "cli", "com.apple.Terminal") == .activate(bundleId: "com.apple.Terminal"), "a terminal")
        precondition(target(.code, "cli", vsCode) == .activate(bundleId: vsCode), "VS Code's integrated terminal")
        precondition(target(.code, nil, "dev.warp.Warp-Stable") == .activate(bundleId: "dev.warp.Warp-Stable"),
                     "no entrypoint known")
        precondition(target(.code, "cli", "  com.googlecode.iterm2 \n") == .activate(bundleId: "com.googlecode.iterm2"),
                     "trimmed")
    }

    static func nothingKnownOpensNothing() {
        precondition(target(.code, nil, nil) == nil && target(.code, "cli", "  ") == nil,
                     "the caller keeps its fallback")
    }

    static func aRowOpensByTheSameRule() {
        func row(_ pill: String, _ entrypoint: String?, _ host: String?) -> SessionRow {
            SessionRow(id: sid, pillId: pill, title: "T", phase: .finished, lastAction: "", updatedAt: Date(),
                       hostBundleId: host, entrypoint: entrypoint)
        }
        precondition(row("integration_claude", "claude-vscode", vsCode).openTarget
                     == .url(OpenTarget.vsCodeSession(sid)!), "a VS Code tab")
        precondition(row(HookRouting.desktopPillId, "claude-desktop", claudeApp).openTarget == .activate(bundleId: claudeApp),
                     "the Claude app")
        precondition(row("integration_claude", "cli", "com.apple.Terminal").openTarget == .activate(bundleId: "com.apple.Terminal"),
                     "a terminal")
        precondition(row("integration_claude", nil, nil).openTarget == nil, "unknown")
    }

    static func theSourceOfASessionIsItsPill() {
        precondition(SessionSource.of(pillId: HookRouting.desktopPillId) == .claudeApp)
        precondition(SessionSource.of(pillId: "integration_claude") == .code)
    }

    static func everySessionRowShowsTheCodeIcon() {
        // VS Code, the Code tab, a terminal: all Claude Code sessions.
        for pill in ["integration_claude", HookRouting.desktopPillId] {
            let row = SessionRow(id: "s", pillId: pill, title: "T", phase: .working, lastAction: "", updatedAt: Date())
            precondition(row.sourceIcon == .code, "a row of \(pill) shows </>")
        }
        precondition(SourceIcon.code.symbolName == "chevron.left.forwardslash.chevron.right", "the </> symbol")
    }

    static func aNoteSaysWhereItComesFrom() {
        let code = ClaudeAppNoteSource.of(sessionId: "s")
        precondition(code == .codeSession && code.icon == .code && code.openLabel == "Ouvrir cette session",
                     "a Code tab note")
        let chat = ClaudeAppNoteSource.of(sessionId: nil)
        precondition(chat == .chat && chat.icon == .claudeApp && chat.openLabel == "Ouvrir ce chat",
                     "a Chat or Cowork note")
        precondition(OpenTarget.sessionLabel == "Ouvrir cette session", "the finished and error views")
    }

    static func theClaudeMarkIsANeutralSymbol() {
        // The official Claude logo is Anthropic's mark: it waits for a founder, and comes from the
        // official file only. Until then, one neutral SF Symbol in one constant.
        precondition(ClaudeMark.symbolName == "sparkle", "the neutral stand-in")
        precondition(SourceIcon.claudeApp.symbolName == ClaudeMark.symbolName, "the icon reads the one constant")
        precondition(SourceIcon.code.accessibilityLabel == "Session Code"
                     && SourceIcon.claudeApp.accessibilityLabel == "App Claude", "spoken labels")
    }

    static func labelsInFrenchWithoutEmDash() {
        let labels = [OpenTarget.sessionLabel, ClaudeAppNoteSource.chat.openLabel, ClaudeAppNoteSource.codeSession.openLabel,
                      SourceIcon.code.accessibilityLabel, SourceIcon.claudeApp.accessibilityLabel]
        for label in labels {
            precondition(!label.contains("\u{2014}") && !label.isEmpty, "« \(label) »")
        }
    }
}
