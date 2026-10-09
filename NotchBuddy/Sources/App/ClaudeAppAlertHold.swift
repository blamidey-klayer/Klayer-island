import Foundation

// MARK: - A Claude app alert the busy island could not show (lot 6, final fix wave)
//
// `AppState.showClaudeAppAlert` (a notification of the Code tab, or the Chat and Cowork watch) opens
// the note view only when `FinishPresentation` allows it. When the island is busy (a card waits, the
// chat or a mail draft is open, the drop views, Settings in the island, or it is pinned), the alert
// is held, the latest one only, and shown through the same note view and the same rule the next time
// the island would show its home: a request left with nothing else waiting (HookServer.requestLeft),
// the island opens on its default view, or the house tab is clicked. It is dropped when the Claude
// app comes in front (the user is there), when a newer alert replaces it, and after 30 min.
//
// The house tab of the island's header carries a badge while an alert is held, or while the Claude
// app pill got a badge the user has not seen (a finish, an error, a request behind a card, while the
// island was busy): the strongest of the two. The pill's own badge is drawn nowhere since the home
// lost its Claude pills; it clears from the tab when the home's list is on screen.
//
// Foundation only, tested by scripts/test-code-notification.sh. No timer: the 30 min are compared
// when the island would show its home or draws the tab.

/// What a Claude app alert says and its sound, kept while the island is busy.
struct HeldClaudeAppAlert: Equatable, Sendable {
    var title: String
    var message: String
    /// `approval` (a permission), `question` (Claude waits) or `finish` (a finished answer).
    var sound: String
    /// When it was held: past `ClaudeAppAlertHold.lifetime` it says nothing current.
    var heldAt: Date
    /// The Code tab session the alert is about; nil for the Chat and Cowork watch, whose alerts come
    /// only with the Claude app behind (its activation drops them).
    var sessionId: String? = nil

    /// The mark of the house tab: finished for a finished answer, approval for anything asked.
    var badge: PillBadge { sound == "finish" ? .finished : .approval }
}

/// The latest Claude app alert the busy island could not show, the Claude app pill's badge not seen
/// yet, and what the island does with them.
struct ClaudeAppAlertHold: Equatable, Sendable {
    /// How long a held alert waits to be shown: 30 min.
    static let lifetime: TimeInterval = 30 * 60

    /// The alert to show in place of the home, nil when none waits.
    private(set) var held: HeldClaudeAppAlert? = nil
    /// The strongest badge the Claude app pill got since the home's list was last on screen.
    private(set) var unseenBadge: PillBadge? = nil

    init() {}

    /// A Claude app alert went through `FinishPresentation`. Blocked (`.badgeOnly`): it is held, in
    /// place of any older one. Shown (`.open`): the note on screen is the newest, the older held one
    /// is dropped (it never shows after a newer one).
    mutating func alertCame(_ alert: HeldClaudeAppAlert, presentation: FinishPresentation) {
        held = presentation == .badgeOnly ? alert : nil
    }

    /// The Claude app pill was badged while the island could not show why (a finish or an error
    /// only badged, a request waiting behind a card).
    mutating func pillBadged(_ badge: PillBadge) {
        unseenBadge = Self.strongest(unseenBadge, badge)
    }

    /// The home's list is on screen: its rows tell what the pill's badge said. A held alert stays.
    mutating func homeListShown() {
        unseenBadge = nil
    }

    /// A hook event of Code tab session `sessionId` other than a notification (a tool ran, a prompt,
    /// an end, a new request): what its held alert asked was answered in the Claude app, or is asked
    /// again by its own card. The held alert of that session goes, and its mark on the house tab.
    mutating func sessionMovedOn(_ sessionId: String) {
        if held?.sessionId == sessionId { held = nil }
    }

    /// The Claude app pill's own badge was cleared (its request shows, or left): the house tab, which
    /// mirrors it, loses the unseen mark. A held alert keeps its own.
    mutating func pillBadgeCleared() {
        unseenBadge = nil
    }

    /// Past 30 min the held alert goes (the island calls this once, at that time). Returns true when
    /// it dropped one.
    @discardableResult
    mutating func dropExpired(now: Date) -> Bool {
        guard let alert = held, Self.expired(alert, now: now) else { return false }
        held = nil
        return true
    }

    /// The Claude app came in front: the user is there, what it had to say is seen.
    mutating func claudeAppCameToFront() {
        held = nil
        unseenBadge = nil
    }

    /// The island is about to show its home. `presentation`: `FinishPresentation.decide` for that
    /// home, the same rule as when the alert came. Returns the held alert to show in its place (it is
    /// no longer held), nil for the home. Past 30 min the held alert is dropped and the home shows; a
    /// home the alert may not be shown over (pinned) keeps it held for the next time.
    mutating func takeForHome(presentation: FinishPresentation, now: Date) -> HeldClaudeAppAlert? {
        guard let alert = held else { return nil }
        if Self.expired(alert, now: now) {
            held = nil
            return nil
        }
        guard presentation == .open else { return nil }
        held = nil
        return alert
    }

    /// The badge of the house tab, nil for none: the held alert's (unless past 30 min) or the unseen
    /// pill badge, the strongest of the two.
    func houseBadge(now: Date) -> PillBadge? {
        let fromHeld = held.flatMap { Self.expired($0, now: now) ? nil : $0.badge }
        return Self.strongest(fromHeld, unseenBadge)
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

    private static func expired(_ alert: HeldClaudeAppAlert, now: Date) -> Bool {
        now.timeIntervalSince(alert.heldAt) > lifetime
    }
}
