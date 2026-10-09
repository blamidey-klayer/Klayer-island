import Foundation

/// Chat and Cowork in the Claude app, followed through the app's interface (lot 6 spec §6, Task 21).
/// The Claude app emits no hook for them, so the island reads the buttons of its interface through
/// macOS Accessibility: a stop button that appears then disappears is a finished answer, an allow
/// button next to a deny button is a permission asked. The island opens only when the Claude app is
/// not in front, never for a label it does not know, and stays quiet within 15 s of a hook of the
/// Code tab (which tells the same thing through Claude Code). Nothing here reads message text: only
/// the role and the label of buttons.
@main
enum ClaudeAppWatchTests {
    static func main() {
        let cases: [(String, () -> Void)] = [
            // Labels (ClaudeAppWatchRules, the only place they live)
            ("a_stop_label_matches_whatever_its_case_and_spaces", aStopLabelMatchesWhateverItsCaseAndSpaces),
            ("a_label_matches_exactly_never_by_containing", aLabelMatchesExactlyNeverByContaining),
            ("only_a_button_can_be_a_stop", onlyAButtonCanBeAStop),
            ("the_seeded_labels_are_english_and_french", theSeededLabelsAreEnglishAndFrench),
            ("a_permission_needs_an_allow_and_a_deny", aPermissionNeedsAnAllowAndADeny),
            ("allow_without_deny_is_no_prompt", allowWithoutDenyIsNoPrompt),
            ("a_curly_apostrophe_is_the_same_label", aCurlyApostropheIsTheSameLabel),
            ("the_label_is_the_description_then_the_title_then_the_help", theLabelIsTheDescriptionThenTheTitleThenTheHelp),
            // The Code tab already reports through its hooks
            ("a_code_hook_14_s_ago_keeps_the_watch_quiet", aCodeHook14SAgoKeepsTheWatchQuiet),
            ("a_code_hook_16_s_ago_does_not", aCodeHook16SAgoDoesNot),
            // The state machine
            ("an_answer_finished_in_front_says_nothing", anAnswerFinishedInFrontSaysNothing),
            ("an_answer_finished_in_the_background_opens_the_island", anAnswerFinishedInTheBackgroundOpensTheIsland),
            ("switching_away_during_an_answer_tells_its_end", switchingAwayDuringAnAnswerTellsItsEnd),
            ("no_label_known_no_event_and_no_reading_in_the_background", noLabelKnownNoEventAndNoReadingInTheBackground),
            ("a_permission_alerts_once_per_appearance", aPermissionAlertsOncePerAppearance),
            ("a_permission_seen_in_front_never_alerts", aPermissionSeenInFrontNeverAlerts),
            ("a_stop_that_gives_way_to_a_permission_is_no_finished_answer", aStopThatGivesWayToAPermissionIsNoFinishedAnswer),
            ("an_event_kept_quiet_by_a_code_hook_is_consumed", anEventKeptQuietByACodeHookIsConsumed),
            ("polling_only_in_front_or_during_an_answer", pollingOnlyInFrontOrDuringAnAnswer),
            ("a_reset_forgets_everything", aResetForgetsEverything),
            // The alert, the permission prompt, the test launch
            ("the_alert_line_is_the_conversation_title_when_readable", theAlertLineIsTheConversationTitleWhenReadable),
            ("the_accessibility_prompt_shows_once_ever_on_its_own", theAccessibilityPromptShowsOnceEverOnItsOwn),
            ("a_test_launch_never_watches", aTestLaunchNeverWatches),
            // The diagnostic copied by Baptiste
            ("the_diagnostic_lists_unique_button_lines", theDiagnosticListsUniqueButtonLines),
            ("the_diagnostic_truncates_labels_and_lines", theDiagnosticTruncatesLabelsAndLines),
            ("the_diagnostic_never_holds_the_window_title", theDiagnosticNeverHoldsTheWindowTitle),
            ("the_diagnostic_tells_when_nothing_can_be_read", theDiagnosticTellsWhenNothingCanBeRead),
        ]
        for (name, run) in cases {
            run()
            print("  ok  \(name)")
        }
        print("Claude app watch: \(cases.count) cases passed")
    }

    static func button(_ label: String) -> AXNodeSummary { AXNodeSummary(role: "AXButton", label: label) }
    static let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)
    static func at(_ seconds: TimeInterval) -> Date { t0.addingTimeInterval(seconds) }

    // MARK: - Labels

    static func aStopLabelMatchesWhateverItsCaseAndSpaces() {
        for label in ["Stop response", "stop response", "STOP RESPONSE", "  Stop response \n", "Arrêter la réponse",
                      "ARRÊTER LA RÉPONSE", "arrêter", "Stop"] {
            precondition(ClaudeAppWatchRules.isStop(button(label)), "« \(label) » is a stop button")
        }
    }

    static func aLabelMatchesExactlyNeverByContaining() {
        for label in ["Stop responses", "Stop response now", "Don't stop", "Stop generating", "Arrêter la lecture",
                      "", "   ", "Send message", "Stopper"] {
            precondition(!ClaudeAppWatchRules.isStop(button(label)), "« \(label) » is not a stop button")
        }
        for label in ["Allow notifications", "Allowed", "Autoriser les notifications", "Always allow notifications"] {
            precondition(!ClaudeAppWatchRules.isPermissionAllow(button(label)), "« \(label) » allows nothing asked")
        }
        for label in ["Deny all cookies", "Refuser les cookies"] {
            precondition(!ClaudeAppWatchRules.isPermissionDeny(button(label)), "« \(label) » denies nothing asked")
        }
    }

    static func onlyAButtonCanBeAStop() {
        for role in ["AXButton", "AXMenuButton", "AXPopUpButton"] {
            precondition(ClaudeAppWatchRules.isStop(AXNodeSummary(role: role, label: "Stop response")), role)
        }
        for role in ["AXStaticText", "AXLink", "AXTextArea", "AXGroup", "AXHeading", ""] {
            precondition(!ClaudeAppWatchRules.isStop(AXNodeSummary(role: role, label: "Stop response")),
                         "a \(role) is never read as a stop")
            precondition(!ClaudeAppWatchRules.hasPermissionPrompt([AXNodeSummary(role: role, label: "Allow"),
                                                                   AXNodeSummary(role: role, label: "Deny")]),
                         "a \(role) is never read as a permission")
        }
    }

    static func theSeededLabelsAreEnglishAndFrench() {
        for label in ["Stop response", "Stop", "Arrêter la réponse", "Arrêter"] {
            precondition(ClaudeAppWatchRules.stopLabels.contains(label), label)
        }
        for label in ["Allow", "Allow once", "Always allow", "Allow always", "Autoriser", "Autoriser une fois",
                      "Toujours autoriser"] {
            precondition(ClaudeAppWatchRules.permissionAllowLabels.contains(label), label)
        }
        for label in ["Deny", "Don't allow", "Refuser", "Ne pas autoriser"] {
            precondition(ClaudeAppWatchRules.permissionDenyLabels.contains(label), label)
        }
        precondition(Set(ClaudeAppWatchRules.permissionLabels)
                     == Set(ClaudeAppWatchRules.permissionAllowLabels + ClaudeAppWatchRules.permissionDenyLabels))
    }

    static func aPermissionNeedsAnAllowAndADeny() {
        precondition(ClaudeAppWatchRules.hasPermissionPrompt([button("Allow once"), button("Deny")]))
        precondition(ClaudeAppWatchRules.hasPermissionPrompt([button("Send"), button("always allow"),
                                                              button("Don't allow"), button("Copy")]))
        precondition(ClaudeAppWatchRules.hasPermissionPrompt([button("Autoriser une fois"), button("Refuser")]))
        precondition(ClaudeAppWatchRules.hasPermissionPrompt([button(" Toujours autoriser "), button("NE PAS AUTORISER")]))
    }

    static func allowWithoutDenyIsNoPrompt() {
        precondition(!ClaudeAppWatchRules.hasPermissionPrompt([button("Allow")]))
        precondition(!ClaudeAppWatchRules.hasPermissionPrompt([button("Autoriser"), button("Allow once")]))
        precondition(!ClaudeAppWatchRules.hasPermissionPrompt([button("Deny"), button("Refuser")]))
        precondition(!ClaudeAppWatchRules.hasPermissionPrompt([button("Allow notifications"), button("Deny")]),
                     "an allow-like label that is not exact does not count")
        precondition(!ClaudeAppWatchRules.hasPermissionPrompt([]))
    }

    // The interface may write Don’t with a typographic apostrophe.
    static func aCurlyApostropheIsTheSameLabel() {
        precondition(ClaudeAppWatchRules.isPermissionDeny(button("Don\u{2019}t allow")))
        precondition(ClaudeAppWatchRules.hasPermissionPrompt([button("Allow"), button("Don\u{2019}t Allow")]))
    }

    static func theLabelIsTheDescriptionThenTheTitleThenTheHelp() {
        precondition(ClaudeAppWatchRules.label(description: "Stop response", title: "Stop", help: "Stops") == "Stop response")
        precondition(ClaudeAppWatchRules.label(description: "  ", title: "Stop", help: "Stops") == "Stop")
        precondition(ClaudeAppWatchRules.label(description: nil, title: "", help: "Stops") == "Stops")
        precondition(ClaudeAppWatchRules.label(description: nil, title: nil, help: nil) == "")
        precondition(ClaudeAppWatchRules.label(description: " Allow ", title: nil, help: nil) == "Allow",
                     "the label is trimmed")
        // The reader asks one attribute at a time, stops at the first label, and never asks AXValue.
        precondition(ClaudeAppWatchRules.labelAttributes == ["AXDescription", "AXTitle", "AXHelp"])
        var asked: [String] = []
        let found = ClaudeAppWatchRules.label { attribute in
            asked.append(attribute)
            return attribute == "AXTitle" ? "Stop" : nil
        }
        precondition(found == "Stop" && asked == ["AXDescription", "AXTitle"], "no read past the label: \(asked)")
    }

    // MARK: - The Code tab's hooks

    static func aCodeHook14SAgoKeepsTheWatchQuiet() {
        precondition(ClaudeAppWatchRules.suppressedByCodeHook(lastHookAt: at(0), now: at(14)))
        precondition(ClaudeAppWatchRules.suppressedByCodeHook(lastHookAt: at(0), now: at(0)))
        precondition(ClaudeAppWatchRules.suppressedByCodeHook(lastHookAt: at(0), now: at(15)), "15 s is still within")
    }

    static func aCodeHook16SAgoDoesNot() {
        precondition(!ClaudeAppWatchRules.suppressedByCodeHook(lastHookAt: at(0), now: at(16)))
        precondition(!ClaudeAppWatchRules.suppressedByCodeHook(lastHookAt: nil, now: at(16)), "no hook ever: never quiet")
    }

    // MARK: - The state machine

    static func anAnswerFinishedInFrontSaysNothing() {
        var s = ClaudeAppWatchState()
        precondition(s.observe(stopVisible: true, permissionVisible: false, appFrontmost: true, now: at(0)).isEmpty)
        precondition(s.observe(stopVisible: true, permissionVisible: false, appFrontmost: true, now: at(2)).isEmpty)
        precondition(s.observe(stopVisible: false, permissionVisible: false, appFrontmost: true, now: at(4)).isEmpty,
                     "the user saw the answer end")
        // It went to the background afterwards: still nothing, and nothing more to read.
        precondition(s.observe(stopVisible: false, permissionVisible: false, appFrontmost: false, now: at(6)).isEmpty)
        precondition(!s.needsPolling)
    }

    static func anAnswerFinishedInTheBackgroundOpensTheIsland() {
        var s = ClaudeAppWatchState()
        precondition(s.observe(stopVisible: true, permissionVisible: false, appFrontmost: false, now: at(0)).isEmpty)
        precondition(s.needsPolling, "an answer is under way: read again")
        precondition(s.observe(stopVisible: true, permissionVisible: false, appFrontmost: false, now: at(2)).isEmpty)
        precondition(s.observe(stopVisible: false, permissionVisible: false, appFrontmost: false, now: at(4))
                     == [.answerFinished])
        precondition(!s.needsPolling, "the answer ended in the background: no more reading")
        precondition(s.observe(stopVisible: false, permissionVisible: false, appFrontmost: false, now: at(6)).isEmpty,
                     "once only")
    }

    // Review Focus 1: the user types in the Claude app, sends, then goes to another app while Claude
    // answers. The read done on that switch sees the stop button, so reading goes on until its end.
    static func switchingAwayDuringAnAnswerTellsItsEnd() {
        var s = ClaudeAppWatchState()
        precondition(s.observe(stopVisible: false, permissionVisible: false, appFrontmost: true, now: at(0)).isEmpty)
        precondition(s.needsPolling, "the Claude app is in front: read")
        precondition(s.observe(stopVisible: true, permissionVisible: false, appFrontmost: true, now: at(2)).isEmpty)
        // Another app becomes active: the immediate read, with the Claude app now behind.
        precondition(s.observe(stopVisible: true, permissionVisible: false, appFrontmost: false, now: at(3)).isEmpty)
        precondition(s.needsPolling, "the answer is still under way: keep reading in the background")
        precondition(s.observe(stopVisible: true, permissionVisible: false, appFrontmost: false, now: at(5)).isEmpty)
        precondition(s.observe(stopVisible: false, permissionVisible: false, appFrontmost: false, now: at(7))
                     == [.answerFinished], "the end of the answer opens the island")
        precondition(!s.needsPolling)

        // The same switch with the stop button first seen by the switch's own read.
        var t = ClaudeAppWatchState()
        precondition(t.observe(stopVisible: false, permissionVisible: false, appFrontmost: true, now: at(0)).isEmpty)
        precondition(t.observe(stopVisible: true, permissionVisible: false, appFrontmost: false, now: at(1)).isEmpty)
        precondition(t.needsPolling)
        precondition(t.observe(stopVisible: false, permissionVisible: false, appFrontmost: false, now: at(3))
                     == [.answerFinished])
    }

    // Review Focus 2: the interface has none of the known labels (Anthropic renamed them, or another
    // language). Nothing fires, and nothing is read once the Claude app is behind.
    static func noLabelKnownNoEventAndNoReadingInTheBackground() {
        let screens: [[AXNodeSummary]] = [
            [button("Send message"), button("Attach"), AXNodeSummary(role: "AXMenuButton", label: "Model")],
            [button("Stop generating"), button("Approve"), button("Reject")],
            [button("Arrêter la génération"), button("Accepter"), button("Décliner")],
            [],
        ]
        var s = ClaudeAppWatchState()
        var step: TimeInterval = 0
        for front in [true, false, true, false] {
            for nodes in screens + screens.reversed() {
                let stop = ClaudeAppWatchRules.stopVisible(nodes)
                let prompt = ClaudeAppWatchRules.hasPermissionPrompt(nodes)
                precondition(!stop && !prompt, "no known label in \(nodes)")
                step += 2
                precondition(s.observe(stopVisible: stop, permissionVisible: prompt, appFrontmost: front,
                                       now: at(step)).isEmpty, "no event, ever")
                precondition(s.needsPolling == front, "reading only while the Claude app is in front")
            }
        }
    }

    static func aPermissionAlertsOncePerAppearance() {
        var s = ClaudeAppWatchState()
        // Claude answers in the background, then asks.
        precondition(s.observe(stopVisible: true, permissionVisible: false, appFrontmost: false, now: at(0)).isEmpty)
        precondition(s.observe(stopVisible: true, permissionVisible: true, appFrontmost: false, now: at(2))
                     == [.permissionRequested])
        precondition(s.observe(stopVisible: true, permissionVisible: true, appFrontmost: false, now: at(4)).isEmpty,
                     "the same prompt, still there: no second alert")
        precondition(s.observe(stopVisible: true, permissionVisible: true, appFrontmost: false, now: at(6)).isEmpty)
        // Answered (elsewhere, by the user), then a second permission comes.
        precondition(s.observe(stopVisible: true, permissionVisible: false, appFrontmost: false, now: at(8)).isEmpty)
        precondition(s.observe(stopVisible: true, permissionVisible: true, appFrontmost: false, now: at(10))
                     == [.permissionRequested], "a new appearance alerts again")
    }

    static func aPermissionSeenInFrontNeverAlerts() {
        var s = ClaudeAppWatchState()
        precondition(s.observe(stopVisible: true, permissionVisible: true, appFrontmost: true, now: at(0)).isEmpty)
        // The user goes to another app with the prompt still there: they saw it.
        precondition(s.observe(stopVisible: true, permissionVisible: true, appFrontmost: false, now: at(1)).isEmpty)
        precondition(s.observe(stopVisible: true, permissionVisible: true, appFrontmost: false, now: at(3)).isEmpty)
    }

    // A stop button that leaves while a permission prompt shows: Claude waits, it has not finished.
    static func aStopThatGivesWayToAPermissionIsNoFinishedAnswer() {
        var s = ClaudeAppWatchState()
        precondition(s.observe(stopVisible: true, permissionVisible: false, appFrontmost: false, now: at(0)).isEmpty)
        precondition(s.observe(stopVisible: false, permissionVisible: true, appFrontmost: false, now: at(2))
                     == [.permissionRequested], "the permission, not « fini de répondre »")
        precondition(s.observe(stopVisible: false, permissionVisible: true, appFrontmost: false, now: at(4)).isEmpty)
    }

    // Ruling 5: a session of the Code tab runs inside the Claude app, so its stop and permission
    // buttons show there too while its hooks already report it. Within 15 s of such a hook, the event
    // is consumed: no alert now, and none later for the same appearance.
    static func anEventKeptQuietByACodeHookIsConsumed() {
        var s = ClaudeAppWatchState()
        precondition(s.observe(stopVisible: true, permissionVisible: false, appFrontmost: false, now: at(0),
                               lastCodeHookAt: at(-1)).isEmpty)
        precondition(s.observe(stopVisible: true, permissionVisible: true, appFrontmost: false, now: at(20),
                               lastCodeHookAt: at(6)).isEmpty, "a Code tab permission, its hook 14 s ago")
        precondition(s.observe(stopVisible: true, permissionVisible: true, appFrontmost: false, now: at(40),
                               lastCodeHookAt: at(6)).isEmpty, "consumed: no alert later for the same prompt")
        precondition(s.observe(stopVisible: false, permissionVisible: false, appFrontmost: false, now: at(60),
                               lastCodeHookAt: at(45)).isEmpty, "a Code tab Stop, its hook 15 s ago")
        precondition(!s.needsPolling)
        precondition(s.observe(stopVisible: false, permissionVisible: false, appFrontmost: false, now: at(90),
                               lastCodeHookAt: at(45)).isEmpty, "consumed: nothing later")

        // The same reads without a recent hook alert (16 s is too old).
        var t = ClaudeAppWatchState()
        precondition(t.observe(stopVisible: true, permissionVisible: false, appFrontmost: false, now: at(0),
                               lastCodeHookAt: at(-16)).isEmpty)
        precondition(t.observe(stopVisible: true, permissionVisible: true, appFrontmost: false, now: at(22),
                               lastCodeHookAt: at(6)) == [.permissionRequested])
        precondition(t.observe(stopVisible: false, permissionVisible: false, appFrontmost: false, now: at(61),
                               lastCodeHookAt: at(45)) == [.answerFinished])
    }

    static func pollingOnlyInFrontOrDuringAnAnswer() {
        var s = ClaudeAppWatchState()
        precondition(!s.needsPolling, "nothing seen yet: no reading")
        _ = s.observe(stopVisible: false, permissionVisible: false, appFrontmost: true, now: at(0))
        precondition(s.needsPolling)
        _ = s.observe(stopVisible: false, permissionVisible: false, appFrontmost: false, now: at(1))
        precondition(!s.needsPolling)
        _ = s.observe(stopVisible: false, permissionVisible: true, appFrontmost: false, now: at(2))
        precondition(!s.needsPolling, "a permission alone is no answer under way")
        _ = s.observe(stopVisible: true, permissionVisible: false, appFrontmost: false, now: at(3))
        precondition(s.needsPolling)
    }

    static func aResetForgetsEverything() {
        var s = ClaudeAppWatchState()
        _ = s.observe(stopVisible: true, permissionVisible: true, appFrontmost: true, now: at(0))
        s.reset()
        precondition(!s.needsPolling, "the Claude app quit: nothing to read")
        precondition(s == ClaudeAppWatchState())
        // Relaunched: the stop button of the old answer is forgotten, its absence is no finish.
        precondition(s.observe(stopVisible: false, permissionVisible: false, appFrontmost: false, now: at(5)).isEmpty)
    }

    // MARK: - The alert, the permission prompt, the test launch

    static func theAlertLineIsTheConversationTitleWhenReadable() {
        precondition(ClaudeAppWatchRules.conversationTitle(windowTitle: "Plan de la semaine") == "Plan de la semaine")
        precondition(ClaudeAppWatchRules.conversationTitle(windowTitle: "  Plan de la semaine \n") == "Plan de la semaine")
        for title in [nil, "", "   ", "Claude", "claude", " CLAUDE "] as [String?] {
            precondition(ClaudeAppWatchRules.conversationTitle(windowTitle: title) == nil,
                         "« \(title ?? "nil") » says nothing more than « Dans l'app Claude »")
        }
    }

    static func theAccessibilityPromptShowsOnceEverOnItsOwn() {
        precondition(ClaudeAppWatchRules.promptsForAccess(trusted: false, alreadyPrompted: false))
        precondition(!ClaudeAppWatchRules.promptsForAccess(trusted: false, alreadyPrompted: true),
                     "afterwards only from Settings")
        precondition(!ClaudeAppWatchRules.promptsForAccess(trusted: true, alreadyPrompted: false))
        precondition(!ClaudeAppWatchRules.promptsForAccess(trusted: true, alreadyPrompted: true))
    }

    static func aTestLaunchNeverWatches() {
        precondition(ClaudeAppWatchRules.isTestLaunch(environment: ["KLAYER_ISLAND_TEST": "1"]))
        precondition(!ClaudeAppWatchRules.isTestLaunch(environment: [:]))
        precondition(!ClaudeAppWatchRules.isTestLaunch(environment: ["KLAYER_ISLAND_TEST": "0"]))
        precondition(!ClaudeAppWatchRules.isTestLaunch(environment: ["KLAYER_ISLAND_TEST": ""]))
    }

    // MARK: - The diagnostic

    static func snapshot(_ buttons: [AXNodeSummary], title: String? = nil) -> ClaudeAppSnapshot {
        ClaudeAppSnapshot(trusted: true, complete: true, buttons: buttons, nodesRead: 812, windows: 1,
                          truncated: false, windowTitle: title, milliseconds: 42)
    }

    static func theDiagnosticListsUniqueButtonLines() {
        let text = ClaudeAppWatchRules.diagnostic(appVersion: "1.2.3", running: true, trusted: true, snapshot: snapshot([
            button("Stop response"), button("Copy"), button("Copy"), AXNodeSummary(role: "AXPopUpButton", label: "Model"),
            button(""), button(""), button("Line one\nline two"),
        ]))
        let lines = text.components(separatedBy: "\n")
        precondition(text.contains("1.2.3"), "the Claude app version")
        precondition(lines.contains("Accès Accessibilité : oui"))
        precondition(lines.contains("AXButton | Stop response"))
        precondition(lines.filter { $0 == "AXButton | Copy" }.count == 1, "each line once")
        precondition(lines.contains("AXPopUpButton | Model"))
        precondition(lines.filter { $0 == "AXButton | (sans libellé)" }.count == 1)
        precondition(lines.contains("AXButton | Line one line two"), "one line per button")
        precondition(lines.contains("Bouton d'arrêt reconnu : oui, autorisation reconnue : non"))
        precondition(text.contains("812"), "the counts")
    }

    static func theDiagnosticTruncatesLabelsAndLines() {
        let long = String(repeating: "a", count: 80)
        var buttons = [button(long)]
        for i in 0..<400 { buttons.append(button("Button \(i)")) }
        let text = ClaudeAppWatchRules.diagnostic(appVersion: "1.2.3", running: true, trusted: true,
                                                  snapshot: snapshot(buttons))
        let rows = ClaudeAppWatchRules.diagnosticLines(buttons)
        precondition(rows.count == 300, "at most 300 lines")
        precondition(rows[0] == "AXButton | " + String(repeating: "a", count: 60), "labels cut at 60 characters")
        precondition(text.contains("AXButton | Button 298"))
        precondition(!text.contains("AXButton | Button 299"), "the 301st line is left out")
        precondition(text.contains("300 sur 401"), "the diagnostic says lines were left out")
    }

    static func theDiagnosticNeverHoldsTheWindowTitle() {
        let text = ClaudeAppWatchRules.diagnostic(appVersion: nil, running: true, trusted: true,
                                                  snapshot: snapshot([button("Allow")], title: "Mon projet secret"))
        precondition(!text.contains("Mon projet secret"))
    }

    static func theDiagnosticTellsWhenNothingCanBeRead() {
        let off = ClaudeAppWatchRules.diagnostic(appVersion: nil, running: false, trusted: true, snapshot: nil)
        precondition(off.contains("non lancée"))
        let denied = ClaudeAppWatchRules.diagnostic(appVersion: "1.2.3", running: true, trusted: false, snapshot: nil)
        precondition(denied.components(separatedBy: "\n").contains("Accès Accessibilité : non"))
        precondition(!denied.contains(" | "), "no button line without access")
    }
}
