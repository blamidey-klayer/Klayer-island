import SwiftUI
import AppKit

// MARK: - Conversations in progress (home of the open island)

/// The running Claude sessions, on the home of the open island (spec §6): one row per session of
/// `AppState.sessions`, newest activity first, 3 at most. Without any, one line in grey says so,
/// and a second one says when the Claude Code hooks are missing, with a way to Settings.
struct ConversationsView: View {
    /// The roster, newest activity first.
    let sessions: [SessionRow]
    /// The Claude Code hooks are not in ~/.claude/settings.json: no session can show up. Read by
    /// the caller when the home shows, never here (it reads a file).
    var hooksMissing: Bool = false

    /// Rows shown at most.
    static let limit = 3

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
            VStack(alignment: .leading, spacing: 3) {
                ForEach(sessions.prefix(Self.limit)) { row in
                    ConversationRow(row: row)
                }
            }
        }
    }
}

/// One session: a mini Klay on the colour of its phase, the project folder, the phase in plain
/// French, and the last action on one line. A click opens the session (`SessionOpener`).
private struct ConversationRow: View {
    let row: SessionRow
    @State private var isHovered = false

    /// The mini Klay of the row, drawn like the pills' ones: the pose and the colour of the
    /// phase (`StateColor`, the colours of Klay's states).
    private var miniTask: AgentTask {
        let pose = BotState(rawValue: row.phase.rawValue) ?? .idle
        return AgentTask(id: row.id, name: row.title, color: hexString(StateColor.of(pose)),
                         state: pose, steps: [], source: .agent)
    }

    var body: some View {
        Button(action: { SessionOpener.open(row) }) {
            HStack(spacing: 8) {
                MiniBotCanvasView(task: miniTask)
                    .frame(width: 18 / 0.6, height: 18 / 0.6)
                    .frame(width: 18, height: 18, alignment: .center)
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 6) {
                        Text(row.title)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(Color(hex: "#F5F6F8"))
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .layoutPriority(1)
                        // Looked up in the catalog (French keys marked manual: no literal here)
                        Text(LocalizedStringKey(row.phase.label))
                            .font(.system(size: 11))
                            .foregroundColor(Color(hex: "#8E939C"))
                            .lineLimit(1)
                            .fixedSize()
                        Spacer(minLength: 0)
                    }
                    if !row.lastAction.isEmpty {
                        Text(row.lastAction)
                            .font(.system(size: 10.5))
                            .foregroundColor(Color(hex: "#6B7079"))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 26)
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

/// Opens what a click on a row opens (`SessionRow.openTarget`): the Claude app (`claude://`) for a
/// session of the Claude app, the running terminal or editor of a Claude Code session, and the
/// Claude app when that host is gone. ⌃⌥T uses the same rule for the most recent session.
@MainActor
enum SessionOpener {
    /// A click on a row: opens the session, then folds the island like the finished view's buttons.
    static func open(_ row: SessionRow) {
        if !openKnownTarget(row) { openClaudeApp() }
        NotificationCenter.default.post(name: .islandCollapse, object: nil)
    }

    /// Opens the session where it is known to live: its running host (terminal or editor), or the
    /// Claude app for a session of the Claude app. False for a Claude Code session whose host is
    /// unknown or no longer running: the caller picks the fallback.
    @discardableResult
    static func openKnownTarget(_ row: SessionRow) -> Bool {
        let apps = NSWorkspace.shared.runningApplications
        switch row.openTarget(running: Set(apps.compactMap(\.bundleIdentifier))) {
        case .host(let bundleId):
            return apps.first(where: { $0.bundleIdentifier == bundleId })?.activate() ?? false
        case .claudeApp:
            guard row.pillId == HookRouting.desktopPillId else { return false }
            openClaudeApp()
            return true
        }
    }

    private static func openClaudeApp() {
        NSWorkspace.shared.open(URL(string: "claude://")!)
    }
}

/// "#RRGGBB" of an RGB colour: the mini Klay takes its disc colour as a hex string.
private func hexString(_ color: CGColor) -> String {
    guard let c = color.components, c.count >= 3 else { return "#FFFFFF" }
    func byte(_ v: CGFloat) -> Int { Int((max(0, min(1, v)) * 255).rounded()) }
    return String(format: "#%02X%02X%02X", byte(c[0]), byte(c[1]), byte(c[2]))
}
