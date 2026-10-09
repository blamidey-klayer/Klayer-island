import Foundation

/// The home of the open island (lot 6 spec §2), left to right: the rail of greyed icons (Spotify,
/// GitHub, Granola), Klay, then the conversations over at least 3/4 of the width. What a click on
/// an icon does to the focus, and where the GitHub and Spotify cards sit when they replace the list.
@main
enum HomeLayoutTests {
    static func main() {
        let cases: [(String, () -> Void)] = [
            ("rail_shows_spotify_and_github_only_when_set_and_granola_always", railIcons),
            ("rail_icons_name_service_pills_of_the_catalog", railIconsNameServicePills),
            ("list_takes_at_least_three_quarters_of_the_island", listTakesThreeQuarters),
            ("list_keeps_its_width_whatever_the_icons", listKeepsItsWidthWhateverTheIcons),
            ("klay_sits_in_his_column_where_the_island_draws_him", klaySitsInHisColumn),
            ("klay_touch_circle_leaves_the_rail_and_the_list_clickable", klayTouchCircleIsClear),
            ("service_cards_start_their_text_where_the_list_starts", serviceCardsLineUpWithTheList),
            ("only_github_and_spotify_replace_the_list", onlyGitHubAndSpotifyReplaceTheList),
            ("a_click_shows_the_card_a_second_click_the_list", aClickShowsTheCardASecondTheList),
            ("the_list_gives_the_focus_back", theListGivesTheFocusBack),
            ("a_request_that_leaves_gives_the_list_back", aRequestThatLeavesGivesTheListBack),
            ("pill_shortcuts_walk_the_list_then_the_rail_cards", pillShortcutsWalkTheListThenTheRailCards),
            ("digit_shortcuts_pick_the_list_or_a_rail_card", digitShortcutsPickTheListOrARailCard),
            ("a_row_at_the_centre_is_whole", aRowAtTheCentreIsWhole),
            ("rows_towards_the_edges_shrink_fade_and_move_aside", rowsTowardsTheEdgesShrinkFadeAndMoveAside),
            ("the_wheel_is_the_same_above_and_below", theWheelIsTheSameAboveAndBelow),
            ("the_wheel_changes_smoothly", theWheelChangesSmoothly),
            ("the_first_and_last_rows_can_reach_the_centre", theFirstAndLastRowsCanReachTheCentre),
            ("the_home_margins_come_from_the_layout", theHomeMarginsComeFromTheLayout),
        ]
        for (name, run) in cases {
            run()
            print("  ok  \(name)")
        }
        print("Home layout: \(cases.count) cases passed")
    }

    static let width = IslandConst.expandedWidth
    static let spotify = "integration_spotify"
    static let github = "integration_github"
    static let claudeCode = "integration_claude"
    static let desktop = "agent_claude-desktop"

    // MARK: - Rail

    static func railIcons() {
        precondition(HomeRail.icons(spotifyActive: true, githubConfigured: true) == [.spotify, .github, .granola],
                     "both services: Spotify, GitHub, then Granola")
        precondition(HomeRail.icons(spotifyActive: false, githubConfigured: true) == [.github, .granola],
                     "no Spotify: GitHub and Granola")
        precondition(HomeRail.icons(spotifyActive: true, githubConfigured: false) == [.spotify, .granola],
                     "no GitHub token: Spotify and Granola")
        precondition(HomeRail.icons(spotifyActive: false, githubConfigured: false) == [.granola],
                     "neither: Granola alone")
        // Claude Code and Claude Desktop never get an icon: their sessions are the list.
        precondition(RailIcon.allCases == [.spotify, .github, .granola])
    }

    static func railIconsNameServicePills() {
        precondition(RailIcon.spotify.pillId == spotify && RailIcon.github.pillId == github,
                     "the icons show the cards of the existing pills, ids unchanged")
        precondition(RailIcon.granola.pillId == nil, "Granola has no pill, it opens a note")
        for icon in RailIcon.allCases {
            guard let id = icon.pillId else { continue }
            precondition(PillCatalog.definition(for: id)?.category == .service,
                         "\(id) is a service pill of the catalog")
        }
        precondition(HomeRail.cardPillIds == [spotify, github])
    }

    // MARK: - Widths

    static func listTakesThreeQuarters() {
        let w = HomeLayout.widths(islandWidth: width)
        precondition(width == 640, "the open island is 640 pt wide")
        precondition(w.list >= 480, "the list takes at least 480 of 640 pt, got \(w.list)")
        precondition(w.list >= 0.75 * width)
        precondition(w.rail >= 28 && w.rail <= 40, "the rail is thin, about 36 pt, got \(w.rail)")
        // Klay (58 pt) fits his column with room on both sides.
        let diameter = IslandConst.viewLayouts[.overview]!.botDiameter
        precondition(w.klay >= diameter + 2 * 12, "Klay's column holds his \(diameter) pt and margins")
        // The three columns and the island's two 10 pt edges make the whole width.
        precondition(HomeLayout.edgeInset * 2 + w.rail + w.klay + w.list == width,
                     "nothing is lost or overlaps: \(w.rail) + \(w.klay) + \(w.list) + edges")
        precondition(HomeLayout.listStartX == HomeLayout.edgeInset + w.rail + w.klay)
    }

    static func listKeepsItsWidthWhateverTheIcons() {
        // No GitHub token and no Spotify: Granola alone, and the list is as wide as ever (the rail
        // keeps its width, empty slots included).
        let alone = HomeRail.icons(spotifyActive: false, githubConfigured: false)
        precondition(alone == [.granola])
        let list = HomeLayout.widths(islandWidth: width).list
        precondition(list >= 480 && list == width - 2 * HomeLayout.edgeInset - HomeLayout.rail - HomeLayout.klay,
                     "the widths depend on the island only, never on the icons shown")
        // A narrower island never gives a negative column.
        precondition(HomeLayout.widths(islandWidth: 100).list == 0)
    }

    // MARK: - Klay

    static func klaySitsInHisColumn() {
        let layout = IslandConst.viewLayouts[.overview]!
        precondition(layout.botX == HomeLayout.klayCenterX,
                     "the island draws Klay at the centre of his column: botX \(layout.botX), column centre \(HomeLayout.klayCenterX)")
        let w = HomeLayout.widths(islandWidth: width)
        let columnStart = HomeLayout.edgeInset + w.rail
        precondition(HomeLayout.klayCenterX == columnStart + w.klay / 2, "centred in his column")
        precondition(layout.botX - layout.botDiameter / 2 > columnStart
                     && layout.botX + layout.botDiameter / 2 < HomeLayout.listStartX,
                     "his body stays inside his column")
        precondition(layout.height == 220, "the home stays 220 pt tall")
    }

    static func klayTouchCircleIsClear() {
        // IslandWindowController takes a click inside Klay's canvas circle (diameter / 0.6) for a
        // slap: that circle must not cover a rail icon or the start of a row.
        let layout = IslandConst.viewLayouts[.overview]!
        let touchRadius = layout.botDiameter / 0.6 / 2
        let railIconRight = HomeLayout.edgeInset + HomeLayout.rail / 2 + HomeLayout.railIconWidth / 2
        precondition(layout.botX - touchRadius > railIconRight,
                     "the rail icons stay clickable: touch circle from \(layout.botX - touchRadius), icons to \(railIconRight)")
        precondition(layout.botX + touchRadius < HomeLayout.listStartX,
                     "the rows stay clickable: touch circle to \(layout.botX + touchRadius), list from \(HomeLayout.listStartX)")
        precondition(HomeLayout.railIconWidth <= HomeLayout.rail)
    }

    // MARK: - GitHub and Spotify cards in place of the list

    static func serviceCardsLineUpWithTheList() {
        // The cards keep their own drawing (text 108 pt in from their left edge, made for the 160
        // pt island): shifted by `serviceCardShift`, their text starts where the rows start.
        let cardLeft = HomeLayout.edgeInset + HomeLayout.rail
        precondition(cardLeft + HomeLayout.serviceCardShift + HomeLayout.serviceCardInset == HomeLayout.listStartX,
                     "a card's text starts at the list's left edge")
        precondition(HomeLayout.serviceCardInset == 108)
        // The shift never moves a card's text over Klay.
        let layout = IslandConst.viewLayouts[.overview]!
        precondition(cardLeft + HomeLayout.serviceCardShift + HomeLayout.serviceCardInset
                     > layout.botX + layout.botDiameter / 2)
    }

    static func onlyGitHubAndSpotifyReplaceTheList() {
        precondition(HomeRail.showsCard(focusId: github) && HomeRail.showsCard(focusId: spotify))
        for other in [nil, claudeCode, desktop, "agent_other", ""] as [String?] {
            precondition(!HomeRail.showsCard(focusId: other), "focus \(other ?? "nil") shows the list")
        }
    }

    static func aClickShowsTheCardASecondTheList() {
        precondition(HomeRail.action(for: .spotify, focusId: claudeCode) == .showCard(spotify))
        precondition(HomeRail.action(for: .github, focusId: nil) == .showCard(github))
        precondition(HomeRail.action(for: .spotify, focusId: spotify) == .showList,
                     "a second click on the icon in focus brings the list back")
        precondition(HomeRail.action(for: .github, focusId: github) == .showList)
        precondition(HomeRail.action(for: .github, focusId: spotify) == .showCard(github),
                     "another service's icon switches cards")
        for focus in [nil, claudeCode, spotify, github] as [String?] {
            precondition(HomeRail.action(for: .granola, focusId: focus) == .openGranola,
                         "Granola always opens a new note, the focus stays")
        }
    }

    static func theListGivesTheFocusBack() {
        let loaded = [claudeCode, desktop, github, spotify]
        precondition(HomeRail.listFocus(saved: desktop, loaded: loaded, main: claudeCode) == desktop,
                     "the pill in focus before the card gets it back (Klay takes its pose again)")
        precondition(HomeRail.listFocus(saved: nil, loaded: loaded, main: claudeCode) == claudeCode,
                     "nothing saved: the main pill")
        precondition(HomeRail.listFocus(saved: "agent_gone", loaded: loaded, main: claudeCode) == claudeCode,
                     "a pill that left since: the main pill")
        precondition(HomeRail.listFocus(saved: github, loaded: loaded, main: claudeCode) == claudeCode,
                     "never back to a card")
    }

    // MARK: - After a permission or a question (review fix 1)

    static func aRequestThatLeavesGivesTheListBack() {
        let loaded = [claudeCode, desktop, github, spotify]
        // The request took the screen from a pill of the list: that pill gets the focus back.
        precondition(HomeRail.focusAfterRequest(saved: desktop, beforeCard: nil, loaded: loaded, main: claudeCode)
                     == desktop)
        precondition(HomeRail.focusAfterRequest(saved: claudeCode, beforeCard: spotify, loaded: loaded, main: claudeCode)
                     == claudeCode)
        // It took the screen from GitHub's or Spotify's card: the home comes back on the list, with
        // the focus the card had taken.
        precondition(HomeRail.focusAfterRequest(saved: github, beforeCard: desktop, loaded: loaded, main: claudeCode)
                     == desktop, "a card in focus before the request gives the list back")
        precondition(HomeRail.focusAfterRequest(saved: spotify, beforeCard: nil, loaded: loaded, main: claudeCode)
                     == claudeCode, "nothing saved before the card: the main pill")
        for saved in [github, spotify] {
            let back = HomeRail.focusAfterRequest(saved: saved, beforeCard: github, loaded: loaded, main: claudeCode)
            precondition(!HomeRail.showsCard(focusId: back), "after a request the home never shows a card")
        }
    }

    // MARK: - Pill shortcuts (review fix 2): ⌃⌥] ⌃⌥[ ⌘→ ⌘← and ⌘1…9

    static func pillShortcutsWalkTheListThenTheRailCards() {
        let all = HomeRail.icons(spotifyActive: true, githubConfigured: true)
        precondition(HomeRail.cycleEntries(icons: all) == [nil, spotify, github],
                     "the list, then the cards of the rail in its order; Granola and the Claude pills are not entries")
        // Forward from the list, from a Claude pill or with no focus: Spotify, then GitHub, then the list.
        for focus in [nil, claudeCode, desktop] as [String?] {
            precondition(HomeRail.cycle(from: focus, by: 1, icons: all) == .showCard(spotify),
                         "from the list (\(focus ?? "nil")) the next entry is the first card")
        }
        precondition(HomeRail.cycle(from: spotify, by: 1, icons: all) == .showCard(github))
        precondition(HomeRail.cycle(from: github, by: 1, icons: all) == .showList, "after the last card, the list")
        // Backward wraps the other way.
        precondition(HomeRail.cycle(from: claudeCode, by: -1, icons: all) == .showCard(github))
        precondition(HomeRail.cycle(from: github, by: -1, icons: all) == .showCard(spotify))
        precondition(HomeRail.cycle(from: spotify, by: -1, icons: all) == .showList)
        // Only the cards the rail shows: no GitHub token, GitHub is skipped.
        let spotifyOnly = HomeRail.icons(spotifyActive: true, githubConfigured: false)
        precondition(HomeRail.cycleEntries(icons: spotifyOnly) == [nil, spotify])
        precondition(HomeRail.cycle(from: github, by: 1, icons: spotifyOnly) == .showCard(spotify),
                     "a card the rail does not show counts as the list")
        // Granola alone: the shortcuts stay on the list.
        let granolaOnly = HomeRail.icons(spotifyActive: false, githubConfigured: false)
        precondition(HomeRail.cycle(from: claudeCode, by: 1, icons: granolaOnly) == .showList)
        precondition(HomeRail.cycle(from: claudeCode, by: -1, icons: granolaOnly) == .showList)
    }

    static func digitShortcutsPickTheListOrARailCard() {
        let all = HomeRail.icons(spotifyActive: true, githubConfigured: true)
        precondition(HomeRail.entry(number: 1, icons: all) == .showList, "⌘1 is the list")
        precondition(HomeRail.entry(number: 2, icons: all) == .showCard(spotify), "⌘2 the first card of the rail")
        precondition(HomeRail.entry(number: 3, icons: all) == .showCard(github), "⌘3 the second")
        precondition(HomeRail.entry(number: 4, icons: all) == nil && HomeRail.entry(number: 0, icons: all) == nil,
                     "no entry: nothing happens")
        let githubOnly = HomeRail.icons(spotifyActive: false, githubConfigured: true)
        precondition(HomeRail.entry(number: 2, icons: githubOnly) == .showCard(github))
        precondition(HomeRail.entry(number: 3, icons: githubOnly) == nil)
    }

    // MARK: - The list as a wheel (Task 27)
    // Baptiste: « un défilement plus sympa en arc de cercle : en haut plus petit, en bas aussi plus
    // petit, au milieu gros au défilement ». `phase`: the scroll transition's value, 0 for a row at the
    // centre of the list, -1 and 1 for a row leaving at the top and at the bottom.

    static func aRowAtTheCentreIsWhole() {
        precondition(ListWheel.look(phase: 0) == ListWheel.Look(scale: 1, opacity: 1, xOffset: 0), "full size")
    }

    static func rowsTowardsTheEdgesShrinkFadeAndMoveAside() {
        let edge = ListWheel.look(phase: 1)
        precondition(abs(edge.scale - 0.78) < 1e-9 && abs(edge.opacity - 0.45) < 1e-9 && edge.xOffset == ListWheel.edgeShift,
                     "about 0.78 and 0.45 at the edges, got \(edge)")
        precondition(ListWheel.edgeShift > 0 && ListWheel.edgeShift <= 12, "a slight shift, so the list reads as an arc")
        precondition(ListWheel.look(phase: ListWheel.reach) == edge, "the edge look is reached before the very edge")
        precondition(ListWheel.look(phase: 3) == edge && ListWheel.look(phase: -3) == edge, "clamped past the edges")
    }

    static func theWheelIsTheSameAboveAndBelow() {
        for p in stride(from: 0.0, through: 1.0, by: 0.05) {
            precondition(ListWheel.look(phase: p) == ListWheel.look(phase: -p), "symmetric at \(p)")
        }
    }

    static func theWheelChangesSmoothly() {
        var previous = ListWheel.look(phase: 0)
        for p in stride(from: 0.02, through: 1.0, by: 0.02) {
            let look = ListWheel.look(phase: p)
            precondition(look.scale <= previous.scale && look.opacity <= previous.opacity
                         && look.xOffset >= previous.xOffset, "monotonic at \(p)")
            precondition(previous.scale - look.scale < 0.03, "no jump at \(p)")
            previous = look
        }
        let near = ListWheel.look(phase: 0.05)
        precondition(near.scale > 0.995, "a row next to the centre is nearly whole, got \(near.scale)")
    }

    static func theFirstAndLastRowsCanReachTheCentre() {
        precondition(ListWheel.centringMargin(viewport: 151, row: 26) == 62.5, "half the room left by a row")
        precondition(ListWheel.centringMargin(viewport: 20, row: 26) == 0, "never negative")
    }

    // MARK: - Hotfix 0.3.4: the home's margins are a layout constant
    // 0.3.3 measured the list's scroll view for its margins, and the measure fed its own layout: the
    // app crashed on macOS 27. The margins now come from the home's layout, checked against it here.

    static func theHomeMarginsComeFromTheLayout() {
        let island = IslandConst.viewLayouts[.overview]!.height
        // IslandContentView: 8 pt top, 34 pt header, 10 pt bottom; OverviewView's list: 9 pt top, 8 pt bottom.
        let card = island - 8 - 34 - 10
        precondition(card == 168, "the home's card is 168 pt, got \(card)")
        precondition(ListWheel.homeListHeight == card - 9 - 8,
                     "the list's height follows the home's layout, got \(ListWheel.homeListHeight)")
        precondition(ListWheel.homeMargin == 62.5, "the first row rests at the centre, got \(ListWheel.homeMargin)")
        precondition(ListWheel.homeMargin + ListWheel.rowHeight / 2 == ListWheel.homeListHeight / 2,
                     "the first row's middle is the list's middle")
    }
}

/// IslandTypes.swift (compiled here for `IslandConst`) names `EyeShape`, which BotEngine.swift
/// defines with SwiftUI. This stand-in lets it build with Foundation only.
enum EyeShape: Equatable {}
