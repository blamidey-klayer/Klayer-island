import Foundation

// MARK: - The card steps aside in the session's app (Task 27)
// Baptiste, 9 October 2026: « Klayer Island doit me permettre de répondre à Claude, mais si je vais
// dans la session en question je dois aussi pouvoir répondre, et la carte de l'île disparaît car je
// suis sur la bonne conversation ». A permission or question card on screen, or a note of the Claude
// app, folds when the app of its session comes to the front: the island sends no decision, the
// request stays pending (badge, hovering shows the card again), and answering in the app closes it as
// before (its hook connection closes, « Handled in … »). Only a change of app counts: an app already
// in front when the card came does not fold it until the user has gone elsewhere and come back. The
// host of a request: the Claude app for its sessions, the app the relay reports (`bundle_id`, from
// `__CFBundleIdentifier`) for an editor. The terminal does not change: a terminal session's card
// (terminal cards on in Settings) never steps aside. Foundation only, tested by
// scripts/test-card-step-aside.sh; AppState keeps the watch, IslandWindowController folds.

enum CardStepAside {
    /// Whether the activation of `activatedBundleId` folds the card of `hostBundleId` shown at
    /// `cardShownAt` (nil: no card on screen). `hostWasFrontAtShow`: the host has been in front since
    /// the card showed, with no other app in between, so this is no change of app.
    static func shouldStepAside(hostBundleId: String?, activatedBundleId: String?, cardShownAt: Date?,
                                hostWasFrontAtShow: Bool) -> Bool {
        guard cardShownAt != nil, !hostWasFrontAtShow else { return false }
        return sameApp(hostBundleId, activatedBundleId)
    }

    /// Two bundle ids name the same app: equal once trimmed, letter case ignored. No id is no app.
    static func sameApp(_ a: String?, _ b: String?) -> Bool {
        let x = (a ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let y = (b ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return !x.isEmpty && x.caseInsensitiveCompare(y) == .orderedSame
    }

    /// The app a request's card steps aside for: the Claude app for a session of the Claude app
    /// (`desktopSession`), nothing for a terminal session (`terminalSession`: the terminal does not
    /// change), else the bundle id the relay forwarded, nil when blank.
    static func requestHost(desktopSession: Bool, terminalSession: Bool, bundleId: String?) -> String? {
        if desktopSession { return HookRouting.desktopBundleId }
        guard !terminalSession else { return nil }
        let id = (bundleId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return id.isEmpty ? nil : id
    }
}

/// What may step aside: the card on screen, by its request, or a note of the Claude app.
enum StepAsideSubject: Equatable, Sendable {
    case approval(requestId: Int)
    case question(requestId: Int)
    case claudeAppNote(title: String, message: String)

    /// A permission or a question: it stays pending when the island folds.
    var isRequest: Bool {
        if case .claudeAppNote = self { return false }
        return true
    }
}

/// The card (or note) on screen, its host, and whether that host has been in front since it showed.
struct StepAsideWatch: Equatable, Sendable {
    let subject: StepAsideSubject
    let hostBundleId: String?
    let shownAt: Date
    /// The host is the app in front, and no other app came in front since the card showed.
    private(set) var hostInFront: Bool

    init(subject: StepAsideSubject, hostBundleId: String?, shownAt: Date, frontmostBundleId: String?) {
        self.subject = subject
        self.hostBundleId = hostBundleId
        self.shownAt = shownAt
        self.hostInFront = CardStepAside.sameApp(hostBundleId, frontmostBundleId)
    }

    /// An app came to the front. True when the card folds: its host came in front after the card
    /// showed. Whatever came, the watch then knows whether the host is in front.
    mutating func appActivated(_ bundleId: String?) -> Bool {
        let steps = CardStepAside.shouldStepAside(hostBundleId: hostBundleId, activatedBundleId: bundleId,
                                                  cardShownAt: shownAt, hostWasFrontAtShow: hostInFront)
        hostInFront = CardStepAside.sameApp(hostBundleId, bundleId)
        return steps
    }

    /// The watch for what the island shows now (`onScreen`: the card or note and its host, nil when
    /// none): the current one for the same card, a new one from `now` for another (its host in front
    /// or not, from `frontmostBundleId`), none when nothing may step aside.
    static func next(current: StepAsideWatch?, onScreen: (subject: StepAsideSubject, host: String?)?, now: Date,
                     frontmostBundleId: String?) -> StepAsideWatch? {
        guard let onScreen else { return nil }
        if let current, current.subject == onScreen.subject, current.hostBundleId == onScreen.host { return current }
        return StepAsideWatch(subject: onScreen.subject, hostBundleId: onScreen.host, shownAt: now,
                              frontmostBundleId: frontmostBundleId)
    }
}
