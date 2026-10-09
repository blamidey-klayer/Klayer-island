import Foundation
import SwiftUI
import Combine


@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    // Island state
    @Published var mode: IslandMode = .hidden {
        didSet {
            noteHomeListShown()
            refreshStepAsideWatch()
        }
    }
    @Published var view: IslandView = .overview {
        // A permission or question card that comes on screen takes Klay's pose back.
        didSet {
            if showsRequestCard { dropBusyPose() }
            noteHomeListShown()
            refreshStepAsideWatch()
        }
    }

    // Tasks
    @Published var tasks: [AgentTask] = []
    @Published var focusId: String? = nil {
        didSet { noteHomeListShown() }
    }

    // Bot state override
    @Published var stateOverride: BotState? = nil

    // Real notch dimensions (set by IslandWindowController on launch)
    var notchWidth:  CGFloat = IslandConst.notchWidth
    var notchHeight: CGFloat = IslandConst.notchHeight
    var hasNotch = true

    // Last app active before NotchBuddy (for window context capture)
    var lastExternalApp: NSRunningApplication? = nil

    // Bot drag-attach state (hides original bot while ghost follows cursor)
    @Published var isDraggingBot: Bool = false

    // Desktop Klay: true while Klay lives on the desktop instead of the notch
    @Published var klayOnDesktop: Bool = false

    // True while Klay walks back into the island (KlayWalker): the island's Klay stays hidden
    // until the walker is home, so two Klays never show.
    @Published var klayWalkingHome: Bool = false

    // Mouse tracking
    var mousePosition: CGPoint = .zero
    var lastMouseMove: Date = .now
    var isPresent: Bool = true

    // Pinned (alerts that stay open, never auto-close)
    var isPinned: Bool = false

    /// When the open island folds on the auto-close timer, as the state machine scheduled it
    /// (`IslandStateMachine.foldDeadline`), else nil. The countdown bar draws only from it.
    @Published var foldDeadline: Date? = nil

    // Keyboard navigation: index of the selected item within the current card's list (nil = none)
    @Published var cardSelection: Int? = nil
    // Number of navigable items in the card currently on screen (0 = no list)
    @Published var cardItemCount: Int = 0

    // Upload progress (0-1): set to 1.0 only at completion; animation is time-based
    @Published var uploadProgress: Double = 0

    // Upload animation timing (non-published: TimelineViews read these directly)
    var uploadStartTime: Date?
    var uploadDuration: Double = 2.4

    // A file is dragged over the island (the drop card's green border and glow)
    @Published var fileDragOver: Bool = false

    // Sound enabled: persisted
    @Published var soundEnabled: Bool = true {
        didSet { UserDefaults.standard.set(soundEnabled, forKey: "soundEnabled") }
    }

    // A colour of the user's own for each pill's Klay (pill id → "#RRGGBB"): persisted.
    // Empty means the catalog's colours. PillDefinition.color reads the stored value, so
    // what is built from the catalog follows on its own; the tasks already on the island
    // hold a copy of their colour and are repainted here.
    @Published var pillColors: [String: String] = [:] {
        didSet {
            PillColors.stored = pillColors
            var repainted = tasks
            var changed = false
            for i in repainted.indices {
                guard let def = PillCatalog.definition(for: repainted[i].id),
                      repainted[i].color != def.color else { continue }
                repainted[i].color = def.color
                changed = true
            }
            if changed { tasks = repainted }
        }
    }
    /// Picks a colour for a pill's Klay; nil, or the pill's own catalog colour, goes back to the default.
    func setPillColor(_ id: String, _ hex: String?) {
        guard let def = PillCatalog.definition(for: id) else { return }
        pillColors = PillColors.picking(hex, for: id, catalogColor: def.defaultColor, in: pillColors)
    }

    // The always-on workspace pill: Claude Code, the only one left since the editor pills went
    // (spec §6). Persisted.
    @Published var mainPillId: String = PillCatalog.defaultMainPillId {
        didSet { UserDefaults.standard.set(mainPillId, forKey: "mainPill") }
    }

    // Sound volume (0–0.2): persisted, synced to SoundEngine
    @Published var soundVolume: Double = 0.12 {
        didSet {
            UserDefaults.standard.set(soundVolume, forKey: "soundVolume")
            SoundEngine.shared.volume = Float(soundVolume)
        }
    }

    // Selected app language ("" = System, else BCP-47 code e.g. "fr")
    @Published var appLanguage: String = {
        let bundleId = Bundle.main.bundleIdentifier ?? "ai.klayer.island"
        let langs = UserDefaults.standard.persistentDomain(forName: bundleId)?["AppleLanguages"] as? [String]
        return langs?.first ?? ""
    }()

    // Context for prompt (window attach / file). Only an explicit act sets it (lot 6 spec §3): Klay
    // dropped on a window (or ⌃⌥W), or « Poser une question » on a dropped file. Opening the chat
    // never captures the previous app's window.
    @Published var promptContext: PromptContext? = nil

    // Dropped file (set during upload flow)
    @Published var droppedFile: DroppedFile? = nil

    // Short note message (shown in NoteView)
    @Published var noteMessage: String? = nil {
        // A note set on its own (« Handled in Claude. », a chat error) is not the Claude app's
        // alert: the alert only lasts while its message is the note.
        didSet { if let alert = claudeAppAlert, alert.message != noteMessage { claudeAppAlert = nil } }
    }

    /// The alert the note view shows while the app asks something of the user: a title, a line,
    /// and « Ouvrir ce chat » or « Ouvrir cette session ». Set by `showClaudeAppAlert` only; nil for
    /// every other note.
    @Published private(set) var claudeAppAlert: ClaudeAppAlert? = nil {
        didSet { refreshStepAsideWatch() }
    }

    /// The Claude app alert held while the island was busy (the latest one), and the Claude app pill's
    /// badge not seen yet: what the house tab's badge shows (ClaudeAppAlertHold, tested).
    @Published private(set) var claudeAppAlertHold = ClaudeAppAlertHold()

    // Auto-close delay: persisted
    @Published var autoCloseInterval: TimeInterval = 15 {
        didSet { UserDefaults.standard.set(autoCloseInterval, forKey: "autoCloseInterval") }
    }

    // Greeting threshold: how long hidden before greeting on reappear (default 2 min)
    var greetThresholdSeconds: TimeInterval = 120 {
        didSet { UserDefaults.standard.set(greetThresholdSeconds, forKey: "greetThreshold") }
    }

    // Hotkey to show island (e.g. ⌘⇧N)
    @Published var hotkeyEnabled: Bool = false {
        didSet { UserDefaults.standard.set(hotkeyEnabled, forKey: "hotkeyEnabled") }
    }
    var hotkeyFlags: UInt = NSEvent.ModifierFlags([.command, .shift]).rawValue {
        didSet { UserDefaults.standard.set(Int(hotkeyFlags), forKey: "hotkeyFlags") }
    }
    var hotkeyCode: UInt16 = 45 {  // 'n'
        didSet { UserDefaults.standard.set(Int(hotkeyCode), forKey: "hotkeyCode") }
    }

    // Screen hosting the island (notch screen by default): persisted
    @Published var islandDisplay: IslandDisplayChoice = .notch {
        didSet { UserDefaults.standard.set(islandDisplay.storageValue, forKey: "islandDisplay") }
    }

    // Active integration pills (main workspace pill excluded). Max 4.
    @Published var activeIntegrations: Set<String> = ["integration_github"] {
        didSet {
            if let data = try? JSONEncoder().encode(Array(activeIntegrations)) {
                UserDefaults.standard.set(data, forKey: "activeIntegrations")
            }
            // Clear stale GitHub data when the integration is disabled
            if !activeIntegrations.contains("integration_github") && oldValue.contains("integration_github") {
                githubPulse = nil
                githubActivity = nil
            }
        }
    }

    // GitHub stats + pulse + activity (populated by GithubPoller)
    @Published var githubStats: GitHubStats? = nil
    @Published var githubPulse: GitHubPulse? = nil
    @Published var githubActivity: GitHubActivity? = nil

    // Chat conversation history
    @Published var chatHistory: [ChatMessage] = []

    // Pending approval request from Claude Code hook
    @Published var pendingApproval: ApprovalInfo? = nil {
        didSet { refreshStepAsideWatch() }
    }

    // Pending AskUserQuestion from Claude Code hook
    @Published var pendingQuestion: AskQuestion? = nil {
        didSet {
            QuestionLayout.height = pendingQuestion?.estimatedIslandHeight
            refreshStepAsideWatch()
        }
    }
    // Token of the pending question (HookServer), set before `pendingQuestion`: the card re-arms
    // its buttons and keeps its draft per request, even for two questions with the same text.
    @Published var pendingQuestionRequestId: Int = 0
    // The app the pending question's card steps aside for (`CardStepAside.requestHost`), set with
    // `pendingQuestionRequestId`, before `pendingQuestion`.
    var pendingQuestionHost: String? = nil
    // What was chosen so far on the question card, for the request it belongs to (QuestionDraft):
    // the card's view is rebuilt on each opening, the draft survives a fold. Read on opening only.
    var questionDraft: QuestionDraft? = nil

    // Choices answered from the island (permissions and questions), kept in choices.json.
    // `recentChoices` is the 3 newest, newest first, for the home of the open island.
    private let choiceHistory = ChoiceHistory(fileURL: HookServer.supportDir.appendingPathComponent("choices.json"))
    @Published private(set) var recentChoices: [ChoiceRecord] = []

    func recordChoice(_ r: ChoiceRecord) {
        choiceHistory.record(r)
        recentChoices = choiceHistory.latest(ChoiceHistoryView.limit)
    }

    // Claude sessions, one row each, most recent activity first (rules in SessionRoster): the
    // running ones and those that finished today. Fed by HookServer. Pruned on every update and
    // when the home shows, never on a timer: a hidden island costs no CPU. Midnight is the user's
    // (`Calendar.autoupdatingCurrent`).
    private var sessionRoster = SessionRoster()
    @Published private(set) var sessions: [SessionRow] = []

    // The session the finished view tells about: set when a Stop opens the island on that view, and
    // replaced by the next one. The view reads it first, so it names the session that ended (its
    // project, its last sentence, the app it runs in) even when its pill is shared with another
    // session or gone. Nil falls back to the pill in focus.
    @Published var finishedSession: SessionRow? = nil
    // The session the error view tells about, set when a StopFailure opens the island on it, like
    // `finishedSession`: its project, its error text (`lastAction`, empty when the hook gave none)
    // and the app it runs in. Nil falls back to the pill in focus.
    @Published var failedSession: SessionRow? = nil

    /// `folder`: the project folder, what the row goes by while the session has no name.
    /// `hostBundleId`, `entrypoint`: the app the session runs in and its `klayer_entrypoint`, nil
    /// keeps the ones the row has. `prompt`: a prompt of the session, the first names it while nobody
    /// did (`SessionName.fromPrompt`).
    func updateSession(sessionId: String, pillId: String, folder: String, phase: SessionPhase,
                       lastAction: String?, hostBundleId: String? = nil, entrypoint: String? = nil,
                       prompt: String? = nil) {
        let now = Date()
        sessionRoster.update(sessionId: sessionId, pillId: pillId, folder: folder, phase: phase,
                             lastAction: lastAction, hostBundleId: hostBundleId, entrypoint: entrypoint,
                             prompt: prompt, at: now)
        sessionRoster.prune(now: now, calendar: .autoupdatingCurrent)
        sessions = sessionRoster.rows
    }

    /// Prunes the roster when the home shows (the island opens, or comes back to the home): a row
    /// that went stale while no hook arrived is gone before the user sees it. No timer.
    func pruneSessions() {
        sessionRoster.prune(now: Date(), calendar: .autoupdatingCurrent)
        if sessions != sessionRoster.rows { sessions = sessionRoster.rows }
    }

    func endSession(_ id: String) {
        sessionRoster.end(sessionId: id)
        sessionRoster.prune(now: Date(), calendar: .autoupdatingCurrent)
        if sessions != sessionRoster.rows { sessions = sessionRoster.rows }
    }

    /// A name of session `id` arrived: a hook's `session_title` or the status line's
    /// `session_name`; the latest non-empty one wins (rules in `SessionRoster.name`). Its row, and the
    /// finished or error view that tells about it, go by that name. Kept in memory with the row
    /// (`recordChoice` writes the row's title of an answered request to the history, as before).
    /// True when the name the session goes by changed.
    @discardableResult
    func nameSession(_ id: String, _ raw: Any?) -> Bool {
        guard sessionRoster.name(sessionId: id, raw, at: Date()) else { return false }
        if sessions != sessionRoster.rows { sessions = sessionRoster.rows }
        if let finished = finishedSession, finished.id == id {
            finishedSession?.title = sessionRoster.title(of: id, folder: finished.folder)
        }
        if let failed = failedSession, failed.id == id {
            failedSession?.title = sessionRoster.title(of: id, folder: failed.folder)
        }
        return true
    }

    /// What session `id` goes by: its name when one is known, even before its row exists, else `folder`.
    func sessionTitle(of id: String, folder: String) -> String {
        sessionRoster.title(of: id, folder: folder)
    }

    // Claude plan gauge (from statusline hook)
    @Published var claudePlanUsage: PlanUsage? = nil {
        didSet {
            if let u = claudePlanUsage,
               let data = try? JSONEncoder().encode(u) {
                UserDefaults.standard.set(data, forKey: "claudePlanUsage")
            }
        }
    }

    // Plan gauge: show pill in notch header (persisted)
    @Published var showPlanInNotch: Bool = false {
        didSet { UserDefaults.standard.set(showPlanInNotch, forKey: "showPlanInNotch") }
    }
    // Cached relay-installed state: updated at launch, after install/uninstall, on Settings open
    @Published var planRelayInstalled: Bool = false
    // Transient: reset when island closes or view changes
    @Published var showingPlanDetail: Bool = false

    func refreshPlanRelayState() {
        planRelayInstalled = HookServer.statusLineInstalled()
    }

    // MARK: - Init (loads persisted settings)

    private init() {
        let ud = UserDefaults.standard

        if let v = ud.object(forKey: "soundEnabled") as? Bool   { soundEnabled = v }
        if let v = ud.object(forKey: "soundVolume")  as? Double { soundVolume  = v }
        pillColors = PillColors.stored
        recentChoices = choiceHistory.latest(ChoiceHistoryView.limit)
        // Migrate old 60s default → 15s
        if let v = ud.object(forKey: "autoCloseInterval") as? Double {
            autoCloseInterval = (v == 60) ? 15 : v
        }
        if let v = ud.object(forKey: "greetThreshold")    as? Double { greetThresholdSeconds = v }
        if let v = ud.object(forKey: "hotkeyEnabled") as? Bool  { hotkeyEnabled = v }
        if let v = ud.object(forKey: "hotkeyFlags")   as? Int   { hotkeyFlags = UInt(v) }
        if let v = ud.object(forKey: "hotkeyCode")    as? Int   { hotkeyCode = UInt16(v) }
        if let v = ud.string(forKey: "islandDisplay") { islandDisplay = IslandDisplayChoice(storageValue: v) }
        if let d = ud.data(forKey: "activeIntegrations"),
           let a = try? JSONDecoder().decode([String].self, from: d) { activeIntegrations = Set(a) }
        if let v = ud.string(forKey: "mainPill"), !v.isEmpty,
           PillCatalog.all.contains(where: { $0.id == v && $0.category == .workspace && !$0.comingSoon }) {
            mainPillId = v
        } else {
            // A main pill this build no longer has (the editor pill agent_cursor): Claude Code,
            // the default, and the stale value leaves the preferences. loadIntegrationTasks drops
            // a removed pill from the active list the same way.
            ud.removeObject(forKey: "mainPill")
        }
        if let d = ud.data(forKey: "claudePlanUsage"),
           let u = try? JSONDecoder().decode(PlanUsage.self, from: d) { claudePlanUsage = u }
        if let v = ud.object(forKey: "showPlanInNotch") as? Bool { showPlanInNotch = v }
        planRelayInstalled = HookServer.statusLineInstalled()

        // Sync SoundEngine volume on launch
        SoundEngine.shared.volume = Float(soundVolume)

        // Always load integration pills
        loadIntegrationTasks()
    }

    // MARK: - Computed

    var focusTask: AgentTask? {
        tasks.first { $0.id == focusId } ?? tasks.first
    }

    var effectiveState: BotState {
        stateOverride ?? focusTask?.state ?? .idle
    }

    /// The island's view is a permission or question card whose request is still pending. Its
    /// pill's pose (approval, question) is Klay's: the quick chat and the Gmail draft neither set
    /// nor keep their own over it (a request's pose wins).
    var showsRequestCard: Bool {
        (view == .approval && pendingApproval != nil) || (view == .question && pendingQuestion != nil)
    }

    /// The poses only the chat and the Gmail draft set (Klay thinking, the chat's error note)
    /// give way to a request card. Any other override (dizzy) stays.
    func dropBusyPose() {
        if stateOverride == .thinking || stateOverride == .error { stateOverride = nil }
    }

    // MARK: - Task management

    func addTask(_ task: AgentTask) {
        guard !tasks.contains(where: { $0.id == task.id }) else { return }
        tasks.append(task)
        if focusId == nil { focusId = task.id }
        syncMode()
        syncView()
    }

    func removeTask(id: String) {
        // mainPillId: always reset, never remove (the active workspace tool)
        // activeIntegrations: also reset (user declared it active, keep it as idle)
        let isProtected = id == mainPillId
        let isActiveDecl = PillCatalog.definition(for: id) != nil && activeIntegrations.contains(id)
        if isProtected || isActiveDecl {
            if let idx = tasks.firstIndex(where: { $0.id == id }) {
                let catalogName = PillCatalog.definition(for: id)?.name
                tasks[idx].state      = .idle
                tasks[idx].steps      = []
                tasks[idx].stepIndex  = 0
                tasks[idx].pillBadge  = nil
                if let n = catalogName { tasks[idx].name = n }
            }
            return
        }
        // Undeclared or declared-but-not-active: remove
        tasks.removeAll { $0.id == id }
        if focusId == id { focusId = mainPillId }
        syncMode(revealing: false)
        syncView()
    }

    func updateTask(id: String, state: BotState) {
        guard let idx = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[idx].state = state
    }

    func setFocus(_ id: String) {
        guard let idx = tasks.firstIndex(where: { $0.id == id }) else { return }
        focusId = id
        tasks[idx].pillBadge = nil  // clear badge when user brings task to focus
    }

    // MARK: - Home rail (lot 6 spec §2)

    /// The pill in focus before the rail put GitHub's or Spotify's card in place of the list: it
    /// gets the focus back (and Klay its pose) when the list comes back.
    private var focusBeforeCard: String? = nil

    /// A click on the Spotify or GitHub icon of the rail: its card replaces the list.
    func showCard(_ pillId: String) {
        if !HomeRail.showsCard(focusId: focusTask?.id) { focusBeforeCard = focusTask?.id }
        setFocus(pillId)
    }

    /// The house tab, or a second click on the icon of the card on screen: the list comes back,
    /// the focus goes back to the pill that had it (`HomeRail.listFocus`). Nothing changes when
    /// the list is already there.
    func showHomeList() {
        guard HomeRail.showsCard(focusId: focusTask?.id) else { return }
        focusId = HomeRail.listFocus(saved: focusBeforeCard, loaded: tasks.map(\.id), main: mainPillId)
        focusBeforeCard = nil
    }

    /// « Poser une question » on a dropped file: the file becomes the chat's context. Dropping a
    /// file alone adds nothing to the chat: after « Préparer un email », the chat opens without it.
    func askAboutDroppedFile() {
        if let file = droppedFile {
            promptContext = .file(name: file.name, fileURL: file.url)
        }
    }

    /// A permission or a question left: the focus goes back to `saved`, the pill it took the screen
    /// from, or to the list's pill when `saved` showed a card (`HomeRail.focusAfterRequest`).
    func restoreFocus(afterRequest saved: String) {
        let back = HomeRail.focusAfterRequest(saved: saved, beforeCard: focusBeforeCard,
                                              loaded: tasks.map(\.id), main: mainPillId)
        if HomeRail.showsCard(focusId: saved) { focusBeforeCard = nil }
        focusId = back
    }

    /// The rail's icons (`HomeRail.icons`): Spotify when its pill is on, GitHub when its pill is on
    /// and a token is set (KeychainStore reads its cache, never the Keychain), Granola always. The
    /// rail and the pill shortcuts both read it.
    var homeRailIcons: [RailIcon] {
        func loaded(_ icon: RailIcon) -> Bool {
            guard let id = icon.pillId else { return false }
            return tasks.contains { $0.id == id }
        }
        return HomeRail.icons(spotifyActive: loaded(.spotify),
                              githubConfigured: loaded(.github) && KeychainStore.shared.get("github-token") != nil)
    }

    func setPillBadge(_ badge: PillBadge, for id: String) {
        guard let idx = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[idx].pillBadge = badge
    }

    // MARK: - The Claude app waits for the user (lot 6 spec §5 and §6)

    /// The one entry that tells the user the Claude app waits for them (a permission or a question
    /// of the Code tab, and Chat and Cowork): the note view shows `title` and `message` with
    /// « Ouvrir ce chat » (Chat, Cowork) or « Ouvrir cette session » (Code tab), which opens the
    /// Claude app, then folds the island. The island opens the
    /// way a finished session's does (`.hookExpand`): the state machine holds it until the pointer
    /// has been on it and left, and `FinishPresentation` decides whether it may open at all: it
    /// never covers a draft of the chat or of a mail, a card that waits, or a pinned island. Then
    /// the sound plays, the Claude app pill is badged and the alert is held, the latest one only:
    /// it shows in place of the home once the island frees (`showHeldClaudeAppAlert`), and the house
    /// tab carries its badge meanwhile (ClaudeAppAlertHold). Nothing here clicks in the Claude app,
    /// answers, or approves. Returns true when the note is on its way to the screen.
    /// `sound`: the sound that plays, `question` for Claude waiting (the default), `approval` for a
    /// permission, `finish` for a finished answer. `sessionId`: the Code tab session the alert is
    /// about (nil for the Chat and Cowork watch): a held alert goes when that session moves on.
    @discardableResult
    func showClaudeAppAlert(title: String, message: String, sound: String = "question",
                            sessionId: String? = nil) -> Bool {
        let alert = ClaudeAppAlert(title: title, message: message, source: .of(sessionId: sessionId), sound: sound)
        // The same alert is already on screen: no second sound, no new hold on the island.
        if mode == .expanded, view == .note, claudeAppAlert == alert { return true }
        SoundEngine.shared.play(sound)
        let presentation = FinishPresentation.decide(
            expanded: mode == .expanded, view: view.rawValue, pinned: isPinned,
            requestPending: pendingApproval != nil || pendingQuestion != nil)
        // Blocked, it is held for when the island frees; shown, it replaces the one held.
        claudeAppAlertHold.alertCame(HeldClaudeAppAlert(title: title, message: message, sound: sound,
                                                        heldAt: Date(), sessionId: sessionId),
                                     presentation: presentation)
        guard presentation == .open else {
            setPillBadge(.approval, for: HookRouting.desktopPillId)
            scheduleHeldAlertExpiry()
            return false
        }
        putClaudeAppAlertOnNote(alert)
        NotificationCenter.default.post(name: .hookExpand, object: IslandView.note)
        return true
    }

    /// The island is about to show its home (`home`): a request left with nothing else waiting
    /// (HookServer.requestLeft), the island opens on its default view, or the house tab is clicked.
    /// The Claude app alert held while it was busy takes the note view instead, under the same rule
    /// as when it came (`FinishPresentation` for that home), with its sound. Returns true when it
    /// did: the note is set. `announce` posts it the way an alert opens the island (the state machine
    /// holds it until the pointer has been on it and left); otherwise the caller puts the island on
    /// `.note` itself, and it folds the way it opened (a hover, the toggle hot key, a click).
    @discardableResult
    func showHeldClaudeAppAlert(inPlaceOf home: IslandView, announce: Bool) -> Bool {
        guard claudeAppAlertHold.held != nil else { return false }
        let presentation = FinishPresentation.decide(
            expanded: mode == .expanded, view: home.rawValue, pinned: isPinned,
            requestPending: pendingApproval != nil || pendingQuestion != nil)
        guard let held = claudeAppAlertHold.takeForHome(presentation: presentation, now: Date()) else { return false }
        SoundEngine.shared.play(held.sound)
        putClaudeAppAlertOnNote(ClaudeAppAlert(title: held.title, message: held.message,
                                               source: .of(sessionId: held.sessionId), sound: held.sound))
        if announce { NotificationCenter.default.post(name: .hookExpand, object: IslandView.note) }
        return true
    }

    /// The note view's content for a Claude app alert. The Claude app pill, when it is loaded, takes
    /// Klay's pose and colour, as for a finish.
    private func putClaudeAppAlertOnNote(_ alert: ClaudeAppAlert) {
        noteMessage = alert.message        // first: a note that was showing loses its own alert
        claudeAppAlert = alert
        let pill = HookRouting.desktopPillId
        if focusId != pill, tasks.contains(where: { $0.id == pill }) {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.72)) { setFocus(pill) }
        }
    }

    /// Token of the one wake-up at the held alert's 30 min: a later hold replaces it.
    private var heldAlertExpiryToken = 0

    /// One wake-up, just past the held alert's 30 min, drops it and its mark on the house tab
    /// (ClaudeAppAlertHold.dropExpired). No polling: one timer per held alert, the last one only.
    private func scheduleHeldAlertExpiry() {
        heldAlertExpiryToken += 1
        let token = heldAlertExpiryToken
        DispatchQueue.main.asyncAfter(deadline: .now() + ClaudeAppAlertHold.lifetime + 1) {
            let state = AppState.shared
            guard state.heldAlertExpiryToken == token, state.claudeAppAlertHold.held != nil else { return }
            state.claudeAppAlertHold.dropExpired(now: Date())
        }
    }

    /// A hook event of Code tab session `sessionId` other than a notification, or a new request of
    /// it: its held alert was answered in the Claude app (or its own card asks it again). It goes,
    /// with its mark on the house tab. Nothing is published when no alert of that session is held.
    func claudeAppSessionMovedOn(_ sessionId: String) {
        guard claudeAppAlertHold.held?.sessionId == sessionId else { return }
        claudeAppAlertHold.sessionMovedOn(sessionId)
    }

    /// The Claude app pill's own badge was cleared (its request shows, or left): the house tab,
    /// which mirrors it, loses the unseen mark.
    func claudeAppPillBadgeCleared() {
        guard claudeAppAlertHold.unseenBadge != nil else { return }
        claudeAppAlertHold.pillBadgeCleared()
    }

    /// The Claude app came in front: the user is there. The held alert is dropped and the house tab
    /// loses its badge.
    func claudeAppCameToFront() {
        guard claudeAppAlertHold != ClaudeAppAlertHold() else { return }
        claudeAppAlertHold.claudeAppCameToFront()
    }

    // MARK: - The card steps aside in the session's app (Task 27, CardStepAside)

    /// The permission or question card, or the Claude app's note, on screen, with the app it steps
    /// aside for and whether that app has been in front since it showed. Nil while the island shows
    /// none of them (folded, another view). Kept in step with the view, the mode and the requests;
    /// never drawn, so not published.
    private(set) var stepAsideWatch: StepAsideWatch? = nil

    /// What may step aside on screen now, and its host.
    private var stepAsideOnScreen: (subject: StepAsideSubject, host: String?)? {
        guard mode == .expanded else { return nil }
        switch view {
        case .approval:
            guard let approval = pendingApproval else { return nil }
            return (.approval(requestId: approval.requestId), approval.hostBundleId)
        case .question:
            guard pendingQuestion != nil else { return nil }
            return (.question(requestId: pendingQuestionRequestId), pendingQuestionHost)
        case .note:
            guard let alert = claudeAppAlert else { return nil }
            return (.claudeAppNote(title: alert.title, message: alert.message), HookRouting.desktopBundleId)
        default:
            return nil
        }
    }

    /// A card that comes on screen starts its watch, from the app in front then; the same card keeps
    /// its own; none on screen, no watch. Reads the app in front only when something may step aside.
    private func refreshStepAsideWatch() {
        guard let onScreen = stepAsideOnScreen else {
            stepAsideWatch = nil
            return
        }
        if let watch = stepAsideWatch, watch.subject == onScreen.subject, watch.hostBundleId == onScreen.host { return }
        stepAsideWatch = StepAsideWatch.next(current: stepAsideWatch, onScreen: onScreen, now: Date(),
                                             frontmostBundleId: NSWorkspace.shared.frontmostApplication?.bundleIdentifier)
    }

    /// An app came to the front (`bundleId`). Returns what steps aside, nil when nothing does: the card
    /// or note on screen whose app came in front after it showed (`StepAsideWatch.appActivated`). The
    /// caller folds the island; nothing here answers anything.
    func appCameToFront(_ bundleId: String?) -> StepAsideSubject? {
        guard var watch = stepAsideWatch else { return nil }
        let steps = watch.appActivated(bundleId)
        stepAsideWatch = watch
        return steps ? watch.subject : nil
    }

    /// The Claude app pill was badged by a hook while the island could not show why (a finish or an
    /// error only badged, a request waiting behind a card): the house tab carries the badge until the
    /// home's list is on screen. The pill itself is drawn nowhere, and may go before then.
    func claudeAppPillBadged(_ badge: PillBadge) {
        claudeAppAlertHold.pillBadged(badge)
        noteHomeListShown()
    }

    /// The badge of the house tab of the header, nil for none (ClaudeAppAlertHold.houseBadge).
    var houseTabBadge: PillBadge? {
        claudeAppAlertHold.houseBadge(now: Date())
    }

    /// The home's list is on screen (the island open on the home, no GitHub or Spotify card in its
    /// place): its rows say what the Claude app pill's badge said, the house tab loses it.
    private func noteHomeListShown() {
        guard claudeAppAlertHold.unseenBadge != nil, mode == .expanded, view == .overview,
              !HomeRail.showsCard(focusId: focusTask?.id) else { return }
        claudeAppAlertHold.homeListShown()
    }

    /// Called on main thread after each GitHub pulse poll. Fires badge + sound based on events.
    func handleGitHubEvents(_ events: [GitHubEvent]) {
        guard !events.isEmpty else { return }
        // Priority: error > question (reviewRequested) > finish (ciPassed)
        var level = 0          // 0 = none, 1 = finish, 2 = question, 3 = error
        var badge: PillBadge?
        var sound: String?
        for event in events {
            switch event {
            case .ciFailed, .mainFailed:
                if level < 3 { level = 3; badge = .error;    sound = "error"    }
            case .reviewRequested:
                if level < 2 { level = 2; badge = .finished; sound = "question" }
            case .ciPassed:
                if level < 1 { level = 1; badge = .finished; sound = "finish"   }
            }
        }
        // Only set badge when the GitHub pill is not currently in focus
        if let b = badge, focusId != "integration_github" { setPillBadge(b, for: "integration_github") }
        if let s = sound { SoundEngine.shared.play(s) }
    }

    /// Keeps the island in step with its pills. With no task left, a compact island hides (the
    /// window controller tells the state machine). Klay comes out only through the state machine
    /// (spec §4): a pill that appears while the island is hidden posts a reveal, which hides him
    /// again 60 s after the pointer is away. A pill that goes, or a pill turned on or off in
    /// Settings (`revealing` false), brings nothing out: only session events do (SPEC rule 3).
    /// Setting `mode` to compact here left the state machine hidden and Klay out for good.
    func syncMode(revealing: Bool = true) {
        if tasks.isEmpty && mode == .compact {
            mode = .hidden
        } else if revealing && !tasks.isEmpty && mode == .hidden && isPresent {
            NotificationCenter.default.post(name: .hookReveal, object: nil)
        }
    }

    func syncView() {
        guard mode == .expanded else { return }
        if view == .empty && !tasks.isEmpty { view = .overview }
        else if view == .overview && tasks.isEmpty { view = .empty }
    }

    /// Load catalog pills into tasks, respecting activeIntegrations. Safe to call multiple times.
    func loadIntegrationTasks() {
        let catalog = PillCatalog.all
        // Sanitize: remove saved IDs not in catalog
        let catalogIds = Set(catalog.map { $0.id })
        activeIntegrations = activeIntegrations.filter { catalogIds.contains($0) }
        // Validate mainPillId: must be a non-comingSoon workspace pill in the catalog
        if !PillCatalog.all.contains(where: { $0.id == mainPillId && $0.category == .workspace && !$0.comingSoon }) {
            mainPillId = PillCatalog.defaultMainPillId
        }
        // mainPillId must never be in activeIntegrations (migration + invariant)
        activeIntegrations.remove(mainPillId)
        for def in catalog {
            // mainPillId always loads; activeIntegrations load
            let shouldLoad = def.id == mainPillId || activeIntegrations.contains(def.id)
            let loaded = tasks.contains(where: { $0.id == def.id })
            if shouldLoad && !loaded {
                let task = AgentTask(id: def.id, name: def.name, color: def.color,
                                     state: .idle, steps: [], source: def.source, isIntegration: true)
                tasks.append(task)
            }
            if !shouldLoad && loaded {
                tasks.removeAll { $0.id == def.id }
            }
        }
        sortTasksByCatalog()
        if focusId == nil { focusId = mainPillId }
        syncMode()
    }

    /// Toggle a catalog pill on/off.
    /// mainPillId: never toggleable (it is always on).
    /// Max 4 non-main pills active at once.
    func toggleIntegration(_ id: String) {
        guard id != mainPillId else { return }
        guard PillCatalog.all.contains(where: { $0.id == id }) else { return }
        if activeIntegrations.contains(id) {
            activeIntegrations.remove(id)
            tasks.removeAll { $0.id == id }
            if focusId == id { focusId = mainPillId }
        } else {
            guard activeIntegrations.count < 4 else { return }
            activeIntegrations.insert(id)
            if let def = PillCatalog.all.first(where: { $0.id == id }),
               !tasks.contains(where: { $0.id == id }) {
                let task = AgentTask(id: def.id, name: def.name, color: def.color,
                                     state: .idle, steps: [], source: def.source, isIntegration: true)
                tasks.append(task)
                sortTasksByCatalog()
            }
        }
        // A choice made in Settings: Klay does not come out for it.
        syncMode(revealing: false)
    }

    /// Sort tasks so catalog pills are in catalog order, undeclared pills sit right after
    /// integration_claude (matching HookServer insertion behaviour), and the rest follows.
    private func sortTasksByCatalog() {
        let order = PillCatalog.all.enumerated()
            .reduce(into: [String: Int]()) { $0[$1.element.id] = $1.offset }
        let catalogPills    = tasks.filter { order[$0.id] != nil }
        let undeclaredPills = tasks.filter { order[$0.id] == nil }
        let sortedCatalog   = catalogPills.sorted { (order[$0.id] ?? 0) < (order[$1.id] ?? 0) }
        if let claudeIdx = sortedCatalog.firstIndex(where: { $0.id == "integration_claude" }) {
            var result: [AgentTask] = Array(sortedCatalog[...claudeIdx])
            result.append(contentsOf: undeclaredPills)
            if claudeIdx + 1 < sortedCatalog.count {
                result.append(contentsOf: sortedCatalog[(claudeIdx + 1)...])
            }
            tasks = result
        } else {
            tasks = undeclaredPills + sortedCatalog
        }
    }

}

// MARK: - Supporting types

enum PromptContext {
    case window(appName: String, title: String, url: String?)
    case file(name: String, fileURL: URL?)
}

struct DroppedFile {
    var url: URL
    var name: String
}

/// What the note view says when the Claude app waits for the user: a title and one line. `source`:
/// a Code tab session or Chat and Cowork, for its icon and its button (« Ouvrir cette session »,
/// « Ouvrir ce chat »). `sound`: `approval`, `question` or `finish`, the colour of its icon.
struct ClaudeAppAlert: Equatable {
    var title: String
    var message: String
    var source: ClaudeAppNoteSource = .chat
    var sound: String = "question"
}

// MARK: - GitHub

struct GitHubStats {
    let totalRepos: Int
    let totalStars: Int
}

// MARK: - Chat

enum ChatRole { case user, assistant }

struct ChatMessage: Identifiable, Equatable {
    let id = UUID()
    let role: ChatRole
    var content: String   // var for streaming updates
    /// Written by the island, not by Claude: an error that came while the chat was not on screen.
    /// Shown as an answer bubble; never re-sent to Claude (`ChatOutgoing.earlierExchanges`).
    var isNotice = false
}
