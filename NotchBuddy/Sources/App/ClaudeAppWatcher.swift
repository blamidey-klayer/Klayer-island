import AppKit
import ApplicationServices

// MARK: - ClaudeAppWatcher: Chat and Cowork in the Claude app (lot 6 spec §6, experimental)
//
// The Claude app's Chat and Cowork modes emit no hook, so the island reads the app's interface
// through macOS Accessibility: a stop button that appears then disappears is a finished answer, an
// allow button next to a deny button is a permission asked. When that happens while the Claude app
// is not in front, the island opens on a note with « Ouvrir Claude » (AppState.showClaudeAppAlert).
// What may be concluded lives in ClaudeAppWatchRules (tested); this file only reads and schedules.
//
// - Reads only buttons (role and label), and the main window's title for the alert's line. Never a
//   value, a static text, a text area or a link. Never clicks, presses, focuses or types: the only
//   calls are AXUIElementCopyAttributeValue, and AXUIElementSetAttributeValue for
//   AXManualAccessibility (the Claude app is an Electron app: its tree exists only while it is on).
// - CPU: no timer while `ClaudeAppWatchState.needsPolling` is false. NSWorkspace notifications
//   (activation, launch, quit) wake it. A read every 2 s while the Claude app is in front or an
//   answer is under way (from behind: at most 15 unreadable reads in a row, at most 60 min), on one
//   serial queue, bounded (depth 30, 5 000 nodes, 0.5 s per call). The state decides alone. While
//   the displays sleep or the user's session is not the active one, no timer and no read: one read
//   when they come back, then the state decides again.
// - Not trusted for Accessibility: nothing is read or scheduled.

@MainActor
final class ClaudeAppWatcher {
    static let shared = ClaudeAppWatcher()

    /// UserDefaults: « Suivre Chat et Cowork dans l'app Claude (expérimental) », on by default.
    nonisolated static let enabledKey = "claudeAppWatchEnabled"
    /// UserDefaults: the build (CFBundleVersion) macOS's Accessibility prompt last showed for without
    /// a click of the user.
    nonisolated private static let promptedBuildKey = "claudeAppWatchPromptedBuild"

    nonisolated static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
    }

    /// Klayer Island may read other apps' interfaces (System Settings › Accessibility).
    nonisolated static var accessGranted: Bool { AXIsProcessTrusted() }

    private let reader = ClaudeAppReader()
    private var state = ClaudeAppWatchState()
    private var observers: [NSObjectProtocol] = []
    /// The watch is on: its observers are set.
    private var running = false
    /// The Claude app's process, while it runs.
    private var claudePid: pid_t?
    /// Reads go on (the next one is scheduled or under way); the Claude app's tree is held on.
    private var polling = false
    private var readInFlight = false
    /// A read was asked while one was under way: one more right after it.
    private var readAgain = false
    private var nextRead: Task<Void, Never>?
    /// Bumped on every reset: the result of a read started before it is dropped.
    private var generation = 0
    /// The displays sleep, or the user's session is not the active one (another user, the login
    /// window): no timer and no read until both are back.
    private var screensAsleep = false
    private var sessionInactive = false
    private var paused: Bool { screensAsleep || sessionInactive }
    /// « Accessibility access not granted » was written to the log in this launch.
    private var missingAccessLogged = false

    private init() {}

    // MARK: - On and off

    /// At launch and when Settings turns the watch on. Never in the end-to-end test launch
    /// (`KLAYER_ISLAND_TEST=1`): no observer, no read, no Accessibility prompt.
    func start() {
        guard !running, Self.isEnabled,
              !ClaudeAppWatchRules.isTestLaunch(environment: ProcessInfo.processInfo.environment) else { return }
        running = true
        let center = NSWorkspace.shared.notificationCenter
        observers = [
            center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil,
                               queue: .main) { note in
                let app = ClaudeAppWatcher.appRef(note)
                MainActor.assumeIsolated { ClaudeAppWatcher.shared.appActivated(app) }
            },
            center.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil,
                               queue: .main) { note in
                let app = ClaudeAppWatcher.appRef(note)
                MainActor.assumeIsolated { ClaudeAppWatcher.shared.appLaunched(app) }
            },
            center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil,
                               queue: .main) { note in
                let app = ClaudeAppWatcher.appRef(note)
                MainActor.assumeIsolated { ClaudeAppWatcher.shared.appTerminated(app) }
            },
            // The displays sleep and wake, the session goes inactive and comes back (M8).
            center.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil,
                               queue: .main) { _ in
                MainActor.assumeIsolated { ClaudeAppWatcher.shared.setPause(screensAsleep: true) }
            },
            center.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil,
                               queue: .main) { _ in
                MainActor.assumeIsolated { ClaudeAppWatcher.shared.setPause(screensAsleep: false) }
            },
            center.addObserver(forName: NSWorkspace.sessionDidResignActiveNotification, object: nil,
                               queue: .main) { _ in
                MainActor.assumeIsolated { ClaudeAppWatcher.shared.setPause(sessionInactive: true) }
            },
            center.addObserver(forName: NSWorkspace.sessionDidBecomeActiveNotification, object: nil,
                               queue: .main) { _ in
                MainActor.assumeIsolated { ClaudeAppWatcher.shared.setPause(sessionInactive: false) }
            },
        ]
        logMissingAccessOnce()
        if let app = Self.runningClaudeApp() {
            claudeSeen(pid: app.processIdentifier)
            if app.isActive { beginReading() }
        }
    }

    /// Settings turns the watch off, or the island quits: no observer, no timer, nothing runs, and
    /// the Claude app's tree goes back as it was. `waitForRestore` (at quit): a walk under way is
    /// cancelled, then the tree is restored before the island goes, even during a diagnostic.
    func stop(waitForRestore: Bool = false) {
        if running {
            running = false
            let center = NSWorkspace.shared.notificationCenter
            observers.forEach { center.removeObserver($0) }
            observers = []
            resetReading()
            claudePid = nil
            screensAsleep = false
            sessionInactive = false
        }
        if waitForRestore { reader.quit() } else { reader.release() }
    }

    func setEnabled(_ on: Bool) {
        if on { start() } else { stop() }
    }

    // MARK: - Accessibility access

    /// System Settings › Privacy & Security › Accessibility.
    nonisolated private static let accessibilityPane =
        "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"

    /// « Autoriser l'accès » in Settings, a click of the user: macOS's own Accessibility prompt, and
    /// the Accessibility pane of System Settings when the app is still not trusted after it (macOS
    /// no longer shows the prompt once the app is listed there and unchecked).
    static func requestAccess() {
        guard !ClaudeAppWatchRules.isTestLaunch(environment: ProcessInfo.processInfo.environment) else { return }
        if !showAccessPrompt(), let url = URL(string: accessibilityPane) {
            NSWorkspace.shared.open(url)
        }
    }

    /// Returns whether the app is trusted.
    @discardableResult
    nonisolated private static func showAccessPrompt() -> Bool {
        // The key of kAXTrustedCheckOptionPrompt, written out: the global is not concurrency-safe.
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    /// The prompt shows on its own at most once per build: the first time the watch is on and the
    /// Claude app is seen running without access, for a build it has not shown for yet (an ad hoc
    /// signed build loses the access at each update). Afterwards only from Settings.
    private func promptForAccessIfFirstTime() {
        logMissingAccessOnce()
        let defaults = UserDefaults.standard
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        guard ClaudeAppWatchRules.promptsForAccess(trusted: Self.accessGranted,
                                                   promptedBuild: defaults.string(forKey: Self.promptedBuildKey),
                                                   currentBuild: build)
        else { return }
        defaults.set(build, forKey: Self.promptedBuildKey)
        log("Accessibility prompt shown (once for build \(build))")
        Self.showAccessPrompt()
    }

    /// Once per launch, while the watch is on: the log says that access is missing, so a watch that
    /// reads nothing after an update shows in claude-app.log.
    private func logMissingAccessOnce() {
        guard running, !missingAccessLogged, !Self.accessGranted else { return }
        missingAccessLogged = true
        log("Accessibility access not granted: nothing is read (Settings, Agents, « Autoriser l'accès »)")
    }

    // MARK: - The Claude app comes and goes

    private struct AppRef: Sendable {
        let bundleId: String?
        let pid: pid_t
    }

    nonisolated private static func appRef(_ note: Notification) -> AppRef? {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return nil }
        return AppRef(bundleId: app.bundleIdentifier, pid: app.processIdentifier)
    }

    private static func runningClaudeApp() -> NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: HookRouting.desktopBundleId).first
    }

    private func appActivated(_ app: AppRef?) {
        guard running else { return }
        if let app, app.bundleId == HookRouting.desktopBundleId {
            claudeSeen(pid: app.pid)
            beginReading()
        } else if polling {
            // Another app came in front: one read now, before deciding to stop, so an answer sent
            // just before the switch is followed to its end (Review Focus 1).
            readNow()
        }
    }

    private func appLaunched(_ app: AppRef?) {
        guard running, let app, app.bundleId == HookRouting.desktopBundleId else { return }
        claudeSeen(pid: app.pid)
    }

    /// The Claude app quit: state reset, no timer. Its tree went with it: nothing to restore.
    private func appTerminated(_ app: AppRef?) {
        guard running, let app, app.bundleId == HookRouting.desktopBundleId, app.pid == claudePid else { return }
        resetReading()
        claudePid = nil
        reader.forget()
    }

    private func claudeSeen(pid: pid_t) {
        if let old = claudePid, old != pid {
            // Another process of the Claude app: what was seen belongs to the old one.
            resetReading()
            reader.forget()
        }
        claudePid = pid
        promptForAccessIfFirstTime()
    }

    // MARK: - Pause (M8)

    /// The displays went to sleep or woke, the session went inactive or came back. Paused: the
    /// timer goes and the Claude app's tree goes back off; a read under way finishes, nothing follows
    /// it. Back: one read (with access), then the state decides as after any read.
    private func setPause(screensAsleep asleep: Bool? = nil, sessionInactive inactive: Bool? = nil) {
        guard running else { return }
        let wasPaused = paused
        if let asleep { screensAsleep = asleep }
        if let inactive { sessionInactive = inactive }
        if paused, !wasPaused {
            log("Paused: the displays sleep or the session is inactive")
            stopReading()
        } else if !paused, wasPaused {
            log("Resumed")
            beginReading()
        }
    }

    // MARK: - Reading

    /// The Claude app came in front, or the watch resumes: reads start, if access is granted. Not
    /// trusted: nothing runs.
    private func beginReading() {
        guard running, !paused, claudePid != nil, Self.accessGranted else { return }
        readNow()
    }

    private func readNow() {
        guard running, !paused, let pid = claudePid else { return }
        nextRead?.cancel()
        nextRead = nil
        if readInFlight {
            readAgain = true
            return
        }
        readInFlight = true
        polling = true
        // In front when the read is asked; checked again once the walk is done (`didRead`).
        let askedInFront = Self.isFrontmost(pid)
        let generation = self.generation
        reader.read(pid: pid) { snapshot in
            Task { @MainActor in
                ClaudeAppWatcher.shared.didRead(snapshot, askedInFront: askedInFront, generation: generation)
            }
        }
    }

    private static func isFrontmost(_ pid: pid_t) -> Bool {
        NSWorkspace.shared.frontmostApplication?.processIdentifier == pid
    }

    private func didRead(_ snapshot: ClaudeAppSnapshot, askedInFront: Bool, generation: Int) {
        guard generation == self.generation else { return }   // started before a reset
        readInFlight = false
        guard running, let pid = claudePid else { return }
        guard snapshot.trusted else {
            log("Accessibility access refused: reading stops")
            stopReading()
            return
        }
        // In front only if it was when the read was asked and still is after the walk: an app
        // switch during the walk counts the read as behind.
        let frontmost = askedInFront && Self.isFrontmost(pid)
        if snapshot.complete {
            let events = state.observe(stopVisible: snapshot.stopVisible,
                                       permissionVisible: snapshot.permissionVisible,
                                       appFrontmost: frontmost, now: Date(),
                                       lastCodeHookAt: HookServer.shared.lastDesktopHookAt)
            present(events, windowTitle: snapshot.windowTitle)
        } else {
            // A read that said nothing (no window, a timeout): the state decides whether to go on.
            state.observeUnreadable(appFrontmost: frontmost)
        }
        if paused {
            // The displays went to sleep (or the session inactive) during the walk: nothing follows.
            stopReading()
        } else if readAgain {
            readAgain = false
            readNow()
        } else if state.needsPolling {
            scheduleNextRead()
        } else {
            stopReading()
        }
    }

    private func scheduleNextRead() {
        nextRead?.cancel()
        nextRead = Task { @MainActor in
            try? await Task.sleep(for: .seconds(ClaudeAppWatchRules.pollInterval))
            guard !Task.isCancelled else { return }
            ClaudeAppWatcher.shared.readNow()   // nothing while paused
        }
    }

    /// Nothing more to read: no timer left, and the Claude app's tree back as it was.
    private func stopReading() {
        nextRead?.cancel()
        nextRead = nil
        readAgain = false
        guard polling else { return }
        polling = false
        reader.endReading()
    }

    /// Forgets what was seen (the Claude app quit, or the watch went off): a read under way is
    /// dropped when it comes back.
    private func resetReading() {
        generation += 1
        state.reset()
        readInFlight = false
        readAgain = false
        nextRead?.cancel()
        nextRead = nil
        polling = false
    }

    // MARK: - The island

    private func present(_ events: [ClaudeAppEvent], windowTitle: String?) {
        guard !events.isEmpty else { return }
        let line = ClaudeAppWatchRules.conversationTitle(windowTitle: windowTitle)
            ?? String(localized: "Dans l'app Claude")
        if events.contains(.permissionRequested) {
            log("A permission waits in the Claude app")
            AppState.shared.showClaudeAppAlert(title: String(localized: "Claude attend ta réponse"),
                                               message: line, sound: "approval")
        } else if events.contains(.answerFinished) {
            log("An answer finished in the Claude app")
            AppState.shared.showClaudeAppAlert(title: String(localized: "Claude a fini de répondre"),
                                               message: line, sound: "finish")
        }
    }

    // MARK: - Diagnostic

    /// « Copier le diagnostic de l'app Claude » (an explicit click): the Claude app's version, whether
    /// access is granted, the counts, then the role and label of its buttons, to the clipboard.
    /// Never a message's text, never the window title; nothing is written to disk.
    func copyDiagnostic() async {
        let app = Self.runningClaudeApp()
        let trusted = Self.accessGranted
        let version = app?.bundleURL.flatMap { Bundle(url: $0)?.infoDictionary?["CFBundleShortVersionString"] as? String }
        var snapshot: ClaudeAppSnapshot? = nil
        if let app, trusted {
            let pid = app.processIdentifier
            let reader = self.reader
            let read: ClaudeAppSnapshot = await withCheckedContinuation { continuation in
                reader.diagnose(pid: pid) { continuation.resume(returning: $0) }
            }
            snapshot = read
        }
        let text = ClaudeAppWatchRules.diagnostic(appVersion: version, running: app != nil, trusted: trusted,
                                                  snapshot: snapshot)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    /// Events only: never a label, a title or a message.
    private func log(_ message: String) {
        appendAppLog("claude-app.log", "Claude app watch: \(message)")
    }
}

// MARK: - ClaudeAppReader: the Accessibility calls, on one serial queue

/// Reads the Claude app's interface off the main thread. The accessibility elements (CF types, not
/// Sendable) never leave `queue`: every property below is touched only there, and only Sendable
/// snapshots go out.
private final class ClaudeAppReader: @unchecked Sendable {
    private let queue = DispatchQueue(label: "ai.klayer.island.claude-app-watch", qos: .utility)

    private var pid: pid_t = 0
    private var app: AXUIElement?
    /// AXManualAccessibility was checked for this run of reads (and is on, by us or already).
    private var treeHeld = false
    /// We set AXManualAccessibility to true (it was not on before): we set it back to false.
    private var treeOnByUs = false
    /// Reads of the watch go on (from the first read to `endReading`).
    private var reading = false
    /// A diagnostic is waiting for the tree or walking it.
    private var diagnosing = false

    /// Set from the main thread at quit, read by the walk at every node: the only property shared
    /// across threads, behind its lock.
    private let quitLock = NSLock()
    private var quitting = false
    private var isQuitting: Bool {
        quitLock.lock()
        defer { quitLock.unlock() }
        return quitting
    }

    /// Roles never entered: their content is text (or a link, an image), never a button.
    private static let leafRoles: Set<String> = ["AXStaticText", "AXTextArea", "AXTextField", "AXLink", "AXImage"]
    private static let manualAccessibility = "AXManualAccessibility"

    func read(pid: pid_t, done: @escaping @Sendable (ClaudeAppSnapshot) -> Void) {
        queue.async { [self] in
            let app = element(for: pid)
            reading = true
            holdTree(app)
            done(walk(app))
        }
    }

    /// Reads stopped: the tree goes back off if we turned it on (Chromium keeps an accessibility
    /// tree while it is on, which costs the Claude app CPU).
    func endReading() {
        queue.async { [self] in
            reading = false
            if !diagnosing { releaseTree() }
        }
    }

    /// The watch went off: the tree goes back off once no diagnostic needs it.
    func release() {
        queue.async { [self] in
            reading = false
            if !diagnosing { releaseTree() }
        }
    }

    /// The island quits: a walk under way stops at its next node, then the tree goes back as it
    /// was, a diagnostic or not, before this returns.
    func quit() {
        quitLock.lock()
        quitting = true
        quitLock.unlock()
        queue.sync { [self] in
            reading = false
            releaseTree()
        }
    }

    /// The Claude app quit: its element and tree went with it.
    func forget() {
        queue.async { [self] in
            app = nil
            pid = 0
            treeHeld = false
            treeOnByUs = false
            reading = false
        }
    }

    /// One read for the diagnostic. When the tree had to be turned on for it, Chromium gets 1 s to
    /// build it first; it goes back off afterwards unless the watch reads.
    func diagnose(pid: pid_t, done: @escaping @Sendable (ClaudeAppSnapshot) -> Void) {
        queue.async { [self] in
            diagnosing = true
            let justTurnedOn = holdTree(element(for: pid))
            let finish: @Sendable () -> Void = { [self] in
                // The element is taken again here: it never leaves the queue's own properties.
                let snapshot = app.map { walk($0) } ?? ClaudeAppSnapshot(complete: false)
                diagnosing = false
                if !reading { releaseTree() }
                done(snapshot)
            }
            if justTurnedOn { queue.asyncAfter(deadline: .now() + 1, execute: finish) } else { finish() }
        }
    }

    // MARK: Queue only

    private func element(for pid: pid_t) -> AXUIElement {
        if let app, self.pid == pid { return app }
        // A new process of the Claude app: the old one's tree is gone with it.
        let created = AXUIElementCreateApplication(pid)
        _ = AXUIElementSetMessagingTimeout(created, ClaudeAppWatchRules.messagingTimeout)
        app = created
        self.pid = pid
        treeHeld = false
        treeOnByUs = false
        return created
    }

    /// AXManualAccessibility on for this run of reads. Returns true when we just turned it on.
    @discardableResult
    private func holdTree(_ app: AXUIElement) -> Bool {
        guard !treeHeld, !isQuitting else { return false }
        treeHeld = true
        let (error, value) = copy(app, Self.manualAccessibility)
        if error == .success, (value as? Bool) == true {
            treeOnByUs = false
            return false
        }
        treeOnByUs = AXUIElementSetAttributeValue(app, Self.manualAccessibility as CFString,
                                                  true as CFTypeRef) == .success
        return treeOnByUs
    }

    private func releaseTree() {
        guard treeHeld else { return }
        treeHeld = false
        if treeOnByUs, let app {
            _ = AXUIElementSetAttributeValue(app, Self.manualAccessibility as CFString, false as CFTypeRef)
        }
        treeOnByUs = false
    }

    /// The buttons of the Claude app's windows, depth-first, bounded. Children are taken last first:
    /// the newest part of the page (the composer and its stop button, a dialog, the last message)
    /// is read before the node bound can cut the oldest messages.
    private func walk(_ app: AXUIElement) -> ClaudeAppSnapshot {
        let started = DispatchTime.now().uptimeNanoseconds
        var snapshot = ClaudeAppSnapshot()
        guard !isQuitting else {
            snapshot.complete = false
            return snapshot
        }
        let (windowsError, windows) = elements(app, "AXWindows")
        switch windowsError {
        case .apiDisabled:
            snapshot.trusted = false
            snapshot.complete = false
            return snapshot
        case .cannotComplete:
            snapshot.complete = false
            return snapshot
        default:
            break
        }
        snapshot.windows = windows.count
        // No window (the app hidden with ⌘H, or its window closed) says nothing, not « no stop
        // button »: an answer under way is not taken for finished.
        guard !windows.isEmpty else {
            snapshot.complete = false
            return snapshot
        }
        // The main window's title, for the alert's line only.
        if let window = element(app, "AXMainWindow") ?? windows.first {
            snapshot.windowTitle = string(window, "AXTitle").value
        }

        var stack: [(AXUIElement, Int)] = windows.reversed().map { ($0, 0) }
        walking: while let (element, depth) = stack.popLast() {
            guard !isQuitting else {
                snapshot.complete = false
                break
            }
            guard snapshot.nodesRead < ClaudeAppWatchRules.maxNodes else {
                snapshot.nodeLimited = true
                break
            }
            snapshot.nodesRead += 1
            _ = AXUIElementSetMessagingTimeout(element, ClaudeAppWatchRules.messagingTimeout)
            let role = string(element, "AXRole")
            switch role.error {
            case .cannotComplete:
                snapshot.complete = false
                break walking
            case .apiDisabled:
                snapshot.trusted = false
                snapshot.complete = false
                break walking
            default:
                break
            }
            guard let roleName = role.value else { continue }
            if ClaudeAppWatchRules.buttonRoles.contains(roleName) {
                let label = ClaudeAppWatchRules.label { attribute in self.string(element, attribute).value }
                snapshot.buttons.append(AXNodeSummary(role: roleName, label: label))
                continue   // a button's children are its own text
            }
            if Self.leafRoles.contains(roleName) { continue }
            guard depth < ClaudeAppWatchRules.maxDepth else {
                snapshot.depthLimited = true
                continue
            }
            let (childrenError, children) = elements(element, "AXChildren")
            if childrenError == .cannotComplete {
                snapshot.complete = false
                break walking
            }
            for child in children { stack.append((child, depth + 1)) }
        }
        snapshot.milliseconds = Int((DispatchTime.now().uptimeNanoseconds - started) / 1_000_000)
        return snapshot
    }

    private func copy(_ element: AXUIElement, _ attribute: String) -> (AXError, CFTypeRef?) {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        return (error, value)
    }

    private func string(_ element: AXUIElement, _ attribute: String) -> (error: AXError, value: String?) {
        let (error, value) = copy(element, attribute)
        return (error, error == .success ? value as? String : nil)
    }

    private func elements(_ element: AXUIElement, _ attribute: String) -> (AXError, [AXUIElement]) {
        let (error, value) = copy(element, attribute)
        guard error == .success else { return (error, []) }
        return (error, value as? [AXUIElement] ?? [])
    }

    private func element(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        let (error, value) = copy(element, attribute)
        guard error == .success, let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        // swiftlint:disable:next force_cast
        return (value as! AXUIElement)
    }
}
