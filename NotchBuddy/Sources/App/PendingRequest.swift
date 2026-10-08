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

/// One token per request the island holds, a permission and a question at most. A timer or a
/// closed connection acts only on the request it was set up for: it compares its token with the
/// current one. The file descriptor cannot tell them apart, since the next connection very often
/// gets the number of the one that just closed.
struct RequestTokens {
    private var last = 0
    private var held: [PendingRequest: Int] = [:]

    /// A new request of this kind is held (it may replace an older one): its token, never given before.
    mutating func hold(_ kind: PendingRequest) -> Int {
        last += 1
        held[kind] = last
        return last
    }

    /// The request of this kind left: answered, handed back, handled elsewhere or timed out.
    mutating func release(_ kind: PendingRequest) {
        held[kind] = nil
    }

    /// The token of the request of this kind still held, nil when there is none.
    func current(_ kind: PendingRequest) -> Int? {
        held[kind]
    }

    /// True while `token` is the request of this kind still held.
    func isCurrent(_ token: Int, _ kind: PendingRequest) -> Bool {
        held[kind] == token
    }
}
