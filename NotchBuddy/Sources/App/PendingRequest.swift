import Foundation

/// A Claude request waiting for the user (spec §4): a permission or a question. While one is
/// pending the island is held open: no timer and no pointer leave folds it, a click outside or
/// Escape only folds it to compact (Klay keeps its badge) and hovering reopens it on the
/// request. The request leaves only when it is answered, sent to the terminal, or when its
/// hook connection closes or times out.
/// Foundation only, tested by scripts/test-pending-request.sh.
enum PendingRequest: Equatable {
    case approval
    case question

    /// The request the island shows: the permission first, then the question.
    static func first(approval: Bool, question: Bool) -> PendingRequest? {
        if approval { return .approval }
        if question { return .question }
        return nil
    }

    /// Whether a click outside (or Escape) acts on the open island. Only an island the user
    /// pinned (⌘P) with no request pending stays open; a pending request (which HookServer
    /// also pins) folds it to compact.
    static func outsideClickActs(pinned: Bool, requestPending: Bool) -> Bool {
        !pinned || requestPending
    }
}
