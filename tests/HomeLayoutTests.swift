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
}

/// IslandTypes.swift (compiled here for `IslandConst`) names `EyeShape`, which BotEngine.swift
/// defines with SwiftUI. This stand-in lets it build with Foundation only.
enum EyeShape: Equatable {}
