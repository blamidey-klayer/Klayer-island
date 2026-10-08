import Foundation

/// The roster of running Claude sessions (spec §6, one row per session): newest activity
/// first, the last action kept and capped, rows removed when the session ends and pruned by
/// age without a timer, what a finished session does to an island that may be in use, and what a
/// row of the open island says and opens.
/// Tests pass explicit dates, never the wall clock.
@main
enum SessionRosterTests {
    static func main() {
        let cases: [(String, () -> Void)] = [
            ("newest_activity_first", newestActivityFirst),
            ("last_action_kept_when_nil_and_capped_at_80", lastActionKeptWhenNilAndCappedAt80),
            ("end_removes_the_row", endRemovesTheRow),
            ("prune_keeps_waiting_rows", pruneKeepsWaitingRows),
            ("visible_limit", visibleLimit),
            ("row_line_is_one_line_cut_with_an_ellipsis", rowLineIsOneLineCutWithAnEllipsis),
            ("finish_opens_a_hidden_or_compact_island", finishOpensAHiddenOrCompactIsland),
            ("finish_only_badges_while_a_card_waits", finishOnlyBadgesWhileACardWaits),
            ("finish_never_replaces_a_view_in_use", finishNeverReplacesAViewInUse),
            ("finish_replaces_a_resting_view_unless_pinned", finishReplacesARestingViewUnlessPinned),
            ("phase_labels_in_plain_french", phaseLabelsInPlainFrench),
            ("host_kept_when_nil_and_replaced_when_given", hostKeptWhenNilAndReplacedWhenGiven),
            ("session_host_is_the_routed_terminal_else_the_bundle", sessionHostIsTheRoutedTerminalElseTheBundle),
            ("row_opens_its_running_host_else_the_claude_app", rowOpensItsRunningHostElseTheClaudeApp),
            ("search_tools_raise_the_binoculars", searchToolsRaiseTheBinoculars),
            ("a_bash_search_raises_them_other_commands_work", aBashSearchRaisesThemOtherCommandsWork),
            ("post_tool_use_keeps_the_binoculars_1_5_s", postToolUseKeepsTheBinoculars15s),
            ("a_searching_row_is_pruned_like_a_working_one", aSearchingRowIsPrunedLikeAWorkingOne),
        ]
        for (name, run) in cases {
            run()
            print("  ok  \(name)")
        }
        print("Session roster: \(cases.count) cases passed")
    }

    static let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    static func at(minutes: Double) -> Date { t0.addingTimeInterval(minutes * 60) }

    static func ids(_ roster: SessionRoster) -> [String] { roster.rows.map(\.id) }

    static func newestActivityFirst() {
        var roster = SessionRoster()
        roster.update(sessionId: "a", pillId: "integration_claude", title: "Projet A", phase: .working,
                      lastAction: "Edits · A.swift", at: at(minutes: 0))
        roster.update(sessionId: "b", pillId: "agent_claude-desktop", title: "Projet B", phase: .thinking,
                      lastAction: "Écris les tests", at: at(minutes: 1))
        precondition(ids(roster) == ["b", "a"], "the session that acted last comes first, got \(ids(roster))")

        // New activity on "a" brings it back first, and updates its row instead of adding one.
        roster.update(sessionId: "a", pillId: "integration_claude", title: "Projet A", phase: .finished,
                      lastAction: "Terminé", at: at(minutes: 2))
        precondition(ids(roster) == ["a", "b"], "a session that acts again moves up, got \(ids(roster))")
        precondition(roster.rows.count == 2, "one row per session id")
        precondition(roster.rows[0].phase == .finished && roster.rows[0].lastAction == "Terminé"
                     && roster.rows[0].updatedAt == at(minutes: 2),
                     "the row holds the latest phase, action and date")
        precondition(roster.rows[1].pillId == "agent_claude-desktop" && roster.rows[1].title == "Projet B",
                     "the other row is untouched")

        // Same date: the later call is the newer activity.
        roster.update(sessionId: "b", pillId: "agent_claude-desktop", title: "Projet B", phase: .working,
                      lastAction: nil, at: at(minutes: 2))
        precondition(ids(roster) == ["b", "a"], "on equal dates the latest call comes first, got \(ids(roster))")
    }

    static func lastActionKeptWhenNilAndCappedAt80() {
        var roster = SessionRoster()
        roster.update(sessionId: "a", pillId: "integration_claude", title: "Projet A", phase: .working,
                      lastAction: "Bash · npm test", at: at(minutes: 0))
        roster.update(sessionId: "a", pillId: "integration_claude", title: "Projet A", phase: .error,
                      lastAction: nil, at: at(minutes: 1))
        precondition(roster.rows[0].lastAction == "Bash · npm test",
                     "a nil last action keeps the previous one")
        precondition(roster.rows[0].phase == .error, "the phase still changes")

        // A session seen for the first time with no action starts with an empty one.
        roster.update(sessionId: "b", pillId: "integration_claude", title: "Projet B", phase: .idle,
                      lastAction: nil, at: at(minutes: 2))
        precondition(roster.rows[0].id == "b" && roster.rows[0].lastAction.isEmpty,
                     "no previous action and no new one: empty")

        let long = String(repeating: "é", count: 200)
        roster.update(sessionId: "a", pillId: "integration_claude", title: "Projet A", phase: .working,
                      lastAction: long, at: at(minutes: 3))
        precondition(roster.rows[0].lastAction.count == 80,
                     "a long action is cut to 80 characters, got \(roster.rows[0].lastAction.count)")
        precondition(roster.rows[0].lastAction == String(long.prefix(80)), "the start of the action is kept")

        let exact = String(repeating: "x", count: 80)
        roster.update(sessionId: "a", pillId: "integration_claude", title: "Projet A", phase: .working,
                      lastAction: exact, at: at(minutes: 4))
        precondition(roster.rows[0].lastAction == exact, "80 characters fit as they are")

        // The cap counts characters, not bytes: an emoji or an accent is one.
        let accents = String(repeating: "👩‍💻", count: 100)
        roster.update(sessionId: "a", pillId: "integration_claude", title: "Projet A", phase: .working,
                      lastAction: accents, at: at(minutes: 5))
        precondition(roster.rows[0].lastAction.count == 80, "the cap counts characters")
    }

    static func endRemovesTheRow() {
        var roster = SessionRoster()
        roster.update(sessionId: "a", pillId: "integration_claude", title: "Projet A", phase: .working,
                      lastAction: "x", at: at(minutes: 0))
        roster.update(sessionId: "b", pillId: "integration_claude", title: "Projet B", phase: .working,
                      lastAction: "y", at: at(minutes: 1))
        roster.end(sessionId: "a")
        precondition(ids(roster) == ["b"], "the ended session leaves, the other stays, got \(ids(roster))")
        roster.end(sessionId: "a")
        roster.end(sessionId: "unknown")
        precondition(ids(roster) == ["b"], "ending a session twice, or one never seen, changes nothing")
        roster.end(sessionId: "b")
        precondition(roster.rows.isEmpty)
    }

    static func pruneKeepsWaitingRows() {
        var roster = SessionRoster()
        // Updated at minute 0; each prune below happens at the stated age.
        roster.update(sessionId: "question", pillId: "integration_claude", title: "Q", phase: .question,
                      lastAction: "Quelle option ?", at: at(minutes: 0))
        roster.update(sessionId: "approval", pillId: "integration_claude", title: "A", phase: .approval,
                      lastAction: "rm -rf build", at: at(minutes: 0))
        roster.update(sessionId: "finished", pillId: "integration_claude", title: "F", phase: .finished,
                      lastAction: "Terminé", at: at(minutes: 0))
        roster.update(sessionId: "working", pillId: "integration_claude", title: "W", phase: .working,
                      lastAction: "Edits · A.swift", at: at(minutes: 0))
        roster.update(sessionId: "error", pillId: "integration_claude", title: "E", phase: .error,
                      lastAction: nil, at: at(minutes: 0))
        roster.update(sessionId: "idle", pillId: "integration_claude", title: "I", phase: .idle,
                      lastAction: "Session démarrée", at: at(minutes: 0))

        roster.prune(now: at(minutes: 29))
        precondition(roster.rows.count == 6, "nothing is pruned before 30 minutes, got \(ids(roster))")

        // 31 minutes: finished, error and idle rows go; a working row (a long task) stays.
        roster.prune(now: at(minutes: 31))
        precondition(Set(ids(roster)) == ["question", "approval", "working"],
                     "finished, error and idle rows go after 30 minutes, got \(ids(roster))")

        // 3 hours: the working row goes too, the rows waiting for the user stay.
        roster.prune(now: at(minutes: 180))
        precondition(Set(ids(roster)) == ["question", "approval"],
                     "a question and an approval stay however old, got \(ids(roster))")

        // A row is pruned once it reaches the limit: exactly 30 minutes for a finished one.
        var edge = SessionRoster()
        edge.update(sessionId: "f", pillId: "integration_claude", title: "F", phase: .finished,
                    lastAction: nil, at: at(minutes: 0))
        edge.prune(now: at(minutes: 30))
        precondition(edge.rows.isEmpty, "a finished row goes at exactly 30 minutes without activity")

        // The ages are measured from the last activity of each row.
        var fresh = SessionRoster()
        fresh.update(sessionId: "old", pillId: "integration_claude", title: "O", phase: .finished,
                     lastAction: nil, at: at(minutes: 0))
        fresh.update(sessionId: "old", pillId: "integration_claude", title: "O", phase: .finished,
                     lastAction: nil, at: at(minutes: 25))
        fresh.prune(now: at(minutes: 31))
        precondition(ids(fresh) == ["old"], "a row touched 6 minutes ago is not pruned")
        // 119 minutes for a working row: still there, 120: gone.
        fresh.update(sessionId: "w", pillId: "integration_claude", title: "W", phase: .thinking,
                     lastAction: nil, at: at(minutes: 31))
        fresh.prune(now: at(minutes: 31 + 119))
        precondition(ids(fresh).contains("w"), "a thinking row survives 119 minutes without activity")
        fresh.prune(now: at(minutes: 31 + 120))
        precondition(!ids(fresh).contains("w"), "a thinking row goes after 2 hours without activity")
    }

    static func visibleLimit() {
        var roster = SessionRoster()
        for n in 1...6 {
            roster.update(sessionId: "s\(n)", pillId: "integration_claude", title: "P\(n)", phase: .working,
                          lastAction: nil, at: at(minutes: Double(n)))
        }
        precondition(roster.visible(limit: 4).map(\.id) == ["s6", "s5", "s4", "s3"],
                     "the limit keeps the newest rows")
        precondition(roster.visible(limit: 10).count == 6, "a limit above the count returns every row")
        precondition(roster.visible(limit: 0).isEmpty, "a limit of 0 returns nothing")
        precondition(roster.visible(limit: -3).isEmpty, "a negative limit returns nothing instead of crashing")
        precondition(roster.rows.count == 6, "visible does not remove rows")
    }

    // MARK: - One line for a row

    static func rowLineIsOneLineCutWithAnEllipsis() {
        precondition(SessionRoster.line("Bash · npm test") == "Bash · npm test", "a short text is kept")
        precondition(SessionRoster.line("première ligne\n\nseconde\tligne") == "première ligne seconde ligne",
                     "line breaks and tabs become one space")
        precondition(SessionRoster.line("") == nil && SessionRoster.line("  \n\t ") == nil,
                     "nothing to show is nil, so the row keeps its last action")
        let exact = String(repeating: "x", count: 80)
        precondition(SessionRoster.line(exact) == exact, "80 characters fit without an ellipsis")
        let long = SessionRoster.line(String(repeating: "é", count: 200)) ?? ""
        precondition(long.count == 80 && long.hasSuffix("…"),
                     "a longer text is cut to 80 characters, the ellipsis included, got \(long.count)")
        precondition(long == String(repeating: "é", count: 79) + "…", "the start of the text is kept")

        // The line survives `update` as it is: the ellipsis is not cut off again.
        var roster = SessionRoster()
        roster.update(sessionId: "a", pillId: "integration_claude", title: "A", phase: .working,
                      lastAction: long, at: at(minutes: 0))
        precondition(roster.rows[0].lastAction == long, "an 80 character line is stored whole")
    }

    // MARK: - What a finished session does to the island

    /// Every IslandView raw value, by group, as the island names them.
    static let restingViews = ["overview", "empty", "note", "greeting", "confused", "finished", "error"]
    static let viewsInUse = ["prompt", "mail", "upload", "uploading", "choose", "searching", "result", "settings"]
    static let cardViews = ["approval", "question"]

    static func finishOpensAHiddenOrCompactIsland() {
        for view in restingViews + viewsInUse + cardViews {
            // The view of a closed island is the one it had when it closed: it does not matter.
            precondition(FinishPresentation.decide(expanded: false, view: view, pinned: false,
                                                   requestPending: false) == .open,
                         "a hidden or compact island opens whatever view it kept, got a refusal on \(view)")
        }
        precondition(FinishPresentation.decide(expanded: false, view: "overview", pinned: true,
                                               requestPending: false) == .open,
                     "a pin left from an earlier opening does not keep a closed island shut")
    }

    static func finishOnlyBadgesWhileACardWaits() {
        for expanded in [false, true] {
            for view in restingViews + viewsInUse + cardViews {
                for pinned in [false, true] {
                    precondition(FinishPresentation.decide(expanded: expanded, view: view, pinned: pinned,
                                                           requestPending: true) == .badgeOnly,
                                 "a waiting permission or question is never covered (expanded \(expanded), \(view))")
                }
            }
        }
        // The card views stay protected even when the pending flag is not read yet.
        for view in cardViews {
            precondition(FinishPresentation.decide(expanded: true, view: view, pinned: false,
                                                   requestPending: false) == .badgeOnly,
                         "the \(view) view is never replaced")
        }
    }

    static func finishNeverReplacesAViewInUse() {
        for view in viewsInUse {
            for pinned in [false, true] {
                precondition(FinishPresentation.decide(expanded: true, view: view, pinned: pinned,
                                                       requestPending: false) == .badgeOnly,
                             "a finish must not destroy what the user is writing or choosing in \(view)")
            }
        }
    }

    static func finishReplacesARestingViewUnlessPinned() {
        for view in restingViews {
            precondition(FinishPresentation.decide(expanded: true, view: view, pinned: false,
                                                   requestPending: false) == .open,
                         "the \(view) view gives way to the end of a session")
            precondition(FinishPresentation.decide(expanded: true, view: view, pinned: true,
                                                   requestPending: false) == .badgeOnly,
                         "an island pinned with ⌘P keeps its view, the \(view) view included")
        }
        // A view this code does not know is treated as in use: nothing is destroyed by surprise.
        precondition(FinishPresentation.decide(expanded: true, view: "somethingNew", pinned: false,
                                               requestPending: false) == .badgeOnly)
    }

    // MARK: - A row of the open island

    static func phaseLabelsInPlainFrench() {
        let expected: [(SessionPhase, String)] = [
            (.idle, "En attente"), (.thinking, "Réfléchit"), (.working, "Travaille"), (.searching, "Cherche"),
            (.approval, "Attend ton accord"), (.question, "Te pose une question"),
            (.ratelimit, "Limite atteinte"), (.error, "Erreur"), (.finished, "Terminé"),
        ]
        precondition(Set(expected.map(\.0)) == Set(SessionPhase.allCases), "every phase has a label")
        for (phase, label) in expected {
            precondition(phase.label == label, "\(phase) reads « \(label) », got « \(phase.label) »")
            precondition(!phase.label.contains("\u{2014}"), "no em dash in a label")
        }
    }

    static func hostKeptWhenNilAndReplacedWhenGiven() {
        var roster = SessionRoster()
        roster.update(sessionId: "a", pillId: "integration_claude", title: "A", phase: .working,
                      lastAction: "x", hostBundleId: "dev.warp.Warp-Stable", at: at(minutes: 0))
        precondition(roster.rows[0].hostBundleId == "dev.warp.Warp-Stable", "the row holds the host of its session")

        roster.update(sessionId: "a", pillId: "integration_claude", title: "A", phase: .finished,
                      lastAction: "Fini", at: at(minutes: 1))
        precondition(roster.rows[0].hostBundleId == "dev.warp.Warp-Stable",
                     "an event that names no host keeps the one the session had")

        roster.update(sessionId: "a", pillId: "integration_claude", title: "A", phase: .working,
                      lastAction: nil, hostBundleId: "com.apple.Terminal", at: at(minutes: 2))
        precondition(roster.rows[0].hostBundleId == "com.apple.Terminal", "a new host replaces the old one")

        // Each session keeps its own host: two sessions of the same pill in two terminals.
        roster.update(sessionId: "b", pillId: "integration_claude", title: "B", phase: .working,
                      lastAction: nil, hostBundleId: "com.googlecode.iterm2", at: at(minutes: 3))
        roster.update(sessionId: "c", pillId: "integration_claude", title: "C", phase: .idle,
                      lastAction: nil, at: at(minutes: 4))
        let hosts = roster.rows.map(\.hostBundleId)
        precondition(hosts == [nil, "com.googlecode.iterm2", "com.apple.Terminal"],
                     "a new session without host has none, the others keep theirs, got \(hosts)")
    }

    static func sessionHostIsTheRoutedTerminalElseTheBundle() {
        precondition(SessionRoster.host(routed: "dev.warp.Warp-Stable", bundleId: "") == "dev.warp.Warp-Stable",
                     "a terminal found from TERM_PROGRAM is the host")
        precondition(SessionRoster.host(routed: "com.mitchellh.ghostty", bundleId: "com.example.other")
                     == "com.mitchellh.ghostty", "the routed terminal wins over the bundle id")
        precondition(SessionRoster.host(routed: nil, bundleId: "com.microsoft.VSCode") == "com.microsoft.VSCode",
                     "an editor session has its bundle id as host")
        precondition(SessionRoster.host(routed: nil, bundleId: "") == nil, "no host known: nil")
        precondition(SessionRoster.host(routed: nil, bundleId: "  \n") == nil, "a blank bundle id is no host")
    }

    static func rowOpensItsRunningHostElseTheClaudeApp() {
        func row(_ pillId: String, host: String?) -> SessionRow {
            SessionRow(id: "s", pillId: pillId, title: "P", phase: .finished, lastAction: "",
                       updatedAt: t0, hostBundleId: host)
        }
        let running: Set<String> = ["dev.warp.Warp-Stable", "com.microsoft.VSCode", "com.anthropic.claudefordesktop"]

        precondition(row("integration_claude", host: "dev.warp.Warp-Stable").openTarget(running: running)
                     == .host(bundleId: "dev.warp.Warp-Stable"),
                     "a Claude Code session brings its own terminal forward")
        precondition(row("integration_claude", host: "com.microsoft.VSCode").openTarget(running: running)
                     == .host(bundleId: "com.microsoft.VSCode"), "or its editor")
        precondition(row("integration_claude", host: "com.apple.Terminal").openTarget(running: running) == .claudeApp,
                     "a host that is not running any more falls back to the Claude app")
        precondition(row("integration_claude", host: nil).openTarget(running: running) == .claudeApp,
                     "no host known: the Claude app")
        precondition(row(HookRouting.desktopPillId, host: "com.anthropic.claudefordesktop")
                     .openTarget(running: running) == .claudeApp,
                     "a session of the Claude app opens the Claude app, whatever its host")
    }

    // MARK: - Binoculars (review I1, spec §7 « Cherche »)

    static func searchToolsRaiseTheBinoculars() {
        for tool in ["Grep", "Glob", "LS", "WebSearch", "WebFetch"] {
            precondition(SessionPhase.of(tool: tool, input: [:]) == .searching, "\(tool) is a search")
        }
        for tool in ["Edit", "Write", "Read", "Task", "TodoWrite", "mcp__github__search_issues"] {
            precondition(SessionPhase.of(tool: tool, input: [:]) == .working, "\(tool) works")
        }
    }

    static func aBashSearchRaisesThemOtherCommandsWork() {
        for command in ["rg TODO", "grep -rn foo src", "find . -name '*.swift'", "fd Package", "ls -la", "tree -L 2"] {
            precondition(SessionPhase.of(tool: "Bash", input: ["command": command]) == .searching,
                         "« \(command) » is a search")
            precondition(BashVerb.of(command) == .searches)
        }
        for command in ["npm test", "cat README.md", "swift build", "git status", ""] {
            precondition(SessionPhase.of(tool: "Bash", input: ["command": command]) == .working,
                         "« \(command) » works")
        }
        precondition(SessionPhase.of(tool: "Bash", input: [:]) == .working, "no command: working")
        precondition(BashVerb.of("cat a.txt") == .reads && BashVerb.of("npm test") == .tests
                     && BashVerb.of("make") == .runs, "the step labels keep their verbs")
    }

    static func postToolUseKeepsTheBinoculars15s() {
        // A Grep lasts about 100 ms: PostToolUse must not put Klay back on working before the
        // binoculars could be seen. No timer: the PostToolUse compares the dates.
        let start = t0
        precondition(SessionPhase.postToolUseKeepsSearching(searchingSince: start, now: start.addingTimeInterval(0.1)))
        precondition(SessionPhase.postToolUseKeepsSearching(searchingSince: start, now: start.addingTimeInterval(1.49)))
        precondition(!SessionPhase.postToolUseKeepsSearching(searchingSince: start, now: start.addingTimeInterval(1.5)),
                     "after 1.5 s, PostToolUse puts Klay back on working")
        precondition(!SessionPhase.postToolUseKeepsSearching(searchingSince: nil, now: start),
                     "not searching: PostToolUse works as before")
        precondition(SessionPhase.searchDwell == 1.5)
    }

    static func aSearchingRowIsPrunedLikeAWorkingOne() {
        var roster = SessionRoster()
        roster.update(sessionId: "s", pillId: "integration_claude", title: "S", phase: .searching,
                      lastAction: "Searches · TODO", at: at(minutes: 0))
        roster.prune(now: at(minutes: 31))
        precondition(roster.rows.count == 1, "a search is work in progress, not an ended session")
        roster.prune(now: at(minutes: 121))
        precondition(roster.rows.isEmpty, "after 2 hours of silence it goes like a working row")
    }
}
