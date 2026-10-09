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

// MARK: - The list as a wheel (Task 27)
// Baptiste: « un défilement plus sympa en arc de cercle : en haut plus petit, en bas aussi plus
// petit, au milieu gros au défilement ». The rows near the vertical centre of the list are full
// size; towards the top and the bottom they shrink, fade and move slightly right, so the list reads
// as an arc. OverviewView applies it per row with a scroll transition (`phase`: -1 a row leaving at
// the top, 0 at the centre, 1 leaving at the bottom), computed only while the list moves: nothing
// runs at rest. Content margins let the first and the last row reach the centre.
// 0.3.4: the margins come from the list's layout height (`homeListHeight`), never from a measure of
// the scroll view, and the scroll no longer settles on a row. In 0.3.3 the measured height fed the
// margins, the margins the layout and the row snapping the offset, inside the window's layout pass:
// AppKit stopped the loop by raising an exception (the crash on macOS 27).

enum ListWheel {
    /// Height of a row of the list.
    static let rowHeight: CGFloat = 26
    /// Height of the home's list: the home's 168 pt card (the 220 pt island of
    /// `IslandConst.viewLayouts[.overview]` less IslandContentView's 8 pt top, 34 pt header and 10 pt
    /// bottom) less the list's 9 pt top and 8 pt bottom (OverviewView). A layout constant: the list's
    /// margins must never follow a measure of its own scroll view.
    static let homeListHeight: CGFloat = 151
    /// The home list's margin above the first row and below the last one.
    static let homeMargin: CGFloat = centringMargin(viewport: homeListHeight, row: rowHeight)
    /// Scale, opacity and shift of a row at the edges.
    static let edgeScale = 0.78
    static let edgeOpacity = 0.45
    /// Points a row at the edges moves right.
    static let edgeShift = 10.0
    /// The phase where the edge look is reached: a row fully visible at the top or the bottom of the
    /// list is already there.
    static let reach = 0.75

    struct Look: Equatable {
        var scale: Double
        var opacity: Double
        var xOffset: Double
    }

    /// How a row at `phase` looks: whole at 0, the edge look from `reach` on, a smooth step between,
    /// the same above and below.
    static func look(phase: Double) -> Look {
        let e = min(1, abs(phase) / reach)
        let eased = e * e * (3 - 2 * e)
        return Look(scale: 1 - (1 - edgeScale) * eased, opacity: 1 - (1 - edgeOpacity) * eased,
                    xOffset: edgeShift * eased)
    }

    /// The margin above the first row and below the last one so each can reach the centre of a list
    /// `viewport` points tall: half the room a `row` leaves. Never negative.
    static func centringMargin(viewport: CGFloat, row: CGFloat) -> CGFloat {
        max(0, (viewport - row) / 2)
    }
}
