import Foundation

/// A Notification hook of a session of the Claude app that says Claude waits for the user (lot 6
/// spec §5, Task 20). The fields are those of the Claude Code hooks reference, Notification input:
/// `message`, an optional `title`, and `notification_type` (`permission_prompt`, `idle_prompt`,
/// `elicitation_dialog`, `elicitation_url_dialog`, and the types that ask nothing: `auth_success`,
/// `elicitation_complete`, `elicitation_response`, `agent_needs_input`, `agent_completed`,
/// `quota_auto_resume_*`). Older Claude Code sends the message only. The terminal never opens the
/// island from here (Baptiste: « Je veux pas que ça soit fait pour le terminal »). An `idle_prompt`
/// comes about 60 s after the end of a turn: when the finish was already shown (the session's row is
/// finished or failed), it does not open the island a second time.
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
            ("an_idle_prompt_opens_without_a_finished_row", anIdlePromptOpensWithoutAFinishedRow),
            ("a_permission_or_an_elicitation_opens_on_any_row", aPermissionOrAnElicitationOpensOnAnyRow),
            ("a_held_card_is_the_sessions_own", aHeldCardIsTheSessionsOwn),
            ("the_terminal_never_opens", theTerminalNeverOpens),
            ("near_misses_of_the_desktop_tag_never_open", nearMissesOfTheDesktopTagNeverOpen),
            ("a_permission_puts_the_row_on_approval", aPermissionPutsTheRowOnApproval),
            ("a_wait_puts_the_row_on_question", aWaitPutsTheRowOnQuestion),
            ("a_wait_leaves_an_ended_row_as_it_is", aWaitLeavesAnEndedRowAsItIs),
            ("an_idle_row_goes_on_question_unless_ended", anIdleRowGoesOnQuestionUnlessEnded),
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
            precondition(CodeNotification.shouldOpen(kind: kind, sessionHasCard: false, agent: desktop,
                                                     currentPhase: nil),
                         "a session of the Claude app with no card of its own opens the island")
        }
    }

    // Spec review focus 4: the card of that session is already on screen (or waits for the pointer):
    // no second view over it.
    static func aCardOfTheSessionPreventsASecondAlert() {
        for kind in allKinds {
            for phase in phasesAndNone {
                precondition(!CodeNotification.shouldOpen(kind: kind, sessionHasCard: true, agent: desktop,
                                                          currentPhase: phase),
                             "no duplicate when the session's card is held")
            }
        }
    }

    // The finished view was the notification: the idle prompt that follows it about 60 s later does
    // not open the island a second time, whether the session finished or failed.
    static func anIdlePromptAfterAShownFinishDoesNotOpen() {
        for ended in [SessionPhase.finished, .error] {
            precondition(!CodeNotification.shouldOpen(kind: .idle, sessionHasCard: false, agent: desktop,
                                                      currentPhase: ended),
                         "an idle prompt after a \(ended) row shows nothing new")
        }
    }

    // Nothing was shown for a session that is still running, idle, or that the island never saw.
    static func anIdlePromptOpensWithoutAFinishedRow() {
        precondition(CodeNotification.shouldOpen(kind: .idle, sessionHasCard: false, agent: desktop,
                                                 currentPhase: nil),
                     "no row: nothing was shown, the idle prompt opens")
        for running in SessionPhase.allCases where !running.isEnded {
            precondition(CodeNotification.shouldOpen(kind: .idle, sessionHasCard: false, agent: desktop,
                                                     currentPhase: running),
                         "an idle prompt with a \(running) row opens")
        }
    }

    // Only the idle prompt is a repeat of the finish: a permission, or an MCP server's form, is a new
    // request whatever the row says.
    static func aPermissionOrAnElicitationOpensOnAnyRow() {
        for kind in [CodeNotification.Kind.permission, .waiting] {
            for phase in phasesAndNone {
                precondition(CodeNotification.shouldOpen(kind: kind, sessionHasCard: false, agent: desktop,
                                                         currentPhase: phase),
                             "\(kind) opens with a \(String(describing: phase)) row")
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
                    // Claude Code in a terminal or an editor sends no klayer_agent.
                    precondition(!CodeNotification.shouldOpen(kind: kind, sessionHasCard: hasCard, agent: "",
                                                              currentPhase: phase),
                                 "a terminal session never opens the island from a notification")
                    // Any other agent is not followed at all.
                    precondition(!CodeNotification.shouldOpen(kind: kind, sessionHasCard: hasCard, agent: "codex",
                                                              currentPhase: phase))
                }
            }
        }
    }

    static func nearMissesOfTheDesktopTagNeverOpen() {
        for near in ["Claude-Desktop", "claude", "claude-desktop2", " claude-desktop", "claude-desktop "] {
            precondition(!CodeNotification.shouldOpen(kind: .permission, sessionHasCard: false, agent: near,
                                                      currentPhase: nil),
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
    // question, an ended one stays (it does not even open the island, `shouldOpen`).
    static func anIdleRowGoesOnQuestionUnlessEnded() {
        precondition(CodeNotification.rowPhase(for: .idle, current: nil) == .question)
        for current in SessionPhase.allCases {
            let expected: SessionPhase? = current.isEnded ? nil : .question
            precondition(CodeNotification.rowPhase(for: .idle, current: current) == expected,
                         "idle prompt over a \(current) row")
        }
    }
}
