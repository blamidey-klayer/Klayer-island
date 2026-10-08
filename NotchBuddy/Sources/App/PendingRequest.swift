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

    // MARK: - After a request leaves (spec §1: no request stays unseen)

    /// What the island shows once a request left: answered from its card, handed back to its
    /// window, handled there, or timed out.
    enum AfterRequest: Equatable {
        /// The card of the other request is on screen: it stays as it is, nothing moves under
        /// the pointer.
        case keepView
        /// The note « Handled in … » or « Still waiting in … », then `noteEnd` decides.
        case note
        /// The other request, waiting behind the one that left.
        case show(PendingRequest)
        /// The home.
        case home
    }

    /// `leaving`: the request that left. `onScreen`: the request card the open island shows (nil
    /// when it is folded or shows another view). `note`: the request left with a note.
    /// `approval`, `question`: what is still pending once it left. The other request comes first,
    /// before the home, and never under a note when the other card is the one on screen.
    static func after(leaving: PendingRequest, onScreen: PendingRequest?, note: Bool,
                      approval: Bool, question: Bool) -> AfterRequest {
        if let onScreen, onScreen != leaving { return .keepView }
        if note { return .note }
        if let next = first(approval: approval, question: question) { return .show(next) }
        return .home
    }

    /// What the 3 s timer of a note does.
    enum NoteEnd: Equatable {
        /// The note is no longer on screen (another note, a request or a finished view took its
        /// place): whatever is there stays.
        case nothing
        /// A request waits: its card replaces the note, the island stays open.
        case show(PendingRequest)
        /// Nothing waits: the island folds.
        case fold
    }

    /// `noteStillOnScreen`: this very note is still the view (each note has its own token, so an
    /// earlier note's timer never ends a later one).
    static func noteEnd(noteStillOnScreen: Bool, approval: Bool, question: Bool) -> NoteEnd {
        guard noteStillOnScreen else { return .nothing }
        if let next = first(approval: approval, question: question) { return .show(next) }
        return .fold
    }

    // MARK: - A card never changes under the pointer (CLAUDE.md: an explicit click)

    /// Whether a request that just arrived takes the screen. `onScreen`: the request card the
    /// open island shows, nil when it shows none. A card is never swapped for a request of the
    /// other kind, which waits (badge and sound) until the first is answered. A newer request of
    /// the same kind replaces the older one, which goes back to its own window.
    static func arrivalTakesScreen(_ incoming: PendingRequest, onScreen: PendingRequest?) -> Bool {
        guard let onScreen else { return true }
        return onScreen == incoming
    }

    /// How long the buttons of a permission or question card stay disabled and dimmed after the
    /// request on screen changed (a new request, another card, the island opening on it): a click
    /// aimed at what was there before never answers the request that took its place.
    static let armingDelay: TimeInterval = 0.6
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

/// What the user chose so far on a question card: the question on screen (several are asked one
/// after the other), the chosen labels, the « Other… » texts and which of them is open. The
/// card's view is rebuilt each time the island opens, so the draft is kept outside it, for the
/// request it belongs to: folding the island and reopening it keeps a partial answer, and only a
/// new request starts blank.
struct QuestionDraft: Equatable {
    let requestId: Int
    var index: Int
    var selections: [[String]]
    var otherTexts: [String]
    var showOther: [Bool]
}

extension QuestionDraft {
    /// A blank draft for request `requestId`, which asks `count` questions.
    init(requestId: Int, count: Int) {
        let n = max(0, count)
        self.init(requestId: requestId, index: 0,
                  selections: Array(repeating: [], count: n),
                  otherTexts: Array(repeating: "", count: n),
                  showOther: Array(repeating: false, count: n))
    }

    /// The draft to show for request `requestId` of `count` questions: `saved` when it belongs to
    /// that request and fits it, else a blank one.
    static func resuming(_ saved: QuestionDraft?, requestId: Int, count: Int) -> QuestionDraft {
        guard let saved, saved.requestId == requestId,
              saved.selections.count == count, saved.otherTexts.count == count,
              saved.showOther.count == count, saved.index >= 0, saved.index < max(count, 1)
        else { return QuestionDraft(requestId: requestId, count: count) }
        return saved
    }
}
