import Foundation

/// A permission or a question from Claude waiting for the user (spec §4): both hold the
/// island open until answered, the island reopens on them (permission first), and a click
/// outside folds a held island instead of being ignored.
@main
enum PendingRequestTests {
    static func main() {
        let cases: [(String, () -> Void)] = [
            ("nothing_pending", nothingPending),
            ("a_question_is_pending_like_a_permission", aQuestionIsPendingLikeAPermission),
            ("the_permission_shows_first", thePermissionShowsFirst),
            ("a_click_outside_acts_unless_pinned_with_nothing_pending", aClickOutsideActsUnlessPinnedWithNothingPending),
            ("a_stale_timer_never_matches_the_next_request", aStaleTimerNeverMatchesTheNextRequest),
            ("a_displaced_request_is_no_longer_current", aDisplacedRequestIsNoLongerCurrent),
            ("tokens_of_each_kind_are_independent", tokensOfEachKindAreIndependent),
            ("after_a_request_the_other_one_shows_first", afterARequestTheOtherOneShowsFirst),
            ("after_the_last_request_the_home_shows", afterTheLastRequestTheHomeShows),
            ("a_note_shows_when_the_request_had_one", aNoteShowsWhenTheRequestHadOne),
            ("a_card_on_screen_is_never_replaced_when_the_other_request_leaves", aCardOnScreenIsNeverReplacedWhenTheOtherRequestLeaves),
            ("the_end_of_a_note_shows_the_waiting_request_instead_of_folding", theEndOfANoteShowsTheWaitingRequestInsteadOfFolding),
            ("an_earlier_note_never_ends_a_later_one", anEarlierNoteNeverEndsALaterOne),
            ("a_request_of_the_other_kind_waits_behind_a_card", aRequestOfTheOtherKindWaitsBehindACard),
            ("a_newer_request_of_the_same_kind_takes_the_card", aNewerRequestOfTheSameKindTakesTheCard),
            ("buttons_arm_after_0_6_s", buttonsArmAfter06s),
        ]
        for (name, run) in cases {
            run()
            print("  ok  \(name)")
        }
        print("Pending request: \(cases.count) cases passed")
    }

    static func nothingPending() {
        precondition(PendingRequest.first(approval: false, question: false) == nil)
    }

    static func aQuestionIsPendingLikeAPermission() {
        precondition(PendingRequest.first(approval: false, question: true) == .question,
                     "a pending question must hold the island like a permission")
        precondition(PendingRequest.first(approval: true, question: false) == .approval)
    }

    static func thePermissionShowsFirst() {
        precondition(PendingRequest.first(approval: true, question: true) == .approval,
                     "with both pending, the island reopens on the permission")
    }

    static func aClickOutsideActsUnlessPinnedWithNothingPending() {
        precondition(PendingRequest.outsideClickActs(pinned: false, requestPending: false))
        precondition(PendingRequest.outsideClickActs(pinned: true, requestPending: true),
                     "a pending request (pinned by HookServer) folds to compact, it is not ignored")
        precondition(PendingRequest.outsideClickActs(pinned: false, requestPending: true))
        precondition(!PendingRequest.outsideClickActs(pinned: true, requestPending: false),
                     "an island pinned with ⌘P stays open")
    }

    // MARK: - One token per held request (I5)

    static func aStaleTimerNeverMatchesTheNextRequest() {
        // The 115 s timeout of an answered request must not dismiss the next one, even when the
        // next connection gets the same file descriptor number (Darwin reuses the lowest free one).
        var tokens = RequestTokens()
        let first = tokens.hold(.approval)
        precondition(tokens.isCurrent(first, .approval))
        tokens.release(.approval)                        // answered
        precondition(!tokens.isCurrent(first, .approval), "an answered request is no longer current")
        let second = tokens.hold(.approval)              // same fd number, new request
        precondition(second != first, "each held request gets its own token")
        precondition(!tokens.isCurrent(first, .approval), "the stale timer of the first must not match the second")
        precondition(tokens.isCurrent(second, .approval))
    }

    static func aDisplacedRequestIsNoLongerCurrent() {
        var tokens = RequestTokens()
        let older = tokens.hold(.question)
        let newer = tokens.hold(.question)               // a newer question displaces the older one
        precondition(!tokens.isCurrent(older, .question), "the displaced request's timer and source do nothing")
        precondition(tokens.isCurrent(newer, .question))
        precondition(tokens.current(.question) == newer)
    }

    static func tokensOfEachKindAreIndependent() {
        var tokens = RequestTokens()
        let approval = tokens.hold(.approval)
        let question = tokens.hold(.question)
        precondition(approval != question, "tokens are never shared across kinds")
        tokens.release(.approval)
        precondition(tokens.current(.approval) == nil)
        precondition(tokens.isCurrent(question, .question), "releasing a permission leaves the question held")
        precondition(!tokens.isCurrent(question, .approval), "a question token never matches a permission")
    }

    // MARK: - What the island shows after a request leaves (I2)

    static func afterARequestTheOtherOneShowsFirst() {
        // A permission answered from its card while a question waits: the question shows,
        // it is not hidden behind the home (spec §1, no request unseen).
        precondition(PendingRequest.after(leaving: .approval, onScreen: .approval, note: false,
                                          approval: false, question: true) == .show(.question))
        precondition(PendingRequest.after(leaving: .question, onScreen: .question, note: false,
                                          approval: true, question: false) == .show(.approval))
        // A question that timed out while the island was folded: the permission is next.
        precondition(PendingRequest.after(leaving: .question, onScreen: nil, note: false,
                                          approval: true, question: false) == .show(.approval))
    }

    static func afterTheLastRequestTheHomeShows() {
        precondition(PendingRequest.after(leaving: .approval, onScreen: .approval, note: false,
                                          approval: false, question: false) == .home)
        precondition(PendingRequest.after(leaving: .question, onScreen: .question, note: false,
                                          approval: false, question: false) == .home)
    }

    static func aNoteShowsWhenTheRequestHadOne() {
        // Handled in the terminal, or still waiting there after the timeout: the note first,
        // whatever waits (its end decides, see noteEnd).
        precondition(PendingRequest.after(leaving: .approval, onScreen: .approval, note: true,
                                          approval: false, question: true) == .note)
        precondition(PendingRequest.after(leaving: .approval, onScreen: nil, note: true,
                                          approval: false, question: false) == .note)
    }

    static func aCardOnScreenIsNeverReplacedWhenTheOtherRequestLeaves() {
        // The question card is on screen; the permission waiting behind it is handled in the
        // terminal. Nothing moves under the pointer: no note over the question.
        precondition(PendingRequest.after(leaving: .approval, onScreen: .question, note: true,
                                          approval: false, question: true) == .keepView)
        precondition(PendingRequest.after(leaving: .question, onScreen: .approval, note: false,
                                          approval: true, question: false) == .keepView)
    }

    static func theEndOfANoteShowsTheWaitingRequestInsteadOfFolding() {
        // Before: the note posted a collapse the held island refused, and stayed forever over the
        // waiting question.
        precondition(PendingRequest.noteEnd(noteStillOnScreen: true, approval: false, question: true)
                     == .show(.question))
        precondition(PendingRequest.noteEnd(noteStillOnScreen: true, approval: true, question: true)
                     == .show(.approval), "the permission first")
        precondition(PendingRequest.noteEnd(noteStillOnScreen: true, approval: false, question: false) == .fold)
    }

    static func anEarlierNoteNeverEndsALaterOne() {
        // The 3 s timer of an earlier note finds a later note (or a request, or a finished view)
        // on screen: it does nothing, the later one has its own timer.
        precondition(PendingRequest.noteEnd(noteStillOnScreen: false, approval: false, question: false) == .nothing)
        precondition(PendingRequest.noteEnd(noteStillOnScreen: false, approval: true, question: false) == .nothing)
    }

    // MARK: - A card never changes under the pointer (I3)

    static func aRequestOfTheOtherKindWaitsBehindACard() {
        precondition(!PendingRequest.arrivalTakesScreen(.question, onScreen: .approval),
                     "a question never replaces a visible permission card: badge and sound only")
        precondition(!PendingRequest.arrivalTakesScreen(.approval, onScreen: .question),
                     "a permission never replaces a visible question card")
        precondition(PendingRequest.arrivalTakesScreen(.question, onScreen: nil),
                     "no card on screen (folded, home, chat): the request opens the island on it")
        precondition(PendingRequest.arrivalTakesScreen(.approval, onScreen: nil))
    }

    static func aNewerRequestOfTheSameKindTakesTheCard() {
        // The older one goes back to its own window ("ask"); the buttons re-arm (armingDelay).
        precondition(PendingRequest.arrivalTakesScreen(.approval, onScreen: .approval))
        precondition(PendingRequest.arrivalTakesScreen(.question, onScreen: .question))
    }

    static func buttonsArmAfter06s() {
        precondition(PendingRequest.armingDelay == 0.6,
                     "the card's buttons wait 0.6 s after the request on screen changes")
    }
}
