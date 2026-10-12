import Foundation

/// A Notification hook of a session of the Claude app that says Claude waits for the user (lot 6
/// spec §5, Task 20). The fields are those of the Claude Code hooks reference, Notification input:
/// `message`, an optional `title`, and `notification_type` (`permission_prompt`, `idle_prompt`,
/// `elicitation_dialog`, `elicitation_url_dialog`, and the types that ask nothing: `auth_success`,
/// `elicitation_complete`, `elicitation_response`, `agent_needs_input`, `agent_completed`,
/// `quota_auto_resume_*`). Older Claude Code sends the message only. The terminal never opens the
/// island from here (Baptiste: « Je veux pas que ça soit fait pour le terminal »). An `idle_prompt`
/// comes about 60 s after the end of a turn: when the finish was already shown (the session's row is
/// finished or failed, and its finished or error view opened), it does not open the island a second
/// time; when that finish was only badged (the island was busy), the idle prompt is its second chance.
/// A Claude app alert that the busy island cannot show is held, the latest one only, and shown in
/// place of the home once the island frees (`ClaudeAppAlertHold`, final fix wave of lot 6).
@main
enum CodeNotificationTests {
    static func main() {
        let cases: [(String, () -> Void)] = [
            ("a_permission_prompt_is_a_permission", aPermissionPromptIsAPermission),
            ("an_idle_prompt_is_idle_and_the_elicitations_are_a_wait", anIdlePromptIsIdleAndTheElicitationsAreAWait),
            ("the_other_documented_types_ask_nothing", theOtherDocumentedTypesAskNothing),
            ("the_type_wins_over_the_message", theTypeWinsOverTheMessage),
            ("an_unknown_type_asks_nothing", anUnknownTypeAsksNothing),
            ("older_claude_code_is_read_from_the_message", olderClaudeCodeIsReadFromTheMessage),
            ("an_empty_type_is_no_type", anEmptyTypeIsNoType),
            ("a_message_that_asks_nothing_alerts_nothing", aMessageThatAsksNothingAlertsNothing),
            ("only_the_claude_app_opens", onlyTheClaudeAppOpens),
            ("a_card_of_the_session_prevents_a_second_alert", aCardOfTheSessionPreventsASecondAlert),
            ("an_idle_prompt_after_a_shown_finish_does_not_open", anIdlePromptAfterAShownFinishDoesNotOpen),
            ("an_idle_prompt_after_a_finish_not_shown_opens", anIdlePromptAfterAFinishNotShownOpens),
            ("an_idle_prompt_opens_without_a_finished_row", anIdlePromptOpensWithoutAFinishedRow),
            ("a_permission_or_an_elicitation_opens_on_any_row", aPermissionOrAnElicitationOpensOnAnyRow),
            ("a_held_card_is_the_sessions_own", aHeldCardIsTheSessionsOwn),
            ("the_terminal_never_opens", theTerminalNeverOpens),
            ("near_misses_of_the_desktop_tag_never_open", nearMissesOfTheDesktopTagNeverOpen),
            ("a_permission_puts_the_row_on_approval", aPermissionPutsTheRowOnApproval),
            ("a_wait_puts_the_row_on_question", aWaitPutsTheRowOnQuestion),
            ("a_wait_leaves_an_ended_row_as_it_is", aWaitLeavesAnEndedRowAsItIs),
            ("an_idle_row_goes_on_question_unless_ended", anIdleRowGoesOnQuestionUnlessEnded),
            // Which finishes the island showed (final fix wave, I1 part 2)
            ("a_shown_finish_is_recorded_per_session", aShownFinishIsRecordedPerSession),
            ("the_latest_finish_of_a_session_decides", theLatestFinishOfASessionDecides),
            ("a_session_that_left_is_forgotten", aSessionThatLeftIsForgotten),
            // A Claude app alert held while the island is busy (final fix wave, I1 part 1)
            ("an_alert_the_busy_island_blocks_is_held", anAlertTheBusyIslandBlocksIsHeld),
            ("only_the_latest_blocked_alert_is_held", onlyTheLatestBlockedAlertIsHeld),
            ("a_newer_alert_shown_drops_the_held_one", aNewerAlertShownDropsTheHeldOne),
            ("the_held_alert_shows_in_place_of_the_home_once", theHeldAlertShowsInPlaceOfTheHomeOnce),
            ("a_held_alert_waits_while_the_home_may_not_show", aHeldAlertWaitsWhileTheHomeMayNotShow),
            ("the_claude_app_in_front_drops_the_held_alert", theClaudeAppInFrontDropsTheHeldAlert),
            ("a_held_alert_lasts_30_min", aHeldAlertLasts30Min),
            ("nothing_held_the_home_shows", nothingHeldTheHomeShows),
            // The badge of the house tab (final fix wave, I1 part 3)
            ("the_house_tab_is_badged_while_an_alert_is_held", theHouseTabIsBadgedWhileAnAlertIsHeld),
            ("an_unseen_claude_app_badge_stays_until_the_list_shows", anUnseenClaudeAppBadgeStaysUntilTheListShows),
            ("the_house_tab_shows_the_strongest_badge", theHouseTabShowsTheStrongestBadge),
            ("a_request_waiting_off_screen_badges_the_house_tab", aRequestWaitingOffScreenBadgesTheHouseTab),
            ("the_claude_app_in_front_clears_the_house_tab", theClaudeAppInFrontClearsTheHouseTab),
            // Residuals of the final re-review (I-1, M-1)
            ("a_held_alert_of_a_session_that_moved_on_is_dropped", aHeldAlertOfASessionThatMovedOnIsDropped),
            ("another_session_moving_on_keeps_the_held_alert", anotherSessionMovingOnKeepsTheHeldAlert),
            ("a_watch_alert_has_no_session_to_move_on", aWatchAlertHasNoSessionToMoveOn),
            ("a_held_alert_past_30_min_is_dropped_at_its_expiry", aHeldAlertPast30MinIsDroppedAtItsExpiry),
            // 0.3.6: one held item per session, finishes too, shown one after the other
            ("one_item_per_session_five_at_most_newest_first", oneItemPerSessionFiveAtMostNewestFirst),
            ("a_shown_alert_keeps_the_other_sessions_items", aShownAlertKeepsTheOtherSessionsItems),
            ("held_items_show_one_after_the_other_newest_first", heldItemsShowOneAfterTheOtherNewestFirst),
            ("a_finish_the_busy_island_could_not_show_is_held", aFinishTheBusyIslandCouldNotShowIsHeld),
            ("the_claude_app_in_front_drops_only_its_own_items", theClaudeAppInFrontDropsOnlyItsOwnItems),
            ("the_house_tab_counts_the_held_items", theHouseTabCountsTheHeldItems),
            ("a_request_showing_or_leaving_keeps_the_other_marks", aRequestShowingOrLeavingKeepsTheOtherMarks),
            ("an_asking_note_replaced_goes_back_to_the_hold", anAskingNoteReplacedGoesBackToTheHold),
            ("a_finish_replaced_before_it_was_seen_goes_back", aFinishReplacedBeforeItWasSeenGoesBack),
            ("a_fold_from_a_held_or_busy_view_shows_the_next", aFoldFromAHeldOrBusyViewShowsTheNext),
            ("the_next_expiry_is_the_oldest_items", theNextExpiryIsTheOldestItems),
            ("a_held_finish_makes_its_idle_prompt_redundant", aHeldFinishMakesItsIdlePromptRedundant),
            ("a_session_that_closes_keeps_its_held_finish", aSessionThatClosesKeepsItsHeldFinish),
            ("two_alerts_with_the_same_text_for_two_sessions_are_two", twoAlertsWithTheSameTextForTwoSessionsAreTwo),
            // 0.3.6: a request that leaves without an answer still waits in its app (C3, I1)
            ("a_request_handed_back_keeps_its_row_waiting", aRequestHandedBackKeepsItsRowWaiting),
            ("only_a_timeout_or_a_newer_request_holds_a_claude_app_alert", onlyATimeoutOrANewerRequestHoldsAClaudeAppAlert),
        ]
        for (name, run) in cases {
            run()
            print("  ok  \(name)")
        }
        print("Code notification: \(cases.count) cases passed")
    }

    static let desktop = "claude-desktop"

    // MARK: - What a notification says (notification_type, then the message)

    static func aPermissionPromptIsAPermission() {
        precondition(CodeNotification.alert(message: "Claude needs your permission to use Bash",
                                            notificationType: "permission_prompt") == .permission)
        // The message is not needed when the type is there.
        precondition(CodeNotification.alert(message: "", notificationType: "permission_prompt") == .permission)
    }

    static func anIdlePromptIsIdleAndTheElicitationsAreAWait() {
        precondition(CodeNotification.alert(message: "Claude is waiting for your input",
                                            notificationType: "idle_prompt") == .idle,
                     "idle_prompt is Claude idle after its turn, told apart from an MCP form")
        for type in ["elicitation_dialog", "elicitation_url_dialog"] {
            precondition(CodeNotification.alert(message: "Claude is waiting for your input",
                                                notificationType: type) == .waiting,
                         "\(type) is an MCP server waiting for the user")
        }
    }

    static func theOtherDocumentedTypesAskNothing() {
        let quiet = ["auth_success", "elicitation_complete", "elicitation_response", "agent_needs_input",
                     "agent_completed", "quota_auto_resume_fired", "quota_auto_resume_stale",
                     "quota_auto_resume_disabled"]
        for type in quiet {
            precondition(CodeNotification.alert(message: "Authentication successful", notificationType: type) == nil,
                         "\(type) asks the user nothing: no alert")
        }
    }

    static func theTypeWinsOverTheMessage() {
        // A type that asks nothing stays quiet even if the text sounds like a request...
        precondition(CodeNotification.alert(message: "Claude needs your permission",
                                            notificationType: "auth_success") == nil)
        precondition(CodeNotification.alert(message: "Claude is waiting for your input",
                                            notificationType: "elicitation_complete") == nil)
        // ...and a request type is read as it says, whatever the text.
        precondition(CodeNotification.alert(message: "Claude needs your permission",
                                            notificationType: "idle_prompt") == .idle)
        precondition(CodeNotification.alert(message: "Claude is waiting for your input",
                                            notificationType: "permission_prompt") == .permission)
    }

    static func anUnknownTypeAsksNothing() {
        // A type the hooks reference does not list: the island does not guess from the text.
        precondition(CodeNotification.alert(message: "Claude needs your permission",
                                            notificationType: "something_new") == nil)
    }

    static func olderClaudeCodeIsReadFromTheMessage() {
        precondition(CodeNotification.alert(message: "Claude needs your permission to use Bash",
                                            notificationType: nil) == .permission)
        precondition(CodeNotification.alert(message: "Claude needs your permission",
                                            notificationType: nil) == .permission)
        precondition(CodeNotification.alert(message: "Claude is waiting for your input",
                                            notificationType: nil) == .idle,
                     "older Claude Code sent this text for the idle prompt")
        // Case does not matter.
        precondition(CodeNotification.alert(message: "CLAUDE NEEDS YOUR PERMISSION TO USE EDIT",
                                            notificationType: nil) == .permission)
        precondition(CodeNotification.alert(message: "claude is waiting for your input",
                                            notificationType: nil) == .idle)
    }

    static func anEmptyTypeIsNoType() {
        for blank in ["", "  "] {
            precondition(CodeNotification.alert(message: "Claude needs your permission to use Bash",
                                                notificationType: blank) == .permission)
            precondition(CodeNotification.alert(message: "Claude is waiting for your input",
                                                notificationType: blank) == .idle)
        }
    }

    static func aMessageThatAsksNothingAlertsNothing() {
        for message in ["", "Claude finished", "Rate limit reached", "Authentication successful",
                        "Which file do you want me to edit?"] {
            precondition(CodeNotification.alert(message: message, notificationType: nil) == nil,
                         "\"\(message)\" asks nothing of the user")
        }
    }

    // MARK: - Who opens the island

    static let allKinds: [CodeNotification.Kind] = [.permission, .waiting, .idle]
    /// Every phase a row may have, and no row at all.
    static let phasesAndNone: [SessionPhase?] = [nil] + SessionPhase.allCases.map { Optional($0) }

    static func onlyTheClaudeAppOpens() {
        for kind in allKinds {
            for shown in [false, true] {
                precondition(CodeNotification.shouldOpen(kind: kind, sessionHasCard: false, agent: desktop,
                                                         currentPhase: nil, finishShown: shown),
                             "a session of the Claude app with no card of its own opens the island")
            }
        }
    }

    // Spec review focus 4: the card of that session is already on screen (or waits for the pointer):
    // no second view over it.
    static func aCardOfTheSessionPreventsASecondAlert() {
        for kind in allKinds {
            for phase in phasesAndNone {
                for shown in [false, true] {
                    precondition(!CodeNotification.shouldOpen(kind: kind, sessionHasCard: true, agent: desktop,
                                                              currentPhase: phase, finishShown: shown),
                                 "no duplicate when the session's card is held")
                }
            }
        }
    }

    // The finished view was the notification: the idle prompt that follows it about 60 s later does
    // not open the island a second time, whether the session finished or failed.
    static func anIdlePromptAfterAShownFinishDoesNotOpen() {
        for ended in [SessionPhase.finished, .error] {
            precondition(!CodeNotification.shouldOpen(kind: .idle, sessionHasCard: false, agent: desktop,
                                                      currentPhase: ended, finishShown: true),
                         "an idle prompt after a shown \(ended) row shows nothing new")
        }
    }

    // I1 part 2: the finish was only badged (a card waited, the chat or a mail draft was open, the
    // island was pinned), so nothing was shown: the idle prompt about 60 s later is its second chance.
    static func anIdlePromptAfterAFinishNotShownOpens() {
        for ended in [SessionPhase.finished, .error] {
            precondition(CodeNotification.shouldOpen(kind: .idle, sessionHasCard: false, agent: desktop,
                                                     currentPhase: ended, finishShown: false),
                         "an idle prompt after a \(ended) row that was never shown opens the note")
            // Still never over its own card, and never for the terminal.
            precondition(!CodeNotification.shouldOpen(kind: .idle, sessionHasCard: true, agent: desktop,
                                                      currentPhase: ended, finishShown: false))
            precondition(!CodeNotification.shouldOpen(kind: .idle, sessionHasCard: false, agent: "",
                                                      currentPhase: ended, finishShown: false))
        }
    }

    // Nothing was shown for a session that is still running, idle, or that the island never saw.
    static func anIdlePromptOpensWithoutAFinishedRow() {
        for shown in [false, true] {
            precondition(CodeNotification.shouldOpen(kind: .idle, sessionHasCard: false, agent: desktop,
                                                     currentPhase: nil, finishShown: shown),
                         "no row: nothing was shown, the idle prompt opens")
            for running in SessionPhase.allCases where !running.isEnded {
                precondition(CodeNotification.shouldOpen(kind: .idle, sessionHasCard: false, agent: desktop,
                                                         currentPhase: running, finishShown: shown),
                             "an idle prompt with a \(running) row opens")
            }
        }
    }

    // Only the idle prompt is a repeat of the finish: a permission, or an MCP server's form, is a new
    // request whatever the row says.
    static func aPermissionOrAnElicitationOpensOnAnyRow() {
        for kind in [CodeNotification.Kind.permission, .waiting] {
            for phase in phasesAndNone {
                for shown in [false, true] {
                    precondition(CodeNotification.shouldOpen(kind: kind, sessionHasCard: false, agent: desktop,
                                                             currentPhase: phase, finishShown: shown),
                                 "\(kind) opens with a \(String(describing: phase)) row")
                }
            }
        }
    }

    // Which card counts as the session's own: its permission, or its question while one is pending.
    static func aHeldCardIsTheSessionsOwn() {
        precondition(!CodeNotification.holdsCard(sessionId: "A", approvalSession: nil,
                                                 questionPending: false, questionSession: nil),
                     "no card pending")
        precondition(CodeNotification.holdsCard(sessionId: "A", approvalSession: "A",
                                                questionPending: false, questionSession: nil),
                     "its permission card")
        precondition(!CodeNotification.holdsCard(sessionId: "A", approvalSession: "B",
                                                 questionPending: false, questionSession: nil),
                     "the permission card of another session")
        precondition(CodeNotification.holdsCard(sessionId: "A", approvalSession: nil,
                                                questionPending: true, questionSession: "A"),
                     "its question card")
        precondition(!CodeNotification.holdsCard(sessionId: "A", approvalSession: nil,
                                                 questionPending: true, questionSession: "B"),
                     "the question card of another session")
        precondition(!CodeNotification.holdsCard(sessionId: "A", approvalSession: nil,
                                                 questionPending: false, questionSession: "A"),
                     "a question session left behind is no card: nothing is pending")
        precondition(CodeNotification.holdsCard(sessionId: "A", approvalSession: "B",
                                                questionPending: true, questionSession: "A"),
                     "its question, under another session's permission")
        precondition(CodeNotification.holdsCard(sessionId: "A", approvalSession: "A",
                                                questionPending: true, questionSession: "B"),
                     "its permission, under another session's question")
    }

    static func theTerminalNeverOpens() {
        for kind in allKinds {
            for hasCard in [false, true] {
                for phase in phasesAndNone {
                    for shown in [false, true] {
                        // Claude Code in a terminal or an editor sends no klayer_agent.
                        precondition(!CodeNotification.shouldOpen(kind: kind, sessionHasCard: hasCard, agent: "",
                                                                  currentPhase: phase, finishShown: shown),
                                     "a terminal session never opens the island from a notification")
                        // Any other agent is not followed at all.
                        precondition(!CodeNotification.shouldOpen(kind: kind, sessionHasCard: hasCard,
                                                                  agent: "codex", currentPhase: phase,
                                                                  finishShown: shown))
                    }
                }
            }
        }
    }

    static func nearMissesOfTheDesktopTagNeverOpen() {
        for near in ["Claude-Desktop", "claude", "claude-desktop2", " claude-desktop", "claude-desktop "] {
            precondition(!CodeNotification.shouldOpen(kind: .permission, sessionHasCard: false, agent: near,
                                                      currentPhase: nil, finishShown: false),
                         "\(near) is not the Claude app")
        }
    }

    // MARK: - The row of the session in the home's list

    static func aPermissionPutsTheRowOnApproval() {
        precondition(CodeNotification.rowPhase(for: .permission, current: nil) == .approval)
        for current in SessionPhase.allCases {
            precondition(CodeNotification.rowPhase(for: .permission, current: current) == .approval,
                         "a permission asked in the app puts a \(current) row on « Attend ton accord »")
        }
    }

    static func aWaitPutsTheRowOnQuestion() {
        precondition(CodeNotification.rowPhase(for: .waiting, current: nil) == .question)
        for current in SessionPhase.allCases where !current.isEnded {
            precondition(CodeNotification.rowPhase(for: .waiting, current: current) == .question,
                         "Claude waiting puts a \(current) row on « Te pose une question »")
        }
    }

    // An idle prompt comes about 60 s after the end of a turn: the row of that finished session
    // stays in the day's history, in grey with its end time, not back among the running ones.
    static func aWaitLeavesAnEndedRowAsItIs() {
        for ended in [SessionPhase.finished, .error] {
            precondition(CodeNotification.rowPhase(for: .waiting, current: ended) == nil,
                         "an ended row keeps its end time: nothing to change")
        }
    }

    // The idle prompt follows a row rule of its own kind: a running or unseen session goes on
    // question, an ended one stays in the day's history (`shouldOpen` decides the note apart: it
    // opens only when that finish was not shown).
    static func anIdleRowGoesOnQuestionUnlessEnded() {
        precondition(CodeNotification.rowPhase(for: .idle, current: nil) == .question)
        for current in SessionPhase.allCases {
            let expected: SessionPhase? = current.isEnded ? nil : .question
            precondition(CodeNotification.rowPhase(for: .idle, current: current) == expected,
                         "idle prompt over a \(current) row")
        }
    }

    // MARK: - Which finishes the island showed (I1 part 2)

    static func aShownFinishIsRecordedPerSession() {
        var finishes = ShownFinishes()
        precondition(!finishes.wasShown("A"), "a session the island never saw finish: not shown")
        finishes.ended("A", shown: true)
        precondition(finishes.wasShown("A"), "its finished view opened")
        precondition(!finishes.wasShown("B"), "another session is not concerned")
        finishes.ended("B", shown: false)
        precondition(!finishes.wasShown("B"), "a finish only badged was not shown")
        precondition(finishes.wasShown("A"))
    }

    // A session that finished in view, then started a new turn and finished again while the island
    // was busy: its last finish was not shown, the idle prompt after it opens the note.
    static func theLatestFinishOfASessionDecides() {
        var finishes = ShownFinishes()
        finishes.ended("A", shown: true)
        finishes.ended("A", shown: false)
        precondition(!finishes.wasShown("A"), "the latest finish was only badged")
        precondition(CodeNotification.shouldOpen(kind: .idle, sessionHasCard: false, agent: desktop,
                                                 currentPhase: .finished, finishShown: finishes.wasShown("A")))
        finishes.ended("A", shown: true)
        precondition(finishes.wasShown("A"), "the latest finish was shown again")
        precondition(!CodeNotification.shouldOpen(kind: .idle, sessionHasCard: false, agent: desktop,
                                                  currentPhase: .finished, finishShown: finishes.wasShown("A")))
    }

    // SessionEnd, or a row the roster no longer has (pruned at midnight): the record goes, so the set
    // never grows over days.
    static func aSessionThatLeftIsForgotten() {
        var finishes = ShownFinishes()
        finishes.ended("A", shown: true)
        finishes.ended("B", shown: true)
        finishes.ended("C", shown: true)
        finishes.forget("A")
        precondition(!finishes.wasShown("A"))
        finishes.keep(only: ["C", "D"])
        precondition(!finishes.wasShown("B"), "B has no row any more")
        precondition(finishes.wasShown("C"))
        precondition(finishes.sessions == ["C"])
    }

    // MARK: - A Claude app alert held while the island is busy (I1 part 1)

    static let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)
    static func at(_ seconds: TimeInterval) -> Date { t0.addingTimeInterval(seconds) }

    static func alert(_ title: String, at seconds: TimeInterval = 0, sound: String = "approval") -> HeldClaudeAppAlert {
        HeldClaudeAppAlert(title: title, message: "Dans l'app Claude", sound: sound, heldAt: at(seconds))
    }

    /// What `FinishPresentation` says for each way the island can be busy, and for the home.
    static let busy: [(String, FinishPresentation)] = {
        func shown(_ view: IslandView, expanded: Bool = true, pinned: Bool = false,
                   request: Bool = false) -> FinishPresentation {
            FinishPresentation.decide(expanded: expanded, view: view.rawValue, pinned: pinned, requestPending: request)
        }
        return [
            ("a permission card waits", shown(.approval, pinned: true, request: true)),
            ("a question card waits", shown(.question, pinned: true, request: true)),
            ("a card waits, the island folded", shown(.overview, expanded: false, pinned: true, request: true)),
            ("the chat", shown(.prompt)),
            ("a mail draft", shown(.mail)),
            ("the drop zone", shown(.upload)),
            ("a file being sent", shown(.uploading)),
            ("a dropped file", shown(.choose)),
            ("Settings in the island", shown(.settings)),
            ("pinned on the home", shown(.overview, pinned: true)),
        ]
    }()
    static let home = FinishPresentation.decide(expanded: true, view: IslandView.overview.rawValue, pinned: false,
                                                requestPending: false)
    /// The island opening on its default view (hover, the toggle hot key): folded, nothing waits.
    static let opening = FinishPresentation.decide(expanded: false, view: IslandView.overview.rawValue, pinned: false,
                                                   requestPending: false)

    static func anAlertTheBusyIslandBlocksIsHeld() {
        for (why, presentation) in busy {
            precondition(presentation == .badgeOnly, "\(why): the island is busy")
            var hold = ClaudeAppAlertHold()
            hold.alertCame(alert("Claude attend ta réponse"), presentation: presentation)
            precondition(hold.held == alert("Claude attend ta réponse"), "\(why): the alert is held, with its sound")
        }
        // Shown at once: nothing to hold.
        var hold = ClaudeAppAlertHold()
        hold.alertCame(alert("Claude a fini de répondre"), presentation: home)
        precondition(hold.held == nil)
    }

    static func onlyTheLatestBlockedAlertIsHeld() {
        var hold = ClaudeAppAlertHold()
        hold.alertCame(alert("Claude a fini de répondre", sound: "finish"), presentation: .badgeOnly)
        hold.alertCame(alert("Claude attend ta réponse", at: 5), presentation: .badgeOnly)
        precondition(hold.held == alert("Claude attend ta réponse", at: 5), "the newer replaces the older")
    }

    static func aNewerAlertShownDropsTheHeldOne() {
        var hold = ClaudeAppAlertHold()
        hold.alertCame(alert("Claude a fini de répondre", sound: "finish"), presentation: .badgeOnly)
        hold.alertCame(alert("Claude attend ta réponse", at: 5), presentation: .open)
        precondition(hold.held == nil, "the note on screen is the newest: the older one is not shown after it")
        precondition(hold.takeForHome(presentation: home, now: at(10)) == nil)
    }

    // A request left with nothing else waiting (HookServer.requestLeft), or the island opens on its
    // default view: the held alert takes the place of the home, once.
    static func theHeldAlertShowsInPlaceOfTheHomeOnce() {
        for presentation in [home, opening] {
            var hold = ClaudeAppAlertHold()
            hold.alertCame(alert("Claude attend ta réponse"), presentation: .badgeOnly)
            precondition(hold.takeForHome(presentation: presentation, now: at(90)) == alert("Claude attend ta réponse"))
            precondition(hold.held == nil, "shown: no longer held")
            precondition(hold.takeForHome(presentation: presentation, now: at(95)) == nil, "the next home is the home")
        }
    }

    // The same rule as when the alert came: a home the island may not show over (pinned) keeps it held.
    static func aHeldAlertWaitsWhileTheHomeMayNotShow() {
        var hold = ClaudeAppAlertHold()
        hold.alertCame(alert("Claude attend ta réponse"), presentation: .badgeOnly)
        for (why, presentation) in busy {
            precondition(hold.takeForHome(presentation: presentation, now: at(60)) == nil, "\(why): not shown")
            precondition(hold.held == alert("Claude attend ta réponse"), "\(why): still held")
        }
        precondition(hold.takeForHome(presentation: home, now: at(120)) == alert("Claude attend ta réponse"))
    }

    static func theClaudeAppInFrontDropsTheHeldAlert() {
        var hold = ClaudeAppAlertHold()
        hold.alertCame(alert("Claude attend ta réponse"), presentation: .badgeOnly)
        hold.claudeAppCameToFront()
        precondition(hold.held == nil, "the user went to the Claude app: he saw it there")
        precondition(hold.takeForHome(presentation: home, now: at(30)) == nil)
        // An alert blocked after that is held again.
        hold.alertCame(alert("Claude a fini de répondre", at: 40, sound: "finish"), presentation: .badgeOnly)
        precondition(hold.takeForHome(presentation: home, now: at(50)) == alert("Claude a fini de répondre", at: 40,
                                                                              sound: "finish"))
    }

    static func aHeldAlertLasts30Min() {
        precondition(ClaudeAppAlertHold.lifetime == 1_800)
        var hold = ClaudeAppAlertHold()
        hold.alertCame(alert("Claude attend ta réponse"), presentation: .badgeOnly)
        precondition(hold.takeForHome(presentation: home, now: at(1_800)) == alert("Claude attend ta réponse"),
                     "30 min to the second: still shown")
        hold.alertCame(alert("Claude attend ta réponse"), presentation: .badgeOnly)
        precondition(hold.takeForHome(presentation: home, now: at(1_801)) == nil, "past 30 min: the home")
        precondition(hold.held == nil, "and it is dropped")
        // Too old is dropped even while the home may not show.
        hold.alertCame(alert("Claude attend ta réponse"), presentation: .badgeOnly)
        precondition(hold.takeForHome(presentation: .badgeOnly, now: at(1_801)) == nil)
        precondition(hold.held == nil, "past 30 min it is dropped, not kept for later")
    }

    static func nothingHeldTheHomeShows() {
        var hold = ClaudeAppAlertHold()
        precondition(hold.held == nil)
        precondition(hold.takeForHome(presentation: home, now: at(0)) == nil)
        hold.claudeAppCameToFront()
        precondition(hold.held == nil)
    }

    // MARK: - The badge of the house tab (I1 part 3)

    // While an alert is held, the house tab of the header carries the badge the rail's icons carry:
    // the approval mark for a request, the finished mark for a finished answer. It goes with the
    // held alert: shown, replaced by a newer one shown, dropped, or past 30 min.
    static func theHouseTabIsBadgedWhileAnAlertIsHeld() {
        var hold = ClaudeAppAlertHold()
        precondition(hold.houseBadge(now: at(0)) == nil, "nothing held, nothing unseen: no badge")
        hold.alertCame(alert("Claude attend ta réponse", sound: "approval"), presentation: .badgeOnly)
        precondition(hold.houseBadge(now: at(10)) == .approval)
        hold.alertCame(alert("Claude attend ta réponse", sound: "question"), presentation: .badgeOnly)
        precondition(hold.houseBadge(now: at(10)) == .approval, "Claude waiting: the approval mark too")
        hold.alertCame(alert("Claude a fini de répondre", sound: "finish"), presentation: .badgeOnly)
        precondition(hold.houseBadge(now: at(10)) == .finished, "a finished answer: the finished mark")
        // Shown in place of the home: the badge goes.
        _ = hold.takeForHome(presentation: home, now: at(20))
        precondition(hold.houseBadge(now: at(20)) == nil)
        // Replaced by a newer alert shown at once: the badge goes.
        hold.alertCame(alert("Claude attend ta réponse"), presentation: .badgeOnly)
        hold.alertCame(alert("Claude a fini de répondre", sound: "finish"), presentation: .open)
        precondition(hold.houseBadge(now: at(30)) == nil)
        // Past 30 min the held alert says nothing current: no badge, even before the home drops it.
        hold.alertCame(alert("Claude attend ta réponse"), presentation: .badgeOnly)
        precondition(hold.houseBadge(now: at(1_800)) == .approval)
        precondition(hold.houseBadge(now: at(1_801)) == nil)
        // The home's list shown while it may not be shown over (pinned): the held alert stays, its
        // badge too.
        var pinned = ClaudeAppAlertHold()
        pinned.alertCame(alert("Claude attend ta réponse"), presentation: .badgeOnly)
        pinned.homeListShown()
        precondition(pinned.houseBadge(now: at(5)) == .approval, "still held: still badged")
    }

    // The Claude app pill badged and not seen (a finish, an error, a request behind a card, while the
    // island was busy): the badge stays on the house tab until the home's list is on screen.
    static func anUnseenClaudeAppBadgeStaysUntilTheListShows() {
        for badge in [PillBadge.finished, .error] {
            var hold = ClaudeAppAlertHold()
            hold.pillBadged(badge)
            precondition(hold.houseBadge(now: at(0)) == badge)
            precondition(hold.houseBadge(now: at(86_400)) == badge, "no time limit: the rows say it")
            hold.homeListShown()
            precondition(hold.houseBadge(now: at(0)) == nil, "the list shows the session's row")
        }
        // A held alert shown or dropped leaves an unseen finish of another session on the tab.
        var hold = ClaudeAppAlertHold()
        hold.pillBadged(.finished)
        hold.alertCame(alert("Claude attend ta réponse"), presentation: .badgeOnly)
        _ = hold.takeForHome(presentation: home, now: at(5))
        precondition(hold.houseBadge(now: at(5)) == .finished)
    }

    // One badge on the tab: a request first, then an error, then a finish.
    static func theHouseTabShowsTheStrongestBadge() {
        precondition(ClaudeAppAlertHold.strongest(nil, nil) == nil)
        precondition(ClaudeAppAlertHold.strongest(.finished, nil) == .finished)
        precondition(ClaudeAppAlertHold.strongest(nil, .error) == .error)
        precondition(ClaudeAppAlertHold.strongest(.finished, .error) == .error)
        precondition(ClaudeAppAlertHold.strongest(.error, .approval) == .approval)
        precondition(ClaudeAppAlertHold.strongest(.approval, .finished) == .approval)
        var hold = ClaudeAppAlertHold()
        hold.pillBadged(.error)
        hold.pillBadged(.finished)
        precondition(hold.houseBadge(now: at(0)) == .error, "a later finish does not hide an error")
        hold.alertCame(alert("Claude a fini de répondre", sound: "finish"), presentation: .badgeOnly)
        precondition(hold.houseBadge(now: at(0)) == .error)
        hold.alertCame(alert("Claude attend ta réponse"), presentation: .badgeOnly)
        precondition(hold.houseBadge(now: at(0)) == .approval)
    }

    // Task 27: a card that stepped aside (its session's app came to the front) leaves its request
    // pending: the house tab carries the request's mark while its card is not on screen, whatever
    // app the session runs in (VS Code too, whose pill's badge is drawn nowhere).
    static func aRequestWaitingOffScreenBadgesTheHouseTab() {
        var hold = ClaudeAppAlertHold()
        precondition(hold.houseBadge(now: at(0), requestWaitsOffScreen: true) == .approval, "a request off screen")
        precondition(hold.houseBadge(now: at(0), requestWaitsOffScreen: false) == nil, "its card on screen, or none")
        hold.pillBadged(.finished)
        precondition(hold.houseBadge(now: at(0), requestWaitsOffScreen: true) == .approval, "a request over a finish")
        precondition(hold.houseBadge(now: at(0)) == .finished, "without a request, as before")
        precondition(ClaudeAppAlertHold.requestWaitsOffScreen(approval: true, question: false, view: "approval") == false,
                     "the permission's card on screen")
        precondition(ClaudeAppAlertHold.requestWaitsOffScreen(approval: true, question: false, view: "prompt"),
                     "the chat over a pending permission")
        precondition(ClaudeAppAlertHold.requestWaitsOffScreen(approval: true, question: true, view: "question"),
                     "the question's card on screen, the permission behind it")
        precondition(!ClaudeAppAlertHold.requestWaitsOffScreen(approval: false, question: false, view: "overview"),
                     "nothing pending")
        precondition(IslandView(rawValue: "approval") == .approval && IslandView(rawValue: "question") == .question,
                     "the card views' raw values are the ones the rule reads")
    }

    // The user went to the Claude app: what it has to say is there, the tab is clear.
    static func theClaudeAppInFrontClearsTheHouseTab() {
        var hold = ClaudeAppAlertHold()
        hold.pillBadged(.finished)
        hold.alertCame(alert("Claude attend ta réponse"), presentation: .badgeOnly)
        hold.claudeAppCameToFront()
        precondition(hold.houseBadge(now: at(0)) == nil)
        precondition(hold.held == nil && hold.unseenBadge == nil)
    }

    // MARK: - Residuals of the final re-review

    static func codeTabAlert(_ session: String?, at seconds: TimeInterval = 0) -> HeldClaudeAppAlert {
        HeldClaudeAppAlert(title: "Claude attend ta réponse",
                           message: "Une autorisation t'attend dans l'app Claude : essai-a",
                           sound: "approval", heldAt: at(seconds), sessionId: session)
    }

    // I-1: A's permission was held under B's card; Baptiste answers A in the Claude app (its tool
    // runs: PostToolUse of A), then answers B's card. The island must not show « Une autorisation
    // t'attend » for A: its session moved on. The house tab loses the mark with it.
    static func aHeldAlertOfASessionThatMovedOnIsDropped() {
        var hold = ClaudeAppAlertHold()
        hold.alertCame(codeTabAlert("A"), presentation: .badgeOnly)
        precondition(hold.houseBadge(now: at(5)) == .approval)
        hold.sessionMovedOn("A")
        precondition(hold.held == nil, "A answered in the app: nothing waits any more")
        precondition(hold.houseBadge(now: at(6)) == nil)
        precondition(hold.takeForHome(presentation: home, now: at(10)) == nil, "B's card leaves: the home")
    }

    static func anotherSessionMovingOnKeepsTheHeldAlert() {
        var hold = ClaudeAppAlertHold()
        hold.alertCame(codeTabAlert("A"), presentation: .badgeOnly)
        hold.sessionMovedOn("B")
        precondition(hold.held == codeTabAlert("A"), "B's events say nothing about A")
        precondition(hold.takeForHome(presentation: home, now: at(10)) == codeTabAlert("A"))
        // The unseen pill badge is another signal: a session moving on leaves it.
        var badged = ClaudeAppAlertHold()
        badged.pillBadged(.finished)
        badged.sessionMovedOn("A")
        precondition(badged.houseBadge(now: at(0)) == .finished)
    }

    // A Chat or Cowork alert (the watch) belongs to no hook session: only the Claude app in front,
    // a newer alert or the 30 min drop it.
    static func aWatchAlertHasNoSessionToMoveOn() {
        var hold = ClaudeAppAlertHold()
        hold.alertCame(codeTabAlert(nil), presentation: .badgeOnly)
        hold.sessionMovedOn("A")
        precondition(hold.held == codeTabAlert(nil))
        precondition(alert("Claude a fini de répondre").sessionId == nil, "no session unless given")
    }

    // M-1: at 30 min the island drops the held alert itself (one wake-up, no polling), so its mark
    // goes without waiting for something else to redraw the header.
    static func aHeldAlertPast30MinIsDroppedAtItsExpiry() {
        var hold = ClaudeAppAlertHold()
        hold.alertCame(codeTabAlert("A"), presentation: .badgeOnly)
        precondition(!hold.dropExpired(now: at(1_800)), "30 min to the second: kept")
        precondition(hold.held != nil)
        precondition(hold.dropExpired(now: at(1_801)), "past 30 min: dropped, and it says so")
        precondition(hold.held == nil && hold.houseBadge(now: at(1_801)) == nil)
        precondition(!hold.dropExpired(now: at(1_802)), "nothing left to drop")
        // A newer alert held since keeps its own 30 min.
        hold.alertCame(codeTabAlert("A", at: 1_000), presentation: .badgeOnly)
        precondition(!hold.dropExpired(now: at(1_801)))
        precondition(hold.held == codeTabAlert("A", at: 1_000))
    }

    // MARK: - 0.3.6: one held item per session, finishes too (C5, I8, I6, I7, M4)

    static func note(_ session: String?, _ sound: String = "approval", at seconds: TimeInterval = 0) -> HeldClaudeAppAlert {
        HeldClaudeAppAlert(title: "Claude attend ta réponse",
                           message: "Une autorisation t'attend dans l'app Claude : \(session ?? "chat")",
                           sound: sound, heldAt: at(seconds), sessionId: session)
    }

    static func row(_ id: String, pill: String = "agent_claude-desktop", phase: SessionPhase = .finished) -> SessionRow {
        SessionRow(id: id, pillId: pill, title: "Session \(id)", phase: phase, lastAction: "Les tests passent.",
                   updatedAt: at(0), folder: "projet-\(id)")
    }

    // Baptiste runs several Code tab sessions: the busy island keeps what each of them said, one item
    // per session (its newest), the Chat and Cowork watch one slot, 5 items at most, newest first.
    static func oneItemPerSessionFiveAtMostNewestFirst() {
        var hold = ClaudeAppAlertHold()
        hold.alertCame(note("A", at: 0), presentation: .badgeOnly)
        hold.alertCame(note("B", at: 1), presentation: .badgeOnly)
        precondition(hold.items.map(\.sessionId) == ["B", "A"], "both kept, newest first: \(hold.items)")
        hold.alertCame(note("A", "question", at: 2), presentation: .badgeOnly)
        precondition(hold.items.map(\.sessionId) == ["A", "B"], "A's newer item replaces its older one")
        precondition(hold.item(of: "A") == note("A", "question", at: 2))
        hold.alertCame(note(nil, at: 3), presentation: .badgeOnly)
        hold.alertCame(note(nil, "finish", at: 4), presentation: .badgeOnly)
        precondition(hold.items.map(\.sessionId) == [nil, "A", "B"], "one slot for the Chat and Cowork watch")
        for (i, id) in ["C", "D", "E"].enumerated() {
            hold.alertCame(note(id, at: 5 + TimeInterval(i)), presentation: .badgeOnly)
        }
        precondition(ClaudeAppAlertHold.limit == 5)
        precondition(hold.items.map(\.sessionId) == ["E", "D", "C", nil, "A"], "5 at most: the oldest (B) went")
    }

    // C5: an alert of B shown on screen no longer drops A's held request.
    static func aShownAlertKeepsTheOtherSessionsItems() {
        var hold = ClaudeAppAlertHold()
        hold.alertCame(note("A"), presentation: .badgeOnly)
        hold.alertCame(note("B", "question", at: 5), presentation: .open)
        precondition(hold.items == [note("A")], "A still waits in the app: still held")
        // B's own older item goes when B's newer one shows.
        hold.alertCame(note("B", at: 6), presentation: .badgeOnly)
        hold.alertCame(note("B", "question", at: 7), presentation: .open)
        precondition(hold.items == [note("A")])
    }

    // When the island frees, the held items show one after the other, newest first.
    static func heldItemsShowOneAfterTheOtherNewestFirst() {
        var hold = ClaudeAppAlertHold()
        hold.alertCame(note("A", at: 0), presentation: .badgeOnly)
        hold.hold(.finish(row("B", pill: "integration_claude"), failed: false, at: at(1)))
        hold.alertCame(note(nil, "finish", at: 2), presentation: .badgeOnly)
        precondition(hold.takeForHome(presentation: home, now: at(10))?.sessionId == nil, "the newest first")
        precondition(hold.takeForHome(presentation: home, now: at(11))?.finished == row("B", pill: "integration_claude"))
        precondition(hold.takeForHome(presentation: home, now: at(12)) == note("A"))
        precondition(hold.takeForHome(presentation: home, now: at(13)) == nil, "then the home")
        // The island still busy: nothing is taken.
        hold.alertCame(note("A"), presentation: .badgeOnly)
        for (why, presentation) in busy {
            precondition(hold.takeForHome(presentation: presentation, now: at(20)) == nil, "\(why): kept")
        }
        precondition(hold.items.count == 1)
    }

    // I8: the end of any session the busy island could not show (VS Code and the terminal too) is held
    // with its row, and marks the house tab with its own badge.
    static func aFinishTheBusyIslandCouldNotShowIsHeld() {
        let vsCode = row("V", pill: "integration_claude")
        let finish = HeldClaudeAppAlert.finish(vsCode, failed: false, at: at(0))
        precondition(finish.finished == vsCode && finish.sessionId == "V" && finish.sound == "finish")
        precondition(finish.badge == .finished && !finish.asksSomething && !finish.fromClaudeApp)
        let failure = HeldClaudeAppAlert.finish(row("W", phase: .error), failed: true, at: at(0))
        precondition(failure.sound == "error" && failure.badge == .error && failure.fromClaudeApp)
        var hold = ClaudeAppAlertHold()
        hold.hold(finish)
        precondition(hold.houseBadge(now: at(5)) == .finished)
        hold.hold(failure)
        precondition(hold.houseBadge(now: at(5)) == .error, "an error over a finish")
        hold.alertCame(note("A"), presentation: .badgeOnly)
        precondition(hold.houseBadge(now: at(5)) == .approval, "a request over both")
        // Its session moving on (a new prompt, SessionEnd) drops it, as for the alerts.
        hold.sessionMovedOn("V")
        precondition(hold.item(of: "V") == nil && hold.items.count == 2)
    }

    // Drop rules unchanged: the Claude app in front drops its own items (Code tab sessions, Chat and
    // Cowork), never the end of a VS Code or terminal session.
    static func theClaudeAppInFrontDropsOnlyItsOwnItems() {
        var hold = ClaudeAppAlertHold()
        hold.hold(.finish(row("V", pill: "integration_claude"), failed: false, at: at(0)))
        hold.hold(.finish(row("D"), failed: false, at: at(1)))
        hold.alertCame(note("A", at: 2), presentation: .badgeOnly)
        hold.alertCame(note(nil, "finish", at: 3), presentation: .badgeOnly)
        hold.pillBadged(.finished)
        hold.claudeAppCameToFront()
        precondition(hold.items.map(\.sessionId) == ["V"], "only the VS Code session's end stays: \(hold.items)")
        precondition(hold.unseenBadge == nil)
        precondition(hold.houseBadge(now: at(5)) == .finished)
    }

    // The house tab counts the held items (the view writes the number from 2 on); none past 30 min.
    static func theHouseTabCountsTheHeldItems() {
        var hold = ClaudeAppAlertHold()
        precondition(hold.count(now: at(0)) == 0)
        hold.alertCame(note("A", at: 0), presentation: .badgeOnly)
        hold.alertCame(note("B", at: 600), presentation: .badgeOnly)
        hold.hold(.finish(row("C", pill: "integration_claude"), failed: false, at: at(900)))
        precondition(hold.count(now: at(1_000)) == 3)
        precondition(hold.count(now: at(1_801)) == 2, "A is past 30 min")
        _ = hold.takeForHome(presentation: home, now: at(1_802))
        precondition(hold.count(now: at(1_802)) == 1, "A dropped, C shown")
    }

    // I7: a request of the Claude app pill that shows or leaves keeps the other sessions' marks; a
    // request's own mark is never kept as unseen (the pending requests are read live).
    static func aRequestShowingOrLeavingKeepsTheOtherMarks() {
        var hold = ClaudeAppAlertHold()
        hold.pillBadged(.approval)
        precondition(hold.unseenBadge == nil && hold.houseBadge(now: at(0)) == nil, "a request's mark is not kept")
        hold.pillBadged(.finished)
        precondition(hold.houseBadge(now: at(0), requestWaitsOffScreen: true) == .approval, "A's request off screen")
        precondition(hold.houseBadge(now: at(1), requestWaitsOffScreen: false) == .finished,
                     "A's request shows or leaves: B's finish still marks the tab")
        hold.homeListShown()
        precondition(hold.houseBadge(now: at(2)) == nil, "the list shows B's row")
    }

    // C5: a note that asks something, replaced on screen by a newer view of another session, goes back
    // into the hold, seen or not: the user still has to answer.
    static func anAskingNoteReplacedGoesBackToTheHold() {
        for sound in ["approval", "question"] {
            let onScreen = note("A", sound)
            precondition(ClaudeAppAlertHold.backToHold(onScreen, replacedBy: "B", shownFor: 0.5, pointerWasOn: false) == onScreen)
            precondition(ClaudeAppAlertHold.backToHold(onScreen, replacedBy: "B", shownFor: 600, pointerWasOn: true) == onScreen,
                         "seen, but not answered")
            precondition(ClaudeAppAlertHold.backToHold(onScreen, replacedBy: nil, shownFor: 1, pointerWasOn: false) == onScreen,
                         "replaced by a Chat alert")
            precondition(ClaudeAppAlertHold.backToHold(onScreen, replacedBy: "A", shownFor: 1, pointerWasOn: false) == nil,
                         "A's own newer view tells it")
        }
        precondition(ClaudeAppAlertHold.backToHold(nil, replacedBy: "B", shownFor: 0, pointerWasOn: false) == nil,
                     "nothing of the hold on screen")
        let watch = note(nil)
        precondition(ClaudeAppAlertHold.backToHold(watch, replacedBy: nil, shownFor: 0, pointerWasOn: false) == nil,
                     "the watch's newer alert replaces its older one")
    }

    // I6: a finished view counts as shown only after 2 s on screen, or once the pointer was on the
    // island; replaced sooner by another session's view, it goes back into the hold.
    static func aFinishReplacedBeforeItWasSeenGoesBack() {
        precondition(ClaudeAppAlertHold.seenAfter == 2)
        precondition(!ClaudeAppAlertHold.finishSeen(shownFor: 1.9, pointerWasOn: false))
        precondition(ClaudeAppAlertHold.finishSeen(shownFor: 2, pointerWasOn: false))
        precondition(ClaudeAppAlertHold.finishSeen(shownFor: 0.3, pointerWasOn: true))
        let finish = HeldClaudeAppAlert.finish(row("A"), failed: false, at: at(0))
        precondition(ClaudeAppAlertHold.backToHold(finish, replacedBy: "B", shownFor: 1, pointerWasOn: false) == finish)
        precondition(ClaudeAppAlertHold.backToHold(finish, replacedBy: "B", shownFor: 2.5, pointerWasOn: false) == nil)
        precondition(ClaudeAppAlertHold.backToHold(finish, replacedBy: "B", shownFor: 1, pointerWasOn: true) == nil)
        precondition(ClaudeAppAlertHold.backToHold(finish, replacedBy: "A", shownFor: 1, pointerWasOn: false) == nil)
        let chatFinished = note(nil, "finish")
        precondition(ClaudeAppAlertHold.backToHold(chatFinished, replacedBy: "B", shownFor: 1, pointerWasOn: false) == chatFinished,
                     "a Chat answer's note not seen yet goes back too")
        precondition(ClaudeAppAlertHold.backToHold(chatFinished, replacedBy: "B", shownFor: 3, pointerWasOn: false) == nil)
    }

    // The next held item shows when the island folds from the note or finished view it showed, or from
    // a view the user was busy in; not from the home, nor from a card that stepped aside.
    static func aFoldFromAHeldOrBusyViewShowsTheNext() {
        for view in [IslandView.note, .finished, .error, .prompt, .mail, .upload, .uploading, .choose, .settings] {
            precondition(ClaudeAppAlertHold.foldShowsNext(fromView: view.rawValue), "\(view)")
        }
        for view in [IslandView.overview, .empty, .greeting, .approval, .question, .confused] {
            precondition(!ClaudeAppAlertHold.foldShowsNext(fromView: view.rawValue), "\(view)")
        }
    }

    // One wake-up at the oldest item's 30 min drops it; the next wake-up is the next oldest's.
    static func theNextExpiryIsTheOldestItems() {
        var hold = ClaudeAppAlertHold()
        precondition(hold.nextExpiry == nil)
        hold.alertCame(note("A", at: 100), presentation: .badgeOnly)
        hold.alertCame(note("B", at: 40), presentation: .badgeOnly)
        precondition(hold.nextExpiry == at(1_840))
        precondition(hold.dropExpired(now: at(1_841)))
        precondition(hold.items == [note("A", at: 100)] && hold.nextExpiry == at(1_900))
    }

    // A session that closes (SessionEnd) right after its end: nobody saw that end, it stays held. What
    // it asked is moot, that goes.
    static func aSessionThatClosesKeepsItsHeldFinish() {
        var hold = ClaudeAppAlertHold()
        hold.hold(.finish(row("A"), failed: false, at: at(0)))
        hold.alertCame(note("B"), presentation: .badgeOnly)
        hold.sessionEnded("A")
        hold.sessionEnded("B")
        precondition(hold.items.map(\.sessionId) == ["A"] && hold.holdsFinish(of: "A"),
                     "A's end stays, B's request goes: \(hold.items)")
        hold.sessionMovedOn("A")
        precondition(hold.items.isEmpty, "a new prompt or tool of A: its end was seen")
    }

    // A session's end held: its idle prompt about 60 s later says nothing more.
    static func aHeldFinishMakesItsIdlePromptRedundant() {
        var hold = ClaudeAppAlertHold()
        hold.alertCame(note("A"), presentation: .badgeOnly)
        precondition(!hold.holdsFinish(of: "A"), "a held alert is no finish")
        hold.hold(.finish(row("A"), failed: false, at: at(1)))
        precondition(hold.holdsFinish(of: "A") && !hold.holdsFinish(of: "B"))
    }

    // M4: two sessions in the same folder, nobody named them: the same text, two alerts.
    static func twoAlertsWithTheSameTextForTwoSessionsAreTwo() {
        let a = ClaudeAppAlert(title: "Claude attend ta réponse", message: "Une autorisation t'attend dans l'app Claude : site",
                               source: .codeSession, sound: "approval", sessionId: "A")
        var b = a
        b.sessionId = "B"
        precondition(a != b, "the second is not swallowed as the same alert")
        var hold = ClaudeAppAlertHold()
        hold.alertCame(HeldClaudeAppAlert(title: a.title, message: a.message, sound: a.sound, heldAt: at(0), sessionId: "A"),
                       presentation: .badgeOnly)
        hold.alertCame(HeldClaudeAppAlert(title: b.title, message: b.message, sound: b.sound, heldAt: at(1), sessionId: "B"),
                       presentation: .badgeOnly)
        precondition(hold.count(now: at(2)) == 2)
    }

    // MARK: - 0.3.6: a request that leaves without an answer (C3, I1)

    // Timed out, replaced by a newer request, handed back by « Répondre dans … », or stepped aside when
    // its app came in front: the request still waits in its app, its row stays on approval or question
    // until the session's next tool event. Answered, handled in the app, or moot: the row goes on.
    static func aRequestHandedBackKeepsItsRowWaiting() {
        for exit in [RequestExit.timedOut, .displaced, .handedBack, .steppedAside] {
            precondition(exit.rowKeepsWaiting, "\(exit)")
        }
        for exit in [RequestExit.answered, .handledElsewhere] {
            precondition(!exit.rowKeepsWaiting, "\(exit)")
        }
    }

    // Only a request the user did not hand back himself, of a session of the Claude app, leaves a held
    // alert (« Une autorisation t'attend dans l'app Claude »): the terminal and VS Code are unchanged.
    static func onlyATimeoutOrANewerRequestHoldsAClaudeAppAlert() {
        precondition(RequestExit.timedOut.holdsAlert(claudeAppSession: true))
        precondition(RequestExit.displaced.holdsAlert(claudeAppSession: true))
        for exit in [RequestExit.answered, .handledElsewhere, .handedBack, .steppedAside] {
            precondition(!exit.holdsAlert(claudeAppSession: true), "\(exit)")
        }
        for exit in [RequestExit.timedOut, .displaced] {
            precondition(!exit.holdsAlert(claudeAppSession: false), "\(exit): not for VS Code or the terminal")
        }
    }
}

/// IslandTypes.swift (compiled here for `PillBadge` and `IslandView`) names `EyeShape`, which
/// BotEngine.swift defines with SwiftUI drawing around it: an empty stand-in is enough here.
enum EyeShape: Equatable {}
