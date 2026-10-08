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
}
