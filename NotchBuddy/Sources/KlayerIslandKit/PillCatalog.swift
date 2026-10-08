import Foundation

// MARK: - Pill category

enum PillCategory: String, CaseIterable {
    case workspace
    case agent
    case service

    var title: String {
        switch self {
        case .workspace: return "Where you code"
        case .agent:     return "Agents"
        case .service:   return "Services"
        }
    }
}

// MARK: - Pill definition

struct PillDefinition {
    let id:         String
    let name:       String
    /// The catalog's colour for this pill, whatever the user picked.
    let defaultColor: String
    let category:   PillCategory
    /// Label shown next to the task name in the idle card header.
    let subtitle:   String
    let source:     AgentSource
    var comingSoon: Bool = false

    /// The colour the pill is painted with: the user's own if they picked one
    /// (Settings → Active pills), else the catalog's.
    var color: String {
        PillColors.color(for: id, catalogColor: defaultColor, in: PillColors.stored)
    }

    init(id: String, name: String, color: String, category: PillCategory, subtitle: String,
         source: AgentSource, comingSoon: Bool = false) {
        self.id = id
        self.name = name
        self.defaultColor = color
        self.category = category
        self.subtitle = subtitle
        self.source = source
        self.comingSoon = comingSoon
    }

    /// Label shown in the active-session card header (workspace/agent pills only).
    var sessionSubtitle: String {
        switch id {
        case "integration_claude": return "Claude Code"
        case "agent_cursor":       return "Cursor"
        case "agent_claude-desktop": return "Claude Desktop"
        default:                   return "Agent"
        }
    }
}

// MARK: - Catalog

enum PillCatalog {
    // All declared pills in display order.
    static let all: [PillDefinition] = [
        // ── Where you code ───────────────────────────────────────────────────
        .init(id: "integration_claude",  name: "VS Code",     color: "#F5F6F8",
              category: .workspace, subtitle: "Integration",  source: .claudeCode),
        .init(id: "agent_cursor",        name: "Cursor",      color: "#C0C4CC",
              category: .workspace, subtitle: "Integration",  source: .agent),
        // ── Agents ───────────────────────────────────────────────────────────
        // Claude Code sessions run from the Claude desktop app: the relay tags them
        // `klayer_agent: claude-desktop` from CLAUDE_CODE_ENTRYPOINT, so nothing to install.
        .init(id: "agent_claude-desktop", name: "Claude Desktop", color: "#D97757",
              category: .agent,     subtitle: "Agent",        source: .agent),
        // ── Services ─────────────────────────────────────────────────────────
        .init(id: "integration_github",  name: "GitHub",      color: "#F4505E",
              category: .service,   subtitle: "Integration",  source: .integration),
        .init(id: "integration_spotify", name: "Spotify",     color: "#1DB954",
              category: .service,   subtitle: "Integration",  source: .integration),
    ]

    /// Default ID for the always-on main workspace pill.
    static let defaultMainPillId = "integration_claude"

    /// Looks up a definition by task ID (nil if not in catalog).
    static func definition(for id: String) -> PillDefinition? {
        all.first { $0.id == id }
    }
}
