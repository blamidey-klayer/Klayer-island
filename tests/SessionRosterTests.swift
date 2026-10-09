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
            ("a_failure_says_the_error_claude_shows", aFailureSaysTheErrorClaudeShows),
            ("a_failure_without_text_has_none", aFailureWithoutTextHasNone),
            ("a_request_is_named_after_its_session", aRequestIsNamedAfterItsSession),
            ("a_new_prompt_folds_only_its_own_finished_view", aNewPromptFoldsOnlyItsOwnFinishedView),
            ("every_view_string_is_a_real_island_view", everyViewStringIsARealIslandView),
            ("finished_rows_stay_until_midnight_of_their_day", finishedRowsStayUntilMidnight),
            ("midnight_is_the_user_calendar_s", midnightIsTheUserCalendars),
            ("ten_finished_rows_at_most_the_most_recent", tenFinishedRowsAtMost),
            ("active_rows_come_before_finished_ones", activeRowsComeBeforeFinishedOnes),
            ("a_session_that_ends_keeps_its_finished_row", aSessionThatEndsKeepsItsFinishedRow),
            ("a_finished_row_says_when_it_ended", aFinishedRowSaysWhenItEnded),
            ("a_session_goes_by_its_custom_title_then_its_status_line_name_then_its_folder",
             aSessionGoesByItsCustomTitleThenItsStatusLineNameThenItsFolder),
            ("a_later_custom_title_replaces_an_ai_title", aLaterCustomTitleReplacesAnAITitle),
            ("an_empty_name_never_replaces_a_known_one", anEmptyNameNeverReplacesAKnownOne),
            ("a_name_is_one_line_of_120_characters_at_most", aNameIsOneLineOf120CharactersAtMost),
            ("a_name_before_its_row_is_applied_when_the_row_appears", aNameBeforeItsRowIsAppliedWhenTheRowAppears),
            ("names_go_with_their_row", namesGoWithTheirRow),
            ("a_name_without_a_row_is_kept_30_min", aNameWithoutARowIsKept30Min),
            ("a_request_goes_by_its_session_s_name", aRequestGoesByItsSessionsName),
        ]
        for (name, run) in cases {
            run()
            print("  ok  \(name)")
        }
        print("Session roster: \(cases.count) cases passed")
    }

    /// 15 January 2027, 08:00 UTC.
    static let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    static func at(minutes: Double) -> Date { t0.addingTimeInterval(minutes * 60) }

    /// The user's calendar, pinned: midnight is the one of this time zone, never the test machine's.
    static func calendar(_ zone: String) -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: zone)!
        return c
    }

    static let utc = calendar("UTC")

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

        roster.prune(now: at(minutes: 29), calendar: utc)
        precondition(roster.rows.count == 6, "nothing is pruned before 30 minutes, got \(ids(roster))")

        // 31 minutes: the idle row goes; a working row (a long task) stays, and so do the finished
        // and failed ones (the history of the day, until midnight).
        roster.prune(now: at(minutes: 31), calendar: utc)
        precondition(Set(ids(roster)) == ["question", "approval", "working", "finished", "error"],
                     "an idle row goes after 30 minutes, got \(ids(roster))")

        // 3 hours: the working row goes too, the rows waiting for the user stay, the day's ended
        // rows stay.
        roster.prune(now: at(minutes: 180), calendar: utc)
        precondition(Set(ids(roster)) == ["question", "approval", "finished", "error"],
                     "a question and an approval stay however old, got \(ids(roster))")

        // Midnight (16 hours after 08:00): the ended rows go, the waiting ones still stay.
        roster.prune(now: at(minutes: 16 * 60), calendar: utc)
        precondition(Set(ids(roster)) == ["question", "approval"],
                     "the day's ended rows go at midnight, got \(ids(roster))")

        // A row is pruned once it reaches the limit: exactly 30 minutes for an idle one.
        var edge = SessionRoster()
        edge.update(sessionId: "i", pillId: "integration_claude", title: "I", phase: .idle,
                    lastAction: nil, at: at(minutes: 0))
        edge.prune(now: at(minutes: 30), calendar: utc)
        precondition(edge.rows.isEmpty, "an idle row goes at exactly 30 minutes without activity")

        // The ages are measured from the last activity of each row.
        var fresh = SessionRoster()
        fresh.update(sessionId: "old", pillId: "integration_claude", title: "O", phase: .idle,
                     lastAction: nil, at: at(minutes: 0))
        fresh.update(sessionId: "old", pillId: "integration_claude", title: "O", phase: .idle,
                     lastAction: nil, at: at(minutes: 25))
        fresh.prune(now: at(minutes: 31), calendar: utc)
        precondition(ids(fresh) == ["old"], "a row touched 6 minutes ago is not pruned")
        // 119 minutes for a working row: still there, 120: gone.
        fresh.update(sessionId: "w", pillId: "integration_claude", title: "W", phase: .thinking,
                     lastAction: nil, at: at(minutes: 31))
        fresh.prune(now: at(minutes: 31 + 119), calendar: utc)
        precondition(ids(fresh).contains("w"), "a thinking row survives 119 minutes without activity")
        fresh.prune(now: at(minutes: 31 + 120), calendar: utc)
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
    static let viewsInUse = ["prompt", "mail", "upload", "uploading", "choose", "settings"]
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
        roster.prune(now: at(minutes: 31), calendar: utc)
        precondition(roster.rows.count == 1, "a search is work in progress, not an ended session")
        roster.prune(now: at(minutes: 121), calendar: utc)
        precondition(roster.rows.isEmpty, "after 2 hours of silence it goes like a working row")
    }

    // MARK: - What the error view says (review I6)

    static func aFailureSaysTheErrorClaudeShows() {
        // The StopFailure input of the Claude Code hooks reference: `error` (the type),
        // optional `error_details`, optional `last_assistant_message` (the rendered error text).
        let full: [String: Any] = ["hook_event_name": "StopFailure", "error": "rate_limit",
                                   "error_details": "429 Too Many Requests",
                                   "last_assistant_message": "API Error: Rate limit reached"]
        precondition(SessionRoster.failureText(of: full) == "API Error: Rate limit reached",
                     "the error text Claude shows comes first")
        precondition(SessionRoster.failureText(of: ["error": "server_error", "error_details": "500 Internal\nServer Error"])
                     == "500 Internal Server Error", "then the details, on one line")
        precondition(SessionRoster.failureText(of: ["error": "billing_error", "last_assistant_message": "  "])
                     == "billing_error", "then the error type")
        let long = SessionRoster.failureText(of: ["last_assistant_message": String(repeating: "x", count: 200)]) ?? ""
        precondition(long.count == SessionRoster.lastActionLimit && long.hasSuffix("…"), "cut like a row line")
    }

    static func aFailureWithoutTextHasNone() {
        precondition(SessionRoster.failureText(of: ["hook_event_name": "StopFailure"]) == nil)
        precondition(SessionRoster.failureText(of: ["error": "", "error_details": 42]) == nil,
                     "empty or non-text fields say nothing: the view says no details are available")
    }

    // MARK: - Who asks (review M4)

    static func aRequestIsNamedAfterItsSession() {
        // The card and the history name the session of the request, whatever the shared pill is
        // called now (another session of the Claude app pill may have renamed it).
        var roster = SessionRoster()
        roster.update(sessionId: "A", pillId: "agent_claude-desktop", title: "Projet A", phase: .approval,
                      lastAction: "Write · a.txt", at: at(minutes: 0))
        roster.update(sessionId: "B", pillId: "agent_claude-desktop", title: "Projet B", phase: .working,
                      lastAction: nil, at: at(minutes: 1))
        precondition(SessionRoster.title(of: "A", in: roster.rows, fallback: "Projet B") == "Projet A")
        precondition(SessionRoster.title(of: "gone", in: roster.rows, fallback: "Claude Desktop") == "Claude Desktop",
                     "a session without a row falls back to the pill's name")
        precondition(SessionRoster.title(of: nil, in: roster.rows, fallback: "Session") == "Session")
    }

    // MARK: - A finished view that went stale (review M5)

    static func aNewPromptFoldsOnlyItsOwnFinishedView() {
        precondition(FinishPresentation.newPromptFoldsFinished(expanded: true, view: "finished",
                                                               finishedSessionId: "A", promptSessionId: "A"),
                     "the session that finished starts a new turn: its finished view is stale")
        precondition(!FinishPresentation.newPromptFoldsFinished(expanded: true, view: "finished",
                                                                finishedSessionId: "A", promptSessionId: "B"),
                     "another session's prompt leaves it")
        precondition(!FinishPresentation.newPromptFoldsFinished(expanded: true, view: "overview",
                                                                finishedSessionId: "A", promptSessionId: "A"),
                     "only the finished view")
        precondition(!FinishPresentation.newPromptFoldsFinished(expanded: false, view: "finished",
                                                                finishedSessionId: "A", promptSessionId: "A"),
                     "a folded island has nothing to fold")
        precondition(!FinishPresentation.newPromptFoldsFinished(expanded: true, view: "finished",
                                                                finishedSessionId: nil, promptSessionId: "A"))
    }

    /// FinishPresentation decides on raw strings, as HookServer passes `state.view.rawValue`:
    /// renaming an IslandView case would silently change the rule. Each string must name a case.
    static func everyViewStringIsARealIslandView() {
        for raw in FinishPresentation.replaceableViews {
            precondition(IslandView(rawValue: raw) != nil, "\(raw) is not an IslandView case")
        }
        // The finished view a new prompt folds.
        precondition(IslandView.finished.rawValue == "finished")
        // The lists these tests use name real views too, so they cannot rot either.
        for raw in restingViews + viewsInUse + cardViews {
            precondition(IslandView(rawValue: raw) != nil, "\(raw) is not an IslandView case")
        }
        precondition(Set(restingViews) == FinishPresentation.replaceableViews)
        // And together they name every view: one added or removed later lands in a group here.
        precondition(Set(restingViews + viewsInUse + cardViews) == Set(IslandView.allCases.map(\.rawValue)),
                     "every IslandView case is in exactly one group of these tests")
        precondition(restingViews.count + viewsInUse.count + cardViews.count == IslandView.allCases.count)
    }

    // MARK: - The day's ended sessions (lot 6 spec §2)

    static func finishedRowsStayUntilMidnight() {
        // t0 is 08:00 UTC: midnight comes 16 hours later, at minute 960.
        var roster = SessionRoster()
        roster.update(sessionId: "f", pillId: "integration_claude", title: "F", phase: .finished,
                      lastAction: "Fini", at: at(minutes: 0))
        roster.update(sessionId: "e", pillId: "agent_claude-desktop", title: "E", phase: .error,
                      lastAction: "API Error", at: at(minutes: 1))
        roster.prune(now: at(minutes: 959), calendar: utc)
        precondition(Set(ids(roster)) == ["f", "e"], "a finished and a failed row stay all day, got \(ids(roster))")
        roster.prune(now: at(minutes: 960), calendar: utc)
        precondition(roster.rows.isEmpty, "at midnight they go, got \(ids(roster))")

        // Finished at 23:50, yesterday's after midnight: gone, though only 20 minutes old.
        var late = SessionRoster()
        late.update(sessionId: "late", pillId: "integration_claude", title: "L", phase: .finished,
                    lastAction: nil, at: at(minutes: 950))
        late.prune(now: at(minutes: 959), calendar: utc)
        precondition(ids(late) == ["late"], "still today at 23:59")
        late.prune(now: at(minutes: 970), calendar: utc)
        precondition(late.rows.isEmpty, "a row finished yesterday is gone after midnight")

        // Finished just after midnight: the whole new day.
        var early = SessionRoster()
        early.update(sessionId: "early", pillId: "integration_claude", title: "E", phase: .finished,
                     lastAction: nil, at: at(minutes: 965))
        early.prune(now: at(minutes: 960 + 24 * 60 - 1), calendar: utc)
        precondition(ids(early) == ["early"], "kept until 23:59 of its own day")

        // A clock set back (now before the end) removes nothing.
        early.prune(now: at(minutes: 0), calendar: utc)
        precondition(ids(early) == ["early"], "a clock set back keeps the row")

        // A finished row that works again is an active row with the active rules.
        var again = SessionRoster()
        again.update(sessionId: "a", pillId: "integration_claude", title: "A", phase: .finished,
                     lastAction: nil, at: at(minutes: 0))
        again.update(sessionId: "a", pillId: "integration_claude", title: "A", phase: .working,
                     lastAction: nil, at: at(minutes: 5))
        again.prune(now: at(minutes: 5 + 120), calendar: utc)
        precondition(again.rows.isEmpty, "a working row goes after 2 hours, even if it had finished before")
    }

    static func midnightIsTheUserCalendars() {
        // 08:00 UTC is 09:00 in Paris (UTC+1 in January): Paris' midnight is 23:00 UTC, minute 900.
        let paris = calendar("Europe/Paris")
        var roster = SessionRoster()
        roster.update(sessionId: "f", pillId: "integration_claude", title: "F", phase: .finished,
                      lastAction: nil, at: at(minutes: 0))
        var inParis = roster
        inParis.prune(now: at(minutes: 899), calendar: paris)
        precondition(ids(inParis) == ["f"], "23:59 in Paris: still today")
        inParis.prune(now: at(minutes: 900), calendar: paris)
        precondition(inParis.rows.isEmpty, "midnight in Paris: gone")
        roster.prune(now: at(minutes: 900), calendar: utc)
        precondition(ids(roster) == ["f"], "the same instant is 23:00 in UTC: still today there")

        // 08:00 UTC is midnight in Los Angeles: a row finished one minute before is yesterday's.
        let losAngeles = calendar("America/Los_Angeles")
        var west = SessionRoster()
        west.update(sessionId: "w", pillId: "integration_claude", title: "W", phase: .error,
                    lastAction: nil, at: at(minutes: -1))
        west.prune(now: at(minutes: 0), calendar: losAngeles)
        precondition(west.rows.isEmpty, "midnight in Los Angeles ends the day of a row that ended at 23:59 there")

        // The day the clocks go forward in Paris (28 March 2027) has 23 hours: its midnight is
        // 22:00 UTC, not 23:00.
        let start = utc.date(from: DateComponents(year: 2027, month: 3, day: 28, hour: 0, minute: 30))!
        var spring = SessionRoster()
        spring.update(sessionId: "s", pillId: "integration_claude", title: "S", phase: .finished,
                      lastAction: nil, at: start)
        spring.prune(now: start.addingTimeInterval((21 * 60 + 29) * 60), calendar: paris)
        precondition(ids(spring) == ["s"], "21:59 UTC is 23:59 in Paris: still today")
        spring.prune(now: start.addingTimeInterval((21 * 60 + 30) * 60), calendar: paris)
        precondition(spring.rows.isEmpty, "22:00 UTC is midnight in Paris that day")

        // The day the clocks go back in Paris (31 October 2027) has 25 hours: a row finished at
        // 00:30 (22:30 UTC the day before) stays until 23:00 UTC, not 22:00.
        let autumn = utc.date(from: DateComponents(year: 2027, month: 10, day: 30, hour: 22, minute: 30))!
        var fall = SessionRoster()
        fall.update(sessionId: "a", pillId: "integration_claude", title: "A", phase: .error,
                    lastAction: nil, at: autumn)
        fall.prune(now: autumn.addingTimeInterval(24 * 60 * 60), calendar: paris)
        precondition(ids(fall) == ["a"], "22:30 UTC is 23:30 in Paris: 24 hours later, still the same 25 hour day")
        fall.prune(now: autumn.addingTimeInterval((24 * 60 + 29) * 60), calendar: paris)
        precondition(ids(fall) == ["a"], "22:59 UTC is 23:59 in Paris: still today")
        fall.prune(now: autumn.addingTimeInterval((24 * 60 + 30) * 60), calendar: paris)
        precondition(fall.rows.isEmpty, "23:00 UTC is midnight in Paris that day")
    }

    static func tenFinishedRowsAtMost() {
        var roster = SessionRoster()
        roster.update(sessionId: "question", pillId: "integration_claude", title: "Q", phase: .question,
                      lastAction: nil, at: at(minutes: 0))
        roster.update(sessionId: "working", pillId: "integration_claude", title: "W", phase: .working,
                      lastAction: nil, at: at(minutes: 0))
        for n in 1...12 {
            roster.update(sessionId: "f\(n)", pillId: "integration_claude", title: "F\(n)",
                          phase: n % 2 == 0 ? .finished : .error, lastAction: nil, at: at(minutes: Double(n)))
        }
        roster.prune(now: at(minutes: 13), calendar: utc)
        let ended = roster.rows.filter { $0.phase.isEnded }.map(\.id)
        precondition(ended == (3...12).reversed().map { "f\($0)" },
                     "12 ended rows (finished or failed) keep the 10 most recent, got \(ended)")
        precondition(SessionRoster.endedLimit == 10)
        precondition(Set(ids(roster)).isSuperset(of: ["question", "working"]),
                     "the cap counts ended rows only: the active ones all stay")
        precondition(roster.rows.count == 12)
    }

    static func activeRowsComeBeforeFinishedOnes() {
        var roster = SessionRoster()
        roster.update(sessionId: "idle", pillId: "integration_claude", title: "I", phase: .idle,
                      lastAction: nil, at: at(minutes: 0))
        roster.update(sessionId: "done1", pillId: "integration_claude", title: "D1", phase: .finished,
                      lastAction: nil, at: at(minutes: 1))
        roster.update(sessionId: "work", pillId: "integration_claude", title: "W", phase: .working,
                      lastAction: nil, at: at(minutes: 2))
        roster.update(sessionId: "fail", pillId: "agent_claude-desktop", title: "F", phase: .error,
                      lastAction: nil, at: at(minutes: 3))
        roster.update(sessionId: "ask", pillId: "integration_claude", title: "A", phase: .question,
                      lastAction: nil, at: at(minutes: 4))

        let expected = ["ask", "work", "idle", "fail", "done1"]
        precondition(SessionRoster.listed(roster.rows).map(\.id) == expected,
                     "running sessions first (latest activity), then ended ones (latest end), got \(SessionRoster.listed(roster.rows).map(\.id))")
        precondition(roster.visible(limit: 10).map(\.id) == expected, "visible lists them in that order")
        precondition(roster.visible(limit: 4).map(\.id) == ["ask", "work", "idle", "fail"],
                     "a limit keeps the running sessions first")
        // The roster itself stays in activity order: ⌃⌥T opens the session that acted last.
        precondition(ids(roster) == ["ask", "fail", "work", "done1", "idle"])

        for phase in SessionPhase.allCases {
            precondition(phase.isEnded == (phase == .finished || phase == .error),
                         "\(phase) is ended only when finished or failed")
        }
    }

    static func aSessionThatEndsKeepsItsFinishedRow() {
        // SessionEnd after Stop (the user quits Claude Code): the session finished today, its row stays.
        var roster = SessionRoster()
        roster.update(sessionId: "done", pillId: "integration_claude", title: "D", phase: .finished,
                      lastAction: "Fini", at: at(minutes: 0))
        roster.update(sessionId: "failed", pillId: "integration_claude", title: "F", phase: .error,
                      lastAction: nil, at: at(minutes: 1))
        roster.update(sessionId: "busy", pillId: "integration_claude", title: "B", phase: .working,
                      lastAction: nil, at: at(minutes: 2))
        roster.update(sessionId: "fresh", pillId: "integration_claude", title: "N", phase: .idle,
                      lastAction: nil, at: at(minutes: 3))
        for id in ["done", "failed", "busy", "fresh"] { roster.end(sessionId: id) }
        precondition(ids(roster) == ["failed", "done"],
                     "an ended session keeps a finished or failed row, any other row leaves, got \(ids(roster))")
        precondition(roster.rows.first { $0.id == "done" }?.updatedAt == at(minutes: 0)
                     && roster.rows.first { $0.id == "done" }?.lastAction == "Fini",
                     "its end time and last line are unchanged")
    }

    static func aFinishedRowSaysWhenItEnded() {
        precondition(SessionRoster.clock(at(minutes: 0), calendar: utc) == "08:00")
        precondition(SessionRoster.clock(at(minutes: 65), calendar: utc) == "09:05", "two digits for the minutes")
        precondition(SessionRoster.clock(at(minutes: 0), calendar: calendar("Europe/Paris")) == "09:00",
                     "the user's time zone")
        precondition(SessionRoster.clock(at(minutes: 6 * 60), calendar: utc) == "14:00", "24 hour clock")
        precondition(SessionRoster.clock(at(minutes: -8 * 60 + 5), calendar: utc) == "00:05", "two digits for the hours")
    }

    // MARK: - The name of a session (Task 25)
    // A hook's `session_title` (a custom title: --name, /rename, a rename in the Claude app or VS Code)
    // comes first, then the status line's `session_name` (the custom name, else the AI title), then
    // the project folder.

    static func row(_ roster: SessionRoster, _ id: String) -> SessionRow? { roster.rows.first { $0.id == id } }

    static func aSessionGoesByItsCustomTitleThenItsStatusLineNameThenItsFolder() {
        var roster = SessionRoster()
        roster.update(sessionId: "a", pillId: "integration_claude", title: "projet-a", phase: .working,
                      lastAction: "Edits · A.swift", at: at(minutes: 0))
        roster.update(sessionId: "b", pillId: "integration_claude", title: "projet-b", phase: .thinking,
                      lastAction: nil, at: at(minutes: 1))
        precondition(row(roster, "a")?.title == "projet-a" && row(roster, "a")?.folder == "projet-a",
                     "without a name, a session goes by its folder")

        // The status line names "a": its row takes the name, and stays where it was, with its date.
        precondition(roster.name(sessionId: "a", "Refonte de l'onboarding", from: .statusLine, at: at(minutes: 2)),
                     "a first name changes the title")
        precondition(row(roster, "a")?.title == "Refonte de l'onboarding", "got \(String(describing: row(roster, "a")?.title))")
        precondition(row(roster, "a")?.folder == "projet-a", "the folder is kept, for nothing else than the fallback")
        precondition(ids(roster) == ["b", "a"] && row(roster, "a")?.updatedAt == at(minutes: 0)
                     && row(roster, "a")?.phase == .working && row(roster, "a")?.lastAction == "Edits · A.swift",
                     "a name moves nothing: same place, date, phase and last action")
        precondition(row(roster, "b")?.title == "projet-b", "the other session keeps its folder")

        // A custom title from a hook comes before the status line's name.
        precondition(roster.name(sessionId: "a", "Onboarding v2", from: .customTitle, at: at(minutes: 3)))
        precondition(row(roster, "a")?.title == "Onboarding v2")
        precondition(!roster.name(sessionId: "a", "Un autre titre", from: .statusLine, at: at(minutes: 4)),
                     "a status line name under a custom title changes nothing shown")
        precondition(row(roster, "a")?.title == "Onboarding v2", "the custom title stays first")

        // The next events of the session still bring its folder: the name stays.
        roster.update(sessionId: "a", pillId: "integration_claude", title: "projet-a", phase: .finished,
                      lastAction: "Terminé", at: at(minutes: 5))
        precondition(row(roster, "a")?.title == "Onboarding v2" && row(roster, "a")?.folder == "projet-a",
                     "an update keeps the name, got \(String(describing: row(roster, "a")))")
        precondition(roster.title(of: "a", folder: "projet-a") == "Onboarding v2")
        precondition(roster.title(of: "b", folder: "projet-b") == "projet-b")
        precondition(roster.title(of: "never-seen", folder: "dossier") == "dossier")
    }

    static func aLaterCustomTitleReplacesAnAITitle() {
        var roster = SessionRoster()
        roster.update(sessionId: "s", pillId: "agent_claude-desktop", title: "site", phase: .thinking,
                      lastAction: nil, at: at(minutes: 0))
        // The AI title, then a rename in the Claude app: the next prompt carries the custom title.
        precondition(roster.name(sessionId: "s", "Corriger le formulaire de contact", from: .statusLine, at: at(minutes: 1)))
        precondition(roster.name(sessionId: "s", "Formulaire", from: .customTitle, at: at(minutes: 2)))
        precondition(row(roster, "s")?.title == "Formulaire")
        // Renamed again (/rename): the later custom title replaces the earlier one.
        precondition(roster.name(sessionId: "s", "Formulaire de contact", from: .customTitle, at: at(minutes: 3)))
        precondition(row(roster, "s")?.title == "Formulaire de contact")
        // A new AI title replaces the earlier AI title when there is no custom one.
        var other = SessionRoster()
        other.update(sessionId: "t", pillId: "integration_claude", title: "api", phase: .working,
                     lastAction: nil, at: at(minutes: 0))
        precondition(other.name(sessionId: "t", "Premier titre", from: .statusLine, at: at(minutes: 1)))
        precondition(other.name(sessionId: "t", "Titre affiné", from: .statusLine, at: at(minutes: 2)))
        precondition(row(other, "t")?.title == "Titre affiné")
        // The same name again: nothing changes, nothing to log.
        precondition(!other.name(sessionId: "t", "Titre affiné", from: .statusLine, at: at(minutes: 3)))
        precondition(!other.name(sessionId: "t", "  Titre affiné  ", from: .statusLine, at: at(minutes: 4)),
                     "the same name, trimmed")
    }

    static func anEmptyNameNeverReplacesAKnownOne() {
        var roster = SessionRoster()
        roster.update(sessionId: "s", pillId: "integration_claude", title: "dossier", phase: .working,
                      lastAction: nil, at: at(minutes: 0))
        precondition(roster.name(sessionId: "s", "Nom de l'IA", from: .statusLine, at: at(minutes: 1)))
        precondition(roster.name(sessionId: "s", "Nom choisi", from: .customTitle, at: at(minutes: 2)))
        let blanks: [Any?] = ["", "   ", "\n\t ", nil, 42, ["Nom"], NSNull()]
        for (i, blank) in blanks.enumerated() {
            for source in [SessionNameSource.customTitle, .statusLine] {
                precondition(!roster.name(sessionId: "s", blank, from: source, at: at(minutes: 3 + Double(i))),
                             "\(String(describing: blank)) from \(source) is no name")
                precondition(row(roster, "s")?.title == "Nom choisi", "\(String(describing: blank)) replaced the name")
            }
        }
        // The status line's name is still there under the custom title: a blank title did not clear it.
        var bare = SessionRoster()
        bare.update(sessionId: "s", pillId: "integration_claude", title: "dossier", phase: .working,
                    lastAction: nil, at: at(minutes: 0))
        precondition(!bare.name(sessionId: "s", " ", from: .statusLine, at: at(minutes: 1)))
        precondition(row(bare, "s")?.title == "dossier", "a blank name never replaces the folder either")
    }

    static func aNameIsOneLineOf120CharactersAtMost() {
        precondition(SessionName.clean("  Refonte\nde l'onboarding\t client ") == "Refonte de l'onboarding client",
                     "line breaks and tabs become one space, ends trimmed, got \(String(describing: SessionName.clean("  Refonte\nde l'onboarding\t client ")))")
        let long = String(repeating: "é", count: 130)
        precondition(SessionName.clean(long)?.count == 120, "cut to 120 characters")
        precondition(SessionName.clean(String(repeating: "a", count: 119) + " b") == String(repeating: "a", count: 119),
                     "no trailing space after the cut")
        precondition(SessionName.limit == 120)
        precondition(SessionName.clean("") == nil && SessionName.clean(" \n ") == nil && SessionName.clean(7) == nil
                     && SessionName.clean(nil) == nil)
        var roster = SessionRoster()
        roster.update(sessionId: "s", pillId: "integration_claude", title: "dossier", phase: .working,
                      lastAction: nil, at: at(minutes: 0))
        precondition(roster.name(sessionId: "s", long, from: .customTitle, at: at(minutes: 1)))
        precondition(row(roster, "s")?.title.count == 120, "the row holds the name cut at 120 characters")
    }

    static func aNameBeforeItsRowIsAppliedWhenTheRowAppears() {
        // The status line can run before the session's first hook reaches the island.
        var roster = SessionRoster()
        precondition(roster.name(sessionId: "s", "Nom de l'IA", from: .statusLine, at: at(minutes: 0)))
        precondition(roster.rows.isEmpty, "a name makes no row")
        precondition(roster.title(of: "s", folder: "dossier") == "Nom de l'IA",
                     "a note about that session already goes by its name")
        roster.update(sessionId: "s", pillId: "agent_claude-desktop", title: "dossier", phase: .idle,
                      lastAction: "Session démarrée", at: at(minutes: 1))
        precondition(row(roster, "s")?.title == "Nom de l'IA" && row(roster, "s")?.folder == "dossier",
                     "the row appears with the name, got \(String(describing: row(roster, "s")))")
        // A custom title that came with the first hook (SessionStart of a named session) too.
        var named = SessionRoster()
        precondition(named.name(sessionId: "n", "Ma session", from: .customTitle, at: at(minutes: 0)))
        named.update(sessionId: "n", pillId: "integration_claude", title: "dossier", phase: .idle,
                     lastAction: nil, at: at(minutes: 0))
        precondition(row(named, "n")?.title == "Ma session")
    }

    static func namesGoWithTheirRow() {
        var roster = SessionRoster()
        for (id, phase) in [("idle", SessionPhase.idle), ("working", .working), ("done", .finished), ("asks", .question)] {
            roster.update(sessionId: id, pillId: "integration_claude", title: "dossier-\(id)", phase: phase,
                          lastAction: nil, at: at(minutes: 0))
            precondition(roster.name(sessionId: id, "Nom \(id)", from: .statusLine, at: at(minutes: 0)))
        }
        // The idle row is pruned after 30 min: its name goes with it.
        roster.prune(now: at(minutes: 31), calendar: utc)
        precondition(row(roster, "idle") == nil && roster.names["idle"] == nil, "a pruned row's name is dropped")
        precondition(roster.names["working"] != nil && roster.names["done"] != nil && roster.names["asks"] != nil)
        // SessionEnd: the working row leaves with its name; the finished row stays, with its name.
        roster.end(sessionId: "working")
        roster.end(sessionId: "done")
        precondition(roster.names["working"] == nil, "an ended session's name is dropped with its row")
        precondition(row(roster, "done")?.title == "Nom done" && roster.names["done"] != nil,
                     "a finished row that stays keeps its name")
        // Midnight clears the finished row and its name; the question waits on with its name.
        roster.prune(now: at(minutes: 24 * 60), calendar: utc)
        precondition(roster.names["done"] == nil, "the day's history leaves with its names")
        precondition(row(roster, "asks")?.title == "Nom asks", "a row still there keeps its name")
        // A session that comes back after its row left starts from its folder.
        roster.update(sessionId: "working", pillId: "integration_claude", title: "dossier-working", phase: .thinking,
                      lastAction: nil, at: at(minutes: 24 * 60 + 1))
        precondition(row(roster, "working")?.title == "dossier-working", "its old name was dropped")
        // Over the 10 finished rows: the oldest end goes with its name.
        var history = SessionRoster()
        for i in 0..<11 {
            history.update(sessionId: "f\(i)", pillId: "integration_claude", title: "d", phase: .finished,
                           lastAction: nil, at: at(minutes: Double(i)))
            precondition(history.name(sessionId: "f\(i)", "Fin \(i)", from: .customTitle, at: at(minutes: Double(i))))
        }
        history.prune(now: at(minutes: 12), calendar: utc)
        precondition(history.names["f0"] == nil && history.names.count == 10, "got \(history.names.keys.sorted())")
    }

    static func aNameWithoutARowIsKept30Min() {
        // A status line of a session the island never shows (an editor it does not follow, a session
        // not started yet) is not kept forever: 30 min after its last name, it goes.
        var roster = SessionRoster()
        precondition(roster.name(sessionId: "ghost", "Nom", from: .statusLine, at: at(minutes: 0)))
        roster.prune(now: at(minutes: 29), calendar: utc)
        precondition(roster.names["ghost"] != nil, "kept before 30 min")
        // The status line keeps running: the name is noted again, the 30 min start over.
        precondition(!roster.name(sessionId: "ghost", "Nom", from: .statusLine, at: at(minutes: 20)))
        roster.prune(now: at(minutes: 45), calendar: utc)
        precondition(roster.names["ghost"] != nil, "a name noted again at 20 min is kept at 45 min")
        roster.prune(now: at(minutes: 50), calendar: utc)
        precondition(roster.names["ghost"] == nil, "30 min after its last note, it goes")
        // An end of a session never seen drops nothing waiting.
        precondition(roster.name(sessionId: "early", "Nom", from: .statusLine, at: at(minutes: 60)))
        roster.end(sessionId: "early")
        precondition(roster.names["early"] != nil, "SessionEnd of a session without a row keeps nothing to drop")
        // Noting a name also drops the stale ones: no prune needed for the dictionary to stay small.
        precondition(roster.name(sessionId: "other", "Autre", from: .statusLine, at: at(minutes: 95)))
        precondition(roster.names["early"] == nil && roster.names["other"] != nil, "got \(roster.names.keys.sorted())")
    }

    static func aRequestGoesByItsSessionsName() {
        // The approval card's « who » and the history entry go through `title(of:in:fallback:)`.
        var roster = SessionRoster()
        roster.update(sessionId: "A", pillId: "agent_claude-desktop", title: "projet-a", phase: .approval,
                      lastAction: "npm test", at: at(minutes: 0))
        precondition(roster.name(sessionId: "A", "Tests du paiement", from: .customTitle, at: at(minutes: 1)))
        precondition(SessionRoster.title(of: "A", in: roster.rows, fallback: "Claude Desktop") == "Tests du paiement")
    }
}

/// IslandTypes.swift (compiled here for `IslandView`) names `EyeShape`, which BotEngine.swift
/// defines with SwiftUI. This stand-in lets it build with Foundation only.
enum EyeShape: Equatable {}
