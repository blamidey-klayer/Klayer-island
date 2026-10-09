import Foundation

// MARK: - Island Mode

enum IslandMode: String, CaseIterable {
    case hidden, compact, expanded
}

// MARK: - Island View

enum IslandView: String, CaseIterable {
    case overview, empty, approval, question, error, finished
    case confused, upload, uploading, choose, mail, prompt
    case note, settings, greeting
}

// MARK: - Bot State

enum BotState: String, CaseIterable {
    case idle, working, thinking, searching
    case approval, question, error, finished
    case ratelimit, sleeping, dizzy
}

// MARK: - Bot Emote

enum BotEmote: String, CaseIterable {
    case love, surprised, proud, wink, yawn, happy, annoyed
}

// MARK: - Approval info (pending PermissionRequest from Claude Code)

struct ApprovalInfo: Sendable {
    var sessionId: String
    var tool: String
    var command: String
    /// tool_input serialized to JSON with sortedKeys, "" if absent — used to match PostToolUse.
    var inputKey: String
    /// Pill that owns this approval: "integration_claude", or "agent_claude-desktop" for a Claude app session.
    var pillId: String
    /// Token of the held request (HookServer): the card re-arms its buttons when it changes.
    var requestId: Int = 0
    /// The app the card steps aside for when it comes to the front (`CardStepAside.requestHost`):
    /// the Claude app, an editor; nil for a terminal session or an unknown host.
    var hostBundleId: String? = nil
}

// MARK: - Pill badge (shown on pill edge when non-focused task has an alert)

enum PillBadge { case approval, finished, error }

// MARK: - Agent Task

struct AgentTask: Identifiable, Equatable {
    var id: String
    var name: String
    var color: String          // hex
    var state: BotState
    var stepIndex: Int = 0
    var steps: [String]
    var source: AgentSource
    var isIntegration: Bool = false  // true for persistent integration pills
    var pillBadge: PillBadge? = nil  // alert badge shown on pill when not focused
    var sessionBundleId: String? = nil  // app the session runs in (hook bundle_id), for « Ouvrir cette session » and ⌃⌥T
    var finalLine: String?   = nil  // last assistant message shown as static text after Stop
    var hostApp: String?     = nil  // bundle id of the terminal running a Claude Code session; nil = an editor or unknown
}

enum AgentSource: Equatable {
    case claudeCode
    case integration   // persistent pill of a service (GitHub, Spotify)
    case agent         // session tagged with the klayer_agent field (Claude desktop app)
}

// MARK: - View dimensions (from VIEWS in prototype)

struct ViewLayout {
    let height: CGFloat
    let botX: CGFloat
    let botY: CGFloat?         // nil = auto-centered
    let botDiameter: CGFloat
    let agentMode: AgentLayoutMode
}

enum AgentLayoutMode {
    case none, grid, pills, column
}

// MARK: - Klay's size rule

/// The island draws its Klay of layout diameter d in a square canvas d / 0.6 wide (BotPlacement);
/// his click circle is that canvas' inscribed circle, and his glyph spans `glyphSpan` of its
/// width (KlayPaint.glyphScale). The one rule for the island, the drop canvas, the click test and
/// BotEngine, so the drop canvas' Klay takes over from the island's at the same size.
enum KlaySize {
    /// Fraction of the canvas width the glyph spans.
    static let glyphSpan: CGFloat = 0.62

    /// Width of the canvas the island draws Klay of diameter `d` in.
    static func canvasWidth(diameter d: CGFloat) -> CGFloat {
        d / 0.6
    }
}

// MARK: - Constants (from NW, NH, EW in prototype)

enum IslandConst {
    static let notchWidth: CGFloat  = IslandScreenGeometry.fallbackNotchWidth
    static let notchHeight: CGFloat = 32
    static let expandedWidth: CGFloat = 640
    static let earRadius: CGFloat   = 14
    static let roundedCorner: CGFloat = 14    // hidden/peek/compact
    static let expandedCorner: CGFloat = 22

    static let viewLayouts: [IslandView: ViewLayout] = [
        // Home: a 168 pt card for the conversations (26 pt rows, they scroll past what fits) and the
        // 3 last choices (12 pt rows), so the home is 220 tall (8 top + 34 header + 168 card + 10
        // bottom). Klay stays centred on its card height, in his column right of the rail of icons:
        // x 96 is `HomeLayout.klayCenterX` (scripts/test-home-layout.sh checks both agree). The
        // GitHub, Spotify and plan cards keep their 98 pt as a band centred in it (OverviewView),
        // so Klay lines up with them as on the 160 pt island.
        .overview:  ViewLayout(height: 220, botX: 96,  botY: nil, botDiameter: 58, agentMode: .pills),
        // The other non-chat views keep the 160 of the 98 pt card they were drawn for. `empty` keeps
        // its single card too: the main pill always loads, so the island has a task to show the home.
        .empty:     ViewLayout(height: 160, botX: 70,  botY: nil, botDiameter: 62, agentMode: .none),
        .approval:  ViewLayout(height: 160, botX: 62,  botY: nil, botDiameter: 56, agentMode: .column),
        .question:  ViewLayout(height: 160, botX: 62,  botY: nil, botDiameter: 56, agentMode: .column),
        .error:     ViewLayout(height: 160, botX: 62,  botY: nil, botDiameter: 58, agentMode: .column),
        .finished:  ViewLayout(height: 160, botX: 62,  botY: nil, botDiameter: 58, agentMode: .column),
        .confused:  ViewLayout(height: 160, botX: 76,  botY: nil, botDiameter: 66, agentMode: .column),
        // Déposer: Klay in the middle of the drop card, « Dépose ton fichier » under him. The drop
        // canvas (UploadSequenceEngine, USC.REST_X/REST_Y/D_KLAY) starts its Klay here: one Klay.
        .upload:    ViewLayout(height: 176, botX: 320, botY: 92,  botDiameter: 62, agentMode: .column),
        .uploading: ViewLayout(height: 176, botX: 46,  botY: 118, botDiameter: 20, agentMode: .none),
        .choose:    ViewLayout(height: 176, botX: 60,  botY: 101, botDiameter: 52, agentMode: .column),
        .mail:      ViewLayout(height: 240, botX: 56,  botY: nil, botDiameter: 46, agentMode: .column),
        .prompt:    ViewLayout(height: 160, botX: 52,  botY: nil, botDiameter: 44, agentMode: .column),
        .note:      ViewLayout(height: 160, botX: 60,  botY: nil, botDiameter: 50, agentMode: .column),
        .settings:  ViewLayout(height: 160, botX: 54,  botY: nil, botDiameter: 46, agentMode: .none),
        // Greeting: bot drawn by GreetingCanvasView; no BotPlacement needed
        .greeting:  ViewLayout(height: 150, botX: 320, botY: 90,  botDiameter: 0,  agentMode: .none),
    ]

    // Project colors — keyed by lowercase display name or slug
    static let projectColors: [String: String] = [
        "korus":             "#FF5A4E",
        "sbe hub":           "#2EC4A0",
        "morning ai brief":  "#F29B38",
        "publication ig":    "#7C5CFF",
        "ig post":           "#7C5CFF",
        "klayer.ai":         "#3E7280",
        "klayer":            "#3E7280",
        "notch buddy":       "#EC4899",
        "notch-buddy":       "#EC4899",
        "notchbuddy":        "#EC4899",
    ]

    static let fallbackColors = ["#22C55E", "#EAB308", "#60A5FA", "#E879F9"]

    /// Returns the fixed project color for a display name, or a stable fallback.
    static func colorForProject(_ name: String) -> String {
        let key = name.lowercased().trimmingCharacters(in: .whitespaces)
        if let c = projectColors[key] { return c }
        // partial match (e.g. "korus-api" → "korus")
        for (k, c) in projectColors where key.hasPrefix(k) || key.contains(k) { return c }
        return fallbackColors[abs(name.hashValue) % fallbackColors.count]
    }
}
