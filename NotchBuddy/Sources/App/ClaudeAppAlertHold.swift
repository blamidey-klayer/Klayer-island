import Foundation

// MARK: - What the busy island could not show (lot 6, final fix wave; 0.3.6)
//
// `AppState.showClaudeAppAlert` (a notification of the Code tab, or the Chat and Cowork watch) opens
// the note view only when `FinishPresentation` allows it, and so does the end of a session (its
// finished or error view, HookServer). When the island is busy (a card waits, the chat or a mail
// draft is open, the drop views, Settings in the island, or it is pinned), what it could not show is
// held: one item per session (the Chat and Cowork watch has one slot of its own), 5 at most, newest
// first. A Claude app alert, and since 0.3.6 the end of any Claude Code session (VS Code, a terminal,
// the Claude app), whatever its app. An alert that asks something, or a finish that was not seen
// (less than 2 s on screen, the pointer never on the island), goes back into the hold when a newer
// one takes its place on screen. Once the island frees (a request left with nothing else waiting, a
// note ended, the island opens on its default view, the house tab is clicked, or the view of a held
// item, or a view the user was busy in, folded), the held items show one after the other, each as its
// own note or finished view. An item goes when its session moves on (closing it only drops what it
// asked, never its end), when the Claude app comes in front (the Claude app's own items only: Code
// tab sessions, Chat and Cowork), and after 30 min.
//
// The house tab of the island's header carries a badge while an item is held (with their number from
// 2 on), or while the Claude app pill got a finish or an error the user has not seen: the strongest.
// The pill's own badge is drawn nowhere since the home lost its Claude pills; it clears from the tab
// when the home's list is on screen.
//
// Foundation only, tested by scripts/test-code-notification.sh. No timer: the 30 min are compared
// when the island would show its home or draws the tab (AppState wakes up once at the next expiry).

/// What the note view says when the app asks something of the user, or a Chat answer finished: a
/// title and one line. `source`: a Code tab session or Chat and Cowork, for its icon and its button
/// (« Ouvrir cette session », « Ouvrir ce chat »). `sound`: `approval`, `question` or `finish`, the
/// colour of its icon. `sessionId`: the Code tab session it is about, nil for the Chat and Cowork
/// watch: two alerts with the same text for two sessions are two alerts (0.3.6, M4).
struct ClaudeAppAlert: Equatable, Sendable {
    var title: String
    var message: String
    var source: ClaudeAppNoteSource = .chat
    var sound: String = "question"
    var sessionId: String? = nil
}

/// What the busy island could not show, kept for when it frees: a Claude app alert (its title, line
/// and sound), or the end of a session (`finished`, the row its finished or error view tells about).
struct HeldClaudeAppAlert: Equatable, Sendable {
    var title: String
    var message: String
    /// `approval` (a permission), `question` (Claude waits), `finish` (a finished answer or session)
    /// or `error` (a session that failed).
    var sound: String
    /// When it was held: past `ClaudeAppAlertHold.lifetime` it says nothing current.
    var heldAt: Date
    /// The session the item is about; nil for the Chat and Cowork watch, whose alerts come only with
    /// the Claude app behind (its activation drops them).
    var sessionId: String? = nil
    /// The end of a session: the row its finished view (or error view, `sound` "error") tells about.
    /// Nil for a note.
    var finished: SessionRow? = nil

    /// The end of session `row`, finished or failed, held at `date`.
    static func finish(_ row: SessionRow, failed: Bool, at date: Date) -> HeldClaudeAppAlert {
        HeldClaudeAppAlert(title: failed ? "Erreur" : "Terminé", message: row.title,
                           sound: failed ? "error" : "finish", heldAt: date, sessionId: row.id, finished: row)
    }

    /// The mark of the house tab: finished for a finish, error for a failure, approval for anything asked.
    var badge: PillBadge {
        switch sound {
        case "finish": return .finished
        case "error":  return .error
        default:       return .approval
        }
    }

    /// A permission, or Claude waiting for the user: it goes back into the hold whenever a newer view
    /// takes its place, seen or not (the user still has to answer).
    var asksSomething: Bool { sound == "approval" || sound == "question" }

    /// The Claude app's own: a Code tab session's alert or end, or the Chat and Cowork watch's alert.
    /// The Claude app coming in front drops them; an end of a VS Code or terminal session stays.
    var fromClaudeApp: Bool {
        guard let finished else { return true }
        return finished.pillId == HookRouting.desktopPillId
    }
}

/// The items the busy island could not show, the Claude app pill's finish or error not seen yet, and
/// what the island does with them.
struct ClaudeAppAlertHold: Equatable, Sendable {
    /// How long a held item waits to be shown: 30 min.
    static let lifetime: TimeInterval = 30 * 60
    /// Items held at most; the oldest goes first.
    static let limit = 5
    /// How long a finish must stay on screen to count as seen, unless the pointer was on the island.
    static let seenAfter: TimeInterval = 2

    /// The items waiting, newest first, one per session (one for the Chat and Cowork watch).
    private(set) var items: [HeldClaudeAppAlert] = []
    /// The strongest finish or error badge the Claude app pill got since the home's list was last on
    /// screen. A request's mark is not kept here: the house tab reads the pending requests themselves,
    /// so a request that shows or leaves never clears the marks of the other sessions (0.3.6, I7).
    /// Only the home's list on screen and the Claude app in front clear it.
    private(set) var unseenBadge: PillBadge? = nil

    init() {}

    /// The item that shows next: the newest.
    var held: HeldClaudeAppAlert? { items.first }

    /// The item of session `sessionId` (nil: the Chat and Cowork watch's), nil when none is held.
    func item(of sessionId: String?) -> HeldClaudeAppAlert? {
        items.first { $0.sessionId == sessionId }
    }

    /// Whether the end of session `sessionId` is held: its idle prompt (about 60 s later) adds nothing.
    func holdsFinish(of sessionId: String) -> Bool {
        item(of: sessionId)?.finished != nil
    }

    /// An alert went through `FinishPresentation`. Blocked (`.badgeOnly`): it is held, in place of any
    /// older item of its session. Shown (`.open`): the note on screen is its session's newest, its
    /// older held item goes; the other sessions' items stay held (0.3.6, C5).
    mutating func alertCame(_ alert: HeldClaudeAppAlert, presentation: FinishPresentation) {
        if presentation == .badgeOnly {
            hold(alert)
        } else {
            items.removeAll { $0.sessionId == alert.sessionId }
        }
    }

    /// Holds `item`, newest first, in place of its session's older one; past 5, the oldest goes.
    mutating func hold(_ item: HeldClaudeAppAlert) {
        items.removeAll { $0.sessionId == item.sessionId }
        items.insert(item, at: 0)
        if items.count > Self.limit { items.removeLast(items.count - Self.limit) }
    }

    /// The Claude app pill was badged with a finish or an error the island could not show. A request's
    /// badge is not kept: the house tab reads the pending requests live.
    mutating func pillBadged(_ badge: PillBadge) {
        guard badge != .approval else { return }
        unseenBadge = Self.strongest(unseenBadge, badge)
    }

    /// The home's list is on screen: its rows tell what the pill's badge said. Held items stay.
    mutating func homeListShown() {
        unseenBadge = nil
    }

    /// A hook event of session `sessionId` other than a notification (a tool ran, a prompt, an end, a
    /// new request): what its held item said was answered or seen, or is asked again by its own card.
    /// Its held item goes, and its mark on the house tab.
    mutating func sessionMovedOn(_ sessionId: String) {
        items.removeAll { $0.sessionId == sessionId }
    }

    /// Session `sessionId` closed (SessionEnd): what it asked is moot and goes; its end stays held,
    /// since closing a session right after its end (a burst of SessionEnd) says nobody saw it.
    mutating func sessionEnded(_ sessionId: String) {
        items.removeAll { $0.sessionId == sessionId && $0.finished == nil }
    }

    /// Drops the items past 30 min. Returns true when it dropped one.
    @discardableResult
    mutating func dropExpired(now: Date) -> Bool {
        let before = items.count
        items.removeAll { Self.expired($0, now: now) }
        return items.count != before
    }

    /// When the next item reaches its 30 min, nil when nothing is held.
    var nextExpiry: Date? {
        items.map(\.heldAt).min().map { $0.addingTimeInterval(Self.lifetime) }
    }

    /// The Claude app came in front: the user is there, what it had to say is seen. Its own items go
    /// (Code tab sessions, Chat and Cowork), and its pill's unseen mark; the end of a VS Code or
    /// terminal session stays.
    mutating func claudeAppCameToFront() {
        items.removeAll { $0.fromClaudeApp }
        unseenBadge = nil
    }

    /// The island is about to show its home. `presentation`: `FinishPresentation.decide` for that
    /// home, the same rule as when the item came. Returns the item to show in its place (the newest,
    /// no longer held), nil for the home. Items past 30 min are dropped first; a home the item may not
    /// be shown over (pinned) keeps it held for the next time.
    mutating func takeForHome(presentation: FinishPresentation, now: Date) -> HeldClaudeAppAlert? {
        dropExpired(now: now)
        guard presentation == .open, !items.isEmpty else { return nil }
        return items.removeFirst()
    }

    /// How many items wait (none past 30 min): the house tab writes it from 2 on.
    func count(now: Date) -> Int {
        items.filter { !Self.expired($0, now: now) }.count
    }

    /// The badge of the house tab, nil for none: the held items' strongest (none past 30 min), the
    /// unseen pill badge, and a request waiting off screen.
    /// `requestWaitsOffScreen` (Task 27): a permission or a question waits and its card is not on
    /// screen (it stepped aside when its session's app came to the front, or the chat is open over
    /// it): the house tab carries the request's mark too, whatever app the session runs in.
    func houseBadge(now: Date, requestWaitsOffScreen: Bool = false) -> PillBadge? {
        var badge = unseenBadge
        for item in items where !Self.expired(item, now: now) { badge = Self.strongest(badge, item.badge) }
        return Self.strongest(badge, requestWaitsOffScreen ? .approval : nil)
    }

    /// Whether a permission (`approval`) or a question (`question`) waits while the island's view
    /// (`view`, the raw value of `IslandView`) is not its card.
    static func requestWaitsOffScreen(approval: Bool, question: Bool, view: String) -> Bool {
        (approval && view != "approval") || (question && view != "question")
    }

    // MARK: - A view replaced on screen (0.3.6, C5 and I6)

    /// Whether a finish shown on screen counts as seen: on screen 2 s at least (`shownFor`), or the
    /// pointer was on the island meanwhile.
    static func finishSeen(shownFor: TimeInterval, pointerWasOn: Bool) -> Bool {
        pointerWasOn || shownFor >= seenAfter
    }

    /// The item on screen (`onScreen`, a note of the Claude app or the finished or error view of a
    /// session) when the app puts another view in its place, for session `replacedBy` (nil: the Chat and
    /// Cowork watch, or a request with no session): what goes back into the hold, nil for nothing. A
    /// newer item of the same session tells it instead. An alert that asks something always goes back;
    /// a finish only when it was not seen (`finishSeen`). A view the user replaced himself (a click, a
    /// tab) is not asked about.
    static func backToHold(_ onScreen: HeldClaudeAppAlert?, replacedBy sessionId: String?,
                           shownFor: TimeInterval, pointerWasOn: Bool) -> HeldClaudeAppAlert? {
        guard let onScreen, onScreen.sessionId != sessionId else { return nil }
        if onScreen.asksSomething { return onScreen }
        return finishSeen(shownFor: shownFor, pointerWasOn: pointerWasOn) ? nil : onScreen
    }

    /// Whether the island folding from view `view` (the raw value of `IslandView`) frees it for the
    /// next held item: the note or the finished or error view it was showing, or a view the user was
    /// busy in (the chat, a mail, the drop views, Settings). Not the home, which showed the held items
    /// already, nor a card that stepped aside (its request waits, or was handed back to its app).
    static func foldShowsNext(fromView view: String) -> Bool {
        ["note", "finished", "error", "prompt", "mail", "upload", "uploading", "choose", "settings"].contains(view)
    }

    /// One badge for two: a request first, then an error, then a finish.
    static func strongest(_ a: PillBadge?, _ b: PillBadge?) -> PillBadge? {
        func rank(_ badge: PillBadge?) -> Int {
            switch badge {
            case .approval: return 3
            case .error:    return 2
            case .finished: return 1
            case nil:       return 0
            }
        }
        return rank(b) > rank(a) ? b : a
    }

    private static func expired(_ item: HeldClaudeAppAlert, now: Date) -> Bool {
        now.timeIntervalSince(item.heldAt) > lifetime
    }
}
