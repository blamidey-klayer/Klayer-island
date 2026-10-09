import Foundation

/// A Notification hook of a session of the Claude app that says Claude waits for the user (lot 6
/// spec §5, Task 20). The fields are those of the Claude Code hooks reference, Notification input:
/// `message`, an optional `title`, and `notification_type` (`permission_prompt`, `idle_prompt`,
/// `elicitation_dialog`, `elicitation_url_dialog`, and the types that ask nothing: `auth_success`,
/// `elicitation_complete`, `elicitation_response`, `agent_needs_input`, `agent_completed`,
/// `quota_auto_resume_*`). Older Claude Code sends the message only. The terminal never opens the
/// island from here (Baptiste: « Je veux pas que ça soit fait pour le terminal »).
@main
enum CodeNotificationTests {
    static func main() {
        let cases: [(String, () -> Void)] = [
            ("a_permission_prompt_is_a_permission", aPermissionPromptIsAPermission),
            ("an_idle_prompt_and_the_elicitations_are_a_wait", anIdlePromptAndTheElicitationsAreAWait),
            ("the_other_documented_types_ask_nothing", theOtherDocumentedTypesAskNothing),
            ("the_type_wins_over_the_message", theTypeWinsOverTheMessage),
            ("an_unknown_type_asks_nothing", anUnknownTypeAsksNothing),
            ("older_claude_code_is_read_from_the_message", olderClaudeCodeIsReadFromTheMessage),
            ("an_empty_type_is_no_type", anEmptyTypeIsNoType),
            ("a_message_that_asks_nothing_alerts_nothing", aMessageThatAsksNothingAlertsNothing),
            ("only_the_claude_app_opens", onlyTheClaudeAppOpens),
            ("a_card_of_the_session_prevents_a_second_alert", aCardOfTheSessionPreventsASecondAlert),
            ("the_terminal_never_opens", theTerminalNeverOpens),
            ("near_misses_of_the_desktop_tag_never_open", nearMissesOfTheDesktopTagNeverOpen),
            ("a_permission_puts_the_row_on_approval", aPermissionPutsTheRowOnApproval),
            ("a_wait_puts_the_row_on_question", aWaitPutsTheRowOnQuestion),
            ("a_wait_leaves_an_ended_row_as_it_is", aWaitLeavesAnEndedRowAsItIs),
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

    static func anIdlePromptAndTheElicitationsAreAWait() {
        for type in ["idle_prompt", "elicitation_dialog", "elicitation_url_dialog"] {
            precondition(CodeNotification.alert(message: "Claude is waiting for your input",
                                                notificationType: type) == .waiting,
                         "\(type) is Claude waiting for the user")
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
                                            notificationType: "idle_prompt") == .waiting)
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
                                            notificationType: nil) == .waiting)
        // Case does not matter.
        precondition(CodeNotification.alert(message: "CLAUDE NEEDS YOUR PERMISSION TO USE EDIT",
                                            notificationType: nil) == .permission)
        precondition(CodeNotification.alert(message: "claude is waiting for your input",
                                            notificationType: nil) == .waiting)
    }

    static func anEmptyTypeIsNoType() {
        for blank in ["", "  "] {
            precondition(CodeNotification.alert(message: "Claude needs your permission to use Bash",
                                                notificationType: blank) == .permission)
            precondition(CodeNotification.alert(message: "Claude is waiting for your input",
                                                notificationType: blank) == .waiting)
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

    static func onlyTheClaudeAppOpens() {
        for kind in [CodeNotification.Kind.permission, .waiting] {
            precondition(CodeNotification.shouldOpen(kind: kind, sessionHasCard: false, agent: desktop),
                         "a session of the Claude app with no card of its own opens the island")
        }
    }

    // Spec review focus 4: the card of that session is already on screen (or waits for the pointer):
    // no second view over it.
    static func aCardOfTheSessionPreventsASecondAlert() {
        for kind in [CodeNotification.Kind.permission, .waiting] {
            precondition(!CodeNotification.shouldOpen(kind: kind, sessionHasCard: true, agent: desktop),
                         "no duplicate when the session's card is held")
        }
    }

    static func theTerminalNeverOpens() {
        for kind in [CodeNotification.Kind.permission, .waiting] {
            for hasCard in [false, true] {
                // Claude Code in a terminal or an editor sends no klayer_agent.
                precondition(!CodeNotification.shouldOpen(kind: kind, sessionHasCard: hasCard, agent: ""),
                             "a terminal session never opens the island from a notification")
                // Any other agent is not followed at all.
                precondition(!CodeNotification.shouldOpen(kind: kind, sessionHasCard: hasCard, agent: "codex"))
            }
        }
    }

    static func nearMissesOfTheDesktopTagNeverOpen() {
        for near in ["Claude-Desktop", "claude", "claude-desktop2", " claude-desktop", "claude-desktop "] {
            precondition(!CodeNotification.shouldOpen(kind: .permission, sessionHasCard: false, agent: near),
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
}
