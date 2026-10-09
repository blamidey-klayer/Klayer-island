import Foundation

/// The card steps aside when the session's app comes to the front (Task 27). Baptiste, 9 October
/// 2026: « Klayer Island doit me permettre de répondre à Claude, mais si je vais dans la session en
/// question je dois aussi pouvoir répondre, et la carte de l'île disparaît car je suis sur la bonne
/// conversation ». The island folds without answering: the request stays pending, hovering shows the
/// card again, answering in the app closes it as before. Only a change of app counts: an app that was
/// already in front when the card came does not fold it. The terminal does not change.
@main
enum CardStepAsideTests {
    static func main() {
        let cases: [(String, () -> Void)] = [
            ("the_host_coming_to_the_front_folds_the_card", theHostComingToTheFrontFoldsTheCard),
            ("another_app_coming_to_the_front_changes_nothing", anotherAppComingToTheFrontChangesNothing),
            ("a_host_already_in_front_when_the_card_came_does_not_fold_it", aHostAlreadyInFrontDoesNotFoldIt),
            ("leaving_the_host_then_coming_back_folds_it", leavingTheHostThenComingBackFoldsIt),
            ("no_card_or_no_host_never_folds", noCardOrNoHostNeverFolds),
            ("bundle_ids_ignore_case_and_spaces", bundleIdsIgnoreCaseAndSpaces),
            ("the_host_of_a_request", theHostOfARequest),
            ("a_new_card_starts_a_new_watch", aNewCardStartsANewWatch),
            ("the_same_card_keeps_its_watch", theSameCardKeepsItsWatch),
            ("reopening_on_the_card_in_the_host_keeps_it", reopeningOnTheCardInTheHostKeepsIt),
            ("nothing_on_screen_watches_nothing", nothingOnScreenWatchesNothing),
            ("a_note_of_the_claude_app_folds_too", aNoteOfTheClaudeAppFoldsToo),
        ]
        for (name, run) in cases {
            run()
            print("  ok  \(name)")
        }
        print("Card step aside: \(cases.count) cases passed")
    }

    static let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    static let claudeApp = HookRouting.desktopBundleId
    static let vsCode = "com.microsoft.VSCode"

    static func theHostComingToTheFrontFoldsTheCard() {
        precondition(CardStepAside.shouldStepAside(hostBundleId: vsCode, activatedBundleId: vsCode,
                                                   cardShownAt: t0, hostWasFrontAtShow: false),
                     "VS Code comes to the front after its card showed")
        precondition(CardStepAside.shouldStepAside(hostBundleId: claudeApp, activatedBundleId: claudeApp,
                                                   cardShownAt: t0, hostWasFrontAtShow: false),
                     "the Claude app comes to the front after its card showed")
    }

    static func anotherAppComingToTheFrontChangesNothing() {
        precondition(!CardStepAside.shouldStepAside(hostBundleId: vsCode, activatedBundleId: "com.apple.Safari",
                                                    cardShownAt: t0, hostWasFrontAtShow: false), "another app")
        precondition(!CardStepAside.shouldStepAside(hostBundleId: vsCode, activatedBundleId: nil,
                                                    cardShownAt: t0, hostWasFrontAtShow: false), "an app without id")
    }

    static func aHostAlreadyInFrontDoesNotFoldIt() {
        precondition(!CardStepAside.shouldStepAside(hostBundleId: vsCode, activatedBundleId: vsCode,
                                                    cardShownAt: t0, hostWasFrontAtShow: true),
                     "VS Code was already in front when the card came: no change of app")
        var watch = StepAsideWatch(subject: .approval(requestId: 1), hostBundleId: vsCode, shownAt: t0,
                                   frontmostBundleId: vsCode)
        precondition(!watch.appActivated(vsCode), "an activation of the app already in front folds nothing")
    }

    static func leavingTheHostThenComingBackFoldsIt() {
        var watch = StepAsideWatch(subject: .approval(requestId: 1), hostBundleId: vsCode, shownAt: t0,
                                   frontmostBundleId: vsCode)
        precondition(!watch.appActivated("com.apple.Safari"), "the user goes elsewhere")
        precondition(watch.appActivated(vsCode), "then back to VS Code: a change of app, the card folds")
    }

    static func noCardOrNoHostNeverFolds() {
        precondition(!CardStepAside.shouldStepAside(hostBundleId: vsCode, activatedBundleId: vsCode,
                                                    cardShownAt: nil, hostWasFrontAtShow: false), "no card on screen")
        precondition(!CardStepAside.shouldStepAside(hostBundleId: nil, activatedBundleId: vsCode,
                                                    cardShownAt: t0, hostWasFrontAtShow: false), "no host known")
        precondition(!CardStepAside.shouldStepAside(hostBundleId: "  ", activatedBundleId: "  ",
                                                    cardShownAt: t0, hostWasFrontAtShow: false), "blank ids")
    }

    static func bundleIdsIgnoreCaseAndSpaces() {
        precondition(CardStepAside.shouldStepAside(hostBundleId: " com.microsoft.vscode\n", activatedBundleId: vsCode,
                                                   cardShownAt: t0, hostWasFrontAtShow: false), "same app")
        precondition(CardStepAside.sameApp("COM.ANTHROPIC.CLAUDEFORDESKTOP", claudeApp))
        precondition(!CardStepAside.sameApp(nil, nil) && !CardStepAside.sameApp("", ""), "no id is no app")
    }

    static func theHostOfARequest() {
        precondition(CardStepAside.requestHost(desktopSession: true, terminalSession: false, bundleId: "")
                     == claudeApp, "a Code tab session: the Claude app")
        precondition(CardStepAside.requestHost(desktopSession: true, terminalSession: false, bundleId: vsCode)
                     == claudeApp, "the Claude app whatever the bundle id says")
        precondition(CardStepAside.requestHost(desktopSession: false, terminalSession: false, bundleId: vsCode)
                     == vsCode, "an editor: the bundle id the relay forwards")
        precondition(CardStepAside.requestHost(desktopSession: false, terminalSession: false, bundleId: " ") == nil,
                     "no bundle id: no host")
        precondition(CardStepAside.requestHost(desktopSession: false, terminalSession: true,
                                               bundleId: "com.apple.Terminal") == nil,
                     "the terminal does not change: its card never steps aside")
    }

    static func aNewCardStartsANewWatch() {
        let first = StepAsideWatch.next(current: nil, onScreen: (.approval(requestId: 1), vsCode), now: t0,
                                        frontmostBundleId: "com.apple.Safari")
        precondition(first?.subject == .approval(requestId: 1) && first?.shownAt == t0 && first?.hostInFront == false,
                     "the card came: watched from now, VS Code not in front")
        let second = StepAsideWatch.next(current: first, onScreen: (.question(requestId: 2), claudeApp),
                                         now: t0.addingTimeInterval(5), frontmostBundleId: claudeApp)
        precondition(second?.subject == .question(requestId: 2) && second?.hostInFront == true
                     && second?.shownAt == t0.addingTimeInterval(5), "another card: a new watch, its host in front")
        let newer = StepAsideWatch.next(current: first, onScreen: (.approval(requestId: 3), vsCode),
                                        now: t0.addingTimeInterval(9), frontmostBundleId: vsCode)
        precondition(newer?.subject == .approval(requestId: 3) && newer?.hostInFront == true,
                     "a newer permission replaces the watch")
    }

    static func theSameCardKeepsItsWatch() {
        var watch = StepAsideWatch.next(current: nil, onScreen: (.approval(requestId: 1), vsCode), now: t0,
                                        frontmostBundleId: vsCode)!
        precondition(!watch.appActivated("com.apple.Safari"))
        // A redraw of the same card (the view or the mode set again) keeps what was seen.
        let kept = StepAsideWatch.next(current: watch, onScreen: (.approval(requestId: 1), vsCode),
                                       now: t0.addingTimeInterval(3), frontmostBundleId: vsCode)
        precondition(kept == watch, "same card: same watch, VS Code left behind since")
        watch = kept!
        precondition(watch.appActivated(vsCode), "and coming back to VS Code folds it")
    }

    static func reopeningOnTheCardInTheHostKeepsIt() {
        // The card stepped aside (the island folded: no watch), the user hovers the island from VS Code.
        let reopened = StepAsideWatch.next(current: nil, onScreen: (.approval(requestId: 1), vsCode),
                                           now: t0.addingTimeInterval(30), frontmostBundleId: vsCode)
        var watch = reopened!
        precondition(!watch.appActivated(vsCode), "« si je reviens d'abord sur l'île, la carte est toujours là »")
    }

    static func nothingOnScreenWatchesNothing() {
        let watch = StepAsideWatch(subject: .approval(requestId: 1), hostBundleId: vsCode, shownAt: t0,
                                   frontmostBundleId: nil)
        precondition(StepAsideWatch.next(current: watch, onScreen: nil, now: t0, frontmostBundleId: nil) == nil,
                     "the card left the screen (folded, answered): no watch")
    }

    static func aNoteOfTheClaudeAppFoldsToo() {
        let subject = StepAsideSubject.claudeAppNote(title: "Claude a fini de répondre", message: "Dans l'app Claude")
        precondition(!subject.isRequest && StepAsideSubject.approval(requestId: 1).isRequest
                     && StepAsideSubject.question(requestId: 1).isRequest, "a note is not a request")
        var watch = StepAsideWatch.next(current: nil, onScreen: (subject, claudeApp), now: t0,
                                        frontmostBundleId: "com.apple.mail")!
        precondition(watch.appActivated(claudeApp), "the Claude app comes to the front: the note folds")
    }
}
