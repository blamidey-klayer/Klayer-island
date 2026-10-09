import Foundation
// On macOS, Foundation alone gives CGFloat; CoreGraphics is imported where it exists, like
// IslandScreenGeometry.swift, so this file builds the same on Linux for its tests.
#if canImport(CoreGraphics)
import CoreGraphics
#endif

// MARK: - The home of the open island (lot 6 spec §2)
// Left to right on the 640 pt island: a thin rail of greyed icons (Spotify, GitHub, Granola),
// Klay, then the conversations over at least 3/4 of the width. Claude Code and Claude Desktop get
// no icon: their sessions are the list. Foundation only, tested by scripts/test-home-layout.sh;
// OverviewView draws it, IslandConst.viewLayouts places Klay at `klayCenterX`.

/// An icon of the home's rail, in display order.
enum RailIcon: String, CaseIterable {
    case spotify, github, granola

    /// The pill whose existing card the icon shows in place of the list. The ids are the pills'
    /// own (routing, Keychain, preferences), never renamed. Nil for Granola: it opens a new note.
    var pillId: String? {
        switch self {
        case .spotify: return "integration_spotify"
        case .github:  return "integration_github"
        case .granola: return nil
        }
    }
}

/// What a click on a rail icon does.
enum RailAction: Equatable {
    /// The card of this pill replaces the list (the pill takes the focus).
    case showCard(String)
    /// The list comes back (the focus goes back to the pill it had, `HomeRail.listFocus`).
    case showList
    /// A new Granola note (`GranolaLink.newNote`), the home stays as it is.
    case openGranola
}

enum HomeRail {
    /// The pills whose card replaces the list when they have the focus: GitHub and Spotify. Any
    /// other focus, or none, shows the list.
    static let cardPillIds: Set<String> = Set(RailIcon.allCases.compactMap(\.pillId))

    /// The rail's icons: Spotify when its pill is on, GitHub when its pill is on with a token,
    /// Granola always.
    static func icons(spotifyActive: Bool, githubConfigured: Bool) -> [RailIcon] {
        RailIcon.allCases.filter { icon in
            switch icon {
            case .spotify: return spotifyActive
            case .github:  return githubConfigured
            case .granola: return true
            }
        }
    }

    /// Whether the home shows a card (GitHub, Spotify) instead of the list.
    static func showsCard(focusId: String?) -> Bool {
        guard let focusId else { return false }
        return cardPillIds.contains(focusId)
    }

    /// A click on `icon` with `focusId` in focus: a service icon shows its card, or the list when
    /// its card is already on screen (second click); Granola opens a note.
    static func action(for icon: RailIcon, focusId: String?) -> RailAction {
        guard let pillId = icon.pillId else { return .openGranola }
        return focusId == pillId ? .showList : .showCard(pillId)
    }

    /// The pill the focus goes back to when the list comes back: the one in focus before a card
    /// took it (`saved`) when it is still loaded and is not a card's, else the main pill.
    static func listFocus(saved: String?, loaded: [String], main: String) -> String {
        if let saved, loaded.contains(saved), !cardPillIds.contains(saved) { return saved }
        return main
    }

    /// The focus a permission or a question gives back when it leaves: the pill it took the screen
    /// from (`saved`), unless that pill showed a card: after a request the home shows the list, with
    /// the focus the card had taken (`beforeCard`, as `listFocus`).
    static func focusAfterRequest(saved: String, beforeCard: String?, loaded: [String], main: String) -> String {
        showsCard(focusId: saved) ? listFocus(saved: beforeCard, loaded: loaded, main: main) : saved
    }

    // MARK: Pill shortcuts (⌃⌥] ⌃⌥[ ⌘→ ⌘←, ⌘1…9)

    /// What the pill shortcuts walk through, as the home shows it: the list (nil), then the card of
    /// each service icon of the rail, in the rail's order. Granola and the Claude pills are not entries.
    static func cycleEntries(icons: [RailIcon]) -> [String?] {
        [nil] + icons.compactMap(\.pillId)
    }

    /// ⌃⌥] or ⌘→ (`delta` 1), ⌃⌥[ or ⌘← (-1): the entry after or before the one on screen, wrapping.
    /// A focus that shows no card of the rail (a Claude pill, none) is the list.
    static func cycle(from focusId: String?, by delta: Int, icons: [RailIcon]) -> RailAction {
        let entries = cycleEntries(icons: icons)
        let current = entries.firstIndex { $0 != nil && $0 == focusId } ?? 0
        let next = ((current + delta) % entries.count + entries.count) % entries.count
        return action(for: entries[next])
    }

    /// ⌘1…9: entry `number` (1 the list, 2 and 3 the rail's cards), nil when there is none.
    static func entry(number: Int, icons: [RailIcon]) -> RailAction? {
        let entries = cycleEntries(icons: icons)
        guard number >= 1, number <= entries.count else { return nil }
        return action(for: entries[number - 1])
    }

    private static func action(for entry: String?) -> RailAction {
        entry.map { .showCard($0) } ?? .showList
    }
}

/// The home's columns, in island coordinates (x from the island's left edge).
struct HomeLayout {
    /// IslandContentView's horizontal padding: the views start 10 pt in from each edge.
    static let edgeInset: CGFloat = 10
    /// The rail of icons, on the black island left of the card.
    static let rail: CGFloat = 36
    /// Width of a rail icon's button, centred in the rail.
    static let railIconWidth: CGFloat = 30
    /// Klay's column, at the left of the card: his 58 pt with 21 pt on each side, so the circle
    /// of his canvas (58 / 0.6 = 97 pt, where a click slaps him) touches neither a rail icon nor
    /// the start of a row. Klay is 50 pt left of the list, as he was left of the home's text.
    static let klay: CGFloat = 100
    /// The GitHub, Spotify and plan cards start their text 108 pt in from their left edge (drawn
    /// for the 160 pt island, Klay 58 pt in). They keep their drawing and move by this much, so
    /// their text starts where the rows start.
    static let serviceCardInset: CGFloat = 108
    static let serviceCardShift: CGFloat = klay - serviceCardInset

    /// Klay's centre: the middle of his column. `IslandConst.viewLayouts[.overview].botX`.
    static let klayCenterX: CGFloat = edgeInset + rail + klay / 2
    /// Where the list starts.
    static let listStartX: CGFloat = edgeInset + rail + klay

    /// The rail, Klay and the list (to the island's 10 pt right edge, the card's inner margin
    /// included), never negative. The icons shown never change them: an empty rail keeps its width.
    static func widths(islandWidth: CGFloat) -> (rail: CGFloat, klay: CGFloat, list: CGFloat) {
        (rail, klay, max(0, islandWidth - 2 * edgeInset - rail - klay))
    }
}
