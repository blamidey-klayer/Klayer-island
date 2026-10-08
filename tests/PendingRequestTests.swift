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
}
