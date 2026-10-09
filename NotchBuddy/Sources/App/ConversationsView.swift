import SwiftUI
import AppKit

// MARK: - Conversations in progress (home of the open island)

/// The Claude sessions, on the home of the open island (spec §6, lot 6 spec §2): one row per
/// session of `AppState.sessions`, the running ones first (latest activity first), then the ones
/// that finished or failed today, in grey (latest end first). All of them: the home scrolls past
/// what fits, as a wheel (`listWheel`). The rows are this view's own children, so the list's stack
/// lays them out and the wheel turns each one. Without any, one line in grey says so, and a second one
/// says when the Claude Code hooks are missing, with a way to Settings.
struct ConversationsView: View {
    /// The roster in the order of the list (`SessionRoster.listed`).
    let sessions: [SessionRow]
    /// The Claude Code hooks are not in ~/.claude/settings.json: no session can show up. Read by
    /// the caller when the home shows, never here (it reads a file).
    var hooksMissing: Bool = false

    var body: some View {
        if sessions.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("Aucune conversation en cours.")
                    .font(.system(size: 12))
                    .foregroundColor(Color(hex: "#8E939C"))
                    .lineLimit(1)
                if hooksMissing {
                    HStack(spacing: 8) {
                        Text("Hooks Claude Code non installés")
                            .font(.system(size: 11))
                            .foregroundColor(Color(hex: "#6B7079"))
                            .lineLimit(1)
                        Button("Réglages…") {
                            NotificationCenter.default.post(name: .openFullSettings, object: "agents")
                        }
                        .font(.system(size: 11))
                        .foregroundColor(Color(hex: "#8E939C"))
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            ForEach(sessions) { row in
                ConversationRow(row: row)
                    .listWheel()
            }
        }
    }
}

/// One session (Task 27, Baptiste: « le nom de la session, et en dessous la description de sa
/// dernière action »): the source icon `</>` in the colour of its phase (`StateColor`, the colours of
/// Klay's states, as the mini Klay it replaces), the session's name, and under it its last action in
/// plain French (`SessionRow.detail`). A session that finished or failed is in grey, its icon grey. A
/// click opens the session (`SessionOpener`).
private struct ConversationRow: View {
    let row: SessionRow
    @State private var isHovered = false

    private var ended: Bool { row.phase.isEnded }

    var body: some View {
        Button(action: { SessionOpener.open(row) }) {
            HStack(spacing: 8) {
                SourceIconView(icon: row.sourceIcon, color: StateColor.color(of: row.phase))
                    .saturation(ended ? 0 : 1)
                    .opacity(ended ? 0.6 : 1)
                VStack(alignment: .leading, spacing: 0) {
                    Text(verbatim: row.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Color(hex: ended ? "#8E939C" : "#F5F6F8"))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text(verbatim: row.detail)
                        .font(.system(size: 10.5))
                        .foregroundColor(Color(hex: ended ? "#6B7079" : "#8E939C"))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: ListWheel.rowHeight)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.white.opacity(isHovered ? 0.06 : 0))
                    .padding(.horizontal, -4)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Opening a session

/// Opens what `OpenTarget` decides (Task 27): the VS Code tab of a VS Code extension session (its
/// documented `vscode://` link, opened with NSWorkspace, never through a shell), the Claude app for a
/// session of the Claude app, the app any other session runs in (terminal or editor). A row falls
/// back to the Claude app when its host is unknown or not running, as before; ⌃⌥T uses the same rule
/// for the most recent session; the open buttons launch the host when it is not running.
@MainActor
enum SessionOpener {
    /// A click on a row: opens the session, then folds the island like the finished view's buttons.
    static func open(_ row: SessionRow) {
        if !openKnownTarget(row) { openClaudeApp() }
        NotificationCenter.default.post(name: .islandCollapse, object: nil)
    }

    /// Opens the session where it is known to live (`SessionRow.openTarget`). False when its host is
    /// unknown or no longer running: the caller picks the fallback.
    @discardableResult
    static func openKnownTarget(_ row: SessionRow) -> Bool {
        guard let target = row.openTarget else { return false }
        return open(target, launching: false)
    }

    /// Opens `target`: a link with NSWorkspace; the Claude app brought forward or launched; another app
    /// brought forward, or launched when `launching` (the open buttons). False when nothing opened.
    @discardableResult
    static func open(_ target: OpenTarget, launching: Bool) -> Bool {
        switch target {
        case .url(let url):
            return NSWorkspace.shared.open(url)
        case .activate(let bundleId):
            if bundleId == HookRouting.desktopBundleId { return openClaudeApp() }
            if let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleId }) {
                return app.activate()
            }
            guard launching, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else {
                return false
            }
            NSWorkspace.shared.openApplication(at: url, configuration: .init(), completionHandler: nil)
            return true
        }
    }

    /// Brings the Claude app forward, or launches it; `claude://` when its bundle is not found.
    @discardableResult
    static func openClaudeApp() -> Bool {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: HookRouting.desktopBundleId) {
            NSWorkspace.shared.openApplication(at: url, configuration: .init(), completionHandler: nil)
            return true
        }
        return NSWorkspace.shared.open(URL(string: "claude://")!)
    }
}
