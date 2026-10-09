import AppKit
import SwiftUI
import Combine

// MARK: - Desktop bot view state

/// Observable bridge so DesktopKlayController can update view-level state without
/// coupling to SwiftUI @State.
@MainActor
final class DesktopBotViewState: ObservableObject {
    /// Display rate while awake; 10 fps when sleeping (saves energy).
    @Published var isSleeping: Bool = false
    /// Pause entirely (screen sleep / lock).
    @Published var paused: Bool = false
    /// Bot center in the same coord space as AppState.mousePosition (DesktopSpace, y-down).
    /// Updated every poll frame; Canvas reads it inside TimelineView — @Published not needed.
    var lookOrigin: CGPoint = .zero
}

// MARK: - Desktop bot view

/// Full Klay character rendered inside the desktop floating panel.
struct DesktopBotView: View {
    @ObservedObject var appState: AppState
    /// Engine owned by DesktopKlayController; controller calls methods on it directly.
    let engine: BotEngine
    @ObservedObject var viewState: DesktopBotViewState

    var body: some View {
        // Awake, one frame per display refresh so the springs and the gaze stay fluid; asleep,
        // 10 fps; paused while the screen sleeps or is locked.
        TimelineView(.animation(
            minimumInterval: viewState.isSleeping ? 1.0 / 10.0 : nil,
            paused: viewState.paused
        )) { timeline in
            Canvas { ctx, size in
                // dt from the engine's own clock, as in BotCanvasView.
                _ = timeline.date
                let dt = KlayMotion.frameDelta(now: CACurrentMediaTime(), last: engine.lastTime)

                // Eye tracking based on the panel's own screen position
                engine.lookX = tanh((appState.mousePosition.x - viewState.lookOrigin.x) / 260)
                engine.lookY = -tanh((appState.mousePosition.y - viewState.lookOrigin.y) / 200)

                // Dance when music plays (same rules as compact mode)
                let dancing: Bool = {
                    let spotify = SpotifyController.shared.isPlaying
                        && appState.activeIntegrations.contains(SpotifyController.pillId)
                    guard spotify else { return false }
                    let allowed: Set<BotState> = [.idle, .working, .thinking, .searching, .finished]
                    return allowed.contains(appState.effectiveState)
                }()
                engine.setDancing(dancing)
                engine.update(dt: dt)

                var c = ctx
                engine.applyDance(&c, size: size)
                // Klay (glow, limbs, glyph, eyes) spins as a whole on a roll; the
                // badge and particles are drawn on top and do not spin.
                engine.draw(context: c, size: size)
                engine.drawHandsAndExtras(context: c, size: size)
            }
        }
        .onChange(of: appState.effectiveState) { _, newState in
            engine.setState(newState)
        }
        .onAppear {
            engine.setState(appState.effectiveState, force: true)
        }
    }
}

// MARK: - Desktop Klay controller

/// Manages the "Klay on the desktop" floating panel.
///
/// Life cycle:
/// - **Sent out**: ⌃⌥D (`flyOutOrHome()`) → `launchFlyIfNeeded()`. A drag of Klay no longer leaves
///   him on the desktop: he walks back into the island (KlayWalker).
/// - **Launch restore**: `AppDelegate` observes `.greetComplete` → `launchFlyIfNeeded()`.
/// - **Alert**: `pendingApproval`/`pendingQuestion` goes non-nil → surprised emote →
///   `retractForAlert()` (he walks home, flag stays true) → both nil → `launchFlyIfNeeded()`.
/// - **User sends him home**: double-click, ⌃⌥D again, a drop on the island → `walkHome()`: he
///   walks back into the island (KlayWalker), the desktop mode ends.
@MainActor
final class DesktopKlayController {
    static let shared = DesktopKlayController()
    private init() {
        observeScreenSleep()
        observeScreenLock()
        observeAlerts()   // permanent — lives for the lifetime of the singleton
    }

    private var panel: NSPanel?
    private var engine: BotEngine?
    private var viewState: DesktopBotViewState?
    private var frameTimer: Timer?

    // Alert state machine
    private var phase: DesktopPhase = .home

    // Desktop drag repositioning
    private var isDragging = false
    private var dragMouseStart: NSPoint = .zero
    private var dragOriginAtStart: NSPoint = .zero

    // Deferred single-click slap
    private var pendingSlapWorkItem: DispatchWorkItem?

    // Sleep detection
    private var lastAgentActive: Date = .distantPast
    private var isSleeping = false

    // Pointer on Klay (hover): he perks up, widens his eyes and leans towards it, as on the
    // island (IslandWindowController.botHoverIn / botHoverOut).
    private var hoveringBody = false

    // Screen sleep / lock
    private var screenSleeping = false

    // Lifecycle subscriptions (cleared on retractForAlert + fullTearDown)
    private var cancellables: Set<AnyCancellable> = []
    // Alert subscription — permanent, only released with the singleton
    private var alertSubscription: AnyCancellable?

    // Event monitors
    private var mouseDownMonitor:    Any?
    private var mouseDraggedMonitor: Any?
    private var mouseUpMonitor:      Any?
    private var globalMouseUpMonitor: Any?

    // UserDefaults keys
    private static let posXKey    = "desktopKlayX"
    private static let posYKey    = "desktopKlayY"
    private static let enabledKey = "klayOnDesktop"

    static let panelSize: CGFloat = DesktopKlayLogic.panelSize

    /// True for the desktop Klay's own panel: a click there is not a click outside the island.
    func owns(_ window: NSWindow) -> Bool {
        window === panel
    }

    // MARK: - Keyboard shortcut toggle (⌃⌥D)

    /// Fly Klay to the desktop if not there, or walk him back if he is. Nothing while a walker
    /// is out: one Klay at a time.
    func flyOutOrHome() {
        guard !KlayWalker.shared.isWalking else { return }
        if phase == .home {
            UserDefaults.standard.set(true, forKey: DesktopKlayController.enabledKey)
            launchFlyIfNeeded()
        } else if phase == .onDesktop {
            walkHome()
        }
    }

    // MARK: - Launch fly (app-start restore or alert return)

    /// Fly a new panel from the notch to the saved desktop position.
    /// Called by AppDelegate after `.greetComplete`, and by the alert-return path.
    func launchFlyIfNeeded() {
        guard UserDefaults.standard.bool(forKey: DesktopKlayController.enabledKey) else { return }
        guard phase == .home else { return }
        guard panel == nil else { return }
        // A walker is out (a drag of the island's Klay): he flies out once that one is home.
        if KlayWalker.shared.isWalking {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.launchFlyIfNeeded()
            }
            return
        }
        // Alert active: don't fly yet — park in .atNotchForAlert so observeAlerts restores us when it clears
        if AppState.shared.pendingApproval != nil || AppState.shared.pendingQuestion != nil {
            phase = .atNotchForAlert
            return
        }

        phase = .flyingOut
        let s = DesktopKlayController.panelSize
        let screen = IslandWindowController.islandScreen()
        let startOrigin = NSPoint(x: screen.frame.midX - s/2, y: screen.frame.maxY - s)
        let target = loadSavedPosition()

        let p = makeBlankPanel()
        p.setFrame(NSRect(origin: startOrigin, size: CGSize(width: s, height: s)), display: false)

        let eng = BotEngine()
        eng.setState(AppState.shared.effectiveState, force: true)
        self.engine = eng
        hoveringBody = false

        let vs = DesktopBotViewState()
        vs.lookOrigin = lookOriginFor(panel: p)
        vs.paused = screenSleeping
        self.viewState = vs

        let hosting = NSHostingView(rootView:
            DesktopBotView(appState: AppState.shared, engine: eng, viewState: vs))
        hosting.frame = CGRect(x: 0, y: 0, width: s, height: s)
        hosting.autoresizingMask = [.width, .height]
        // The panel is framed by hand (its size, its moves): no size constraints from SwiftUI.
        hosting.sizingOptions = []
        p.contentView = hosting
        p.alphaValue = 0
        p.orderFront(nil)

        AppState.shared.klayOnDesktop = true

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.45
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            p.animator().alphaValue = 1
            p.animator().setFrame(NSRect(origin: target, size: CGSize(width: s, height: s)), display: true)
        }, completionHandler: {
            Task { @MainActor in
                self.panel = p
                self.phase = .onDesktop
                UserDefaults.standard.set(true, forKey: DesktopKlayController.enabledKey)
                self.persistPosition()
                // Alert may have fired during the flight (observeAlerts skipped: phase was .flyingOut)
                let alertNow = AppState.shared.pendingApproval != nil || AppState.shared.pendingQuestion != nil
                if DesktopKlayLogic.shouldRetractOnLanding(alertActive: alertNow) {
                    self.engine?.triggerEmote(.surprised)
                    self.phase = .retracting
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
                        guard let self else { return }
                        switch self.phase {
                        case .retracting:              self.retractForAlert()
                        case .alertResolvedDuringRetract: self.phase = .home; self.launchFlyIfNeeded()
                        default: break
                        }
                    }
                } else {
                    self.startPolling()
                    self.addEventMonitors()
                    self.observeLifecycle()
                }
            }
        })
    }

    // MARK: - Walk home (user-initiated: double-click, ⌃⌥D, drop on the island)

    /// Klay walks back into the island (KlayWalker) and the desktop mode ends.
    func walkHome() {
        guard let p = releasePanel() else { return }
        phase = .home
        UserDefaults.standard.set(false, forKey: DesktopKlayController.enabledKey)
        KlayWalker.shared.walkHome(panel: p)
        AppState.shared.klayOnDesktop = false
    }

    // MARK: - Retract for alert (he walks home; comes back after the alert resolves)

    /// Klay walks home so the island's Klay shows the alert. The UserDefaults flag stays true so
    /// `launchFlyIfNeeded` restores him once the alert is dismissed.
    private func retractForAlert() {
        guard let p = releasePanel() else { return }
        KlayWalker.shared.walkHome(panel: p) { [weak self] in
            guard let self else { return }
            if self.phase == .alertResolvedDuringRetract {
                self.phase = .home
                self.launchFlyIfNeeded()
            } else {
                self.phase = .atNotchForAlert
            }
        }
        // The walker keeps the island's Klay hidden until he is home.
        AppState.shared.klayOnDesktop = false
    }

    /// Stops the desktop Klay (polling, mouse monitors, subscriptions) and hands his panel over,
    /// to the walker: the controller keeps nothing of it.
    private func releasePanel() -> NSPanel? {
        guard let p = panel else { return nil }
        stopPolling()
        removeEventMonitors()
        cancellables.removeAll()
        pendingSlapWorkItem?.cancel()
        panel = nil
        engine = nil
        viewState = nil
        isDragging = false
        isSleeping = false
        return p
    }

    // MARK: - Uninstall (immediate, no animation)

    func uninstall() {
        stopPolling()
        removeEventMonitors()
        fullTearDown()
    }

    private func fullTearDown() {
        phase = .home
        cancellables.removeAll()
        pendingSlapWorkItem?.cancel()
        panel?.close()
        panel = nil
        engine = nil
        viewState = nil
        isDragging = false
        isSleeping = false
        AppState.shared.klayOnDesktop = false
        UserDefaults.standard.set(false, forKey: DesktopKlayController.enabledKey)
    }

    // MARK: - Panel factory

    private func makeBlankPanel() -> NSPanel {
        let p = NSPanel(contentRect: .zero,
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = false
        return p
    }

    // MARK: - Lifecycle observation (active while panel is live on desktop)

    private func observeLifecycle() {
        cancellables.removeAll()

        // effectiveState → .finished: joy jump (only when on desktop, not retracting)
        Publishers.CombineLatest(AppState.shared.$stateOverride, AppState.shared.$tasks)
            .map { _, _ in AppState.shared.effectiveState }
            .removeDuplicates()
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newState in
                guard let self, self.phase == .onDesktop else { return }
                if newState == .finished {
                    self.engine?.triggerEmote(.happy, duration: 1.2, silent: true)
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Alert observation (permanent — installed once at init)

    private func observeAlerts() {
        alertSubscription = Publishers.CombineLatest(
            AppState.shared.$pendingApproval,
            AppState.shared.$pendingQuestion
        )
        .map { a, q in a != nil || q != nil }
        .removeDuplicates()
        .dropFirst()
        .receive(on: DispatchQueue.main)
        .sink { [weak self] alertActive in
            guard let self else { return }

            if alertActive {
                guard self.phase == .onDesktop else { return }
                self.engine?.triggerEmote(.surprised)
                self.phase = .retracting
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
                    guard let self else { return }
                    switch self.phase {
                    case .retracting:
                        self.retractForAlert()
                    case .alertResolvedDuringRetract:
                        // Alert cleared before animation started — no need to retract
                        self.phase = .home
                        self.launchFlyIfNeeded()
                    default:
                        break
                    }
                }
            } else {
                switch self.phase {
                case .atNotchForAlert:
                    self.phase = .home
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                        self?.launchFlyIfNeeded()
                    }
                case .retracting:
                    // Alert resolved while waiting to retract — mark it
                    self.phase = .alertResolvedDuringRetract
                default:
                    break
                }
            }
        }
    }

    // MARK: - 60 Hz polling (only while panel is live)

    private func startPolling() {
        frameTimer?.invalidate()
        frameTimer = Timer.scheduledTimer(withTimeInterval: 1.0/60.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in self.pollFrame() }
        }
        RunLoop.main.add(frameTimer!, forMode: .common)
    }

    private func stopPolling() {
        frameTimer?.invalidate()
        frameTimer = nil
    }

    private func pollFrame() {
        guard let p = panel else { return }
        let mouse = NSEvent.mouseLocation
        let pf    = p.frame
        let local = CGPoint(x: mouse.x - pf.minX, y: mouse.y - pf.minY)
        let s     = DesktopKlayController.panelSize

        // Toggle click-through
        let overBody   = DesktopKlayLogic.isOverBody(localPoint: local, panelSize: s)
        let needsMouse = overBody || isDragging
        if p.ignoresMouseEvents == needsMouse {
            p.ignoresMouseEvents = !needsMouse
        }

        // Hover: a blink and eyes ×1.08 as the pointer arrives; the engine reads tgEs above 1
        // as "pointer on me" (perk-up, lean, closer gaze).
        if overBody != hoveringBody {
            hoveringBody = overBody
            if overBody { engine?.blink() }
            engine?.tgEs = overBody ? 1.08 : 1
        }

        // Update eye-tracking origin every frame
        viewState?.lookOrigin = lookOriginFor(panel: p)

        // Sleep detection
        let agentActive = AppState.shared.effectiveState != .idle &&
                          AppState.shared.effectiveState != .sleeping
        if agentActive { lastAgentActive = .now }
        let dist     = hypot(mouse.x - pf.midX, mouse.y - pf.midY)
        let interval = Date.now.timeIntervalSince(lastAgentActive)
        let shouldSleep = DesktopKlayLogic.shouldSleep(lastAgentActiveInterval: interval,
                                                         mouseDistanceToPanelCenter: dist)
        if shouldSleep != isSleeping {
            isSleeping = shouldSleep
            viewState?.isSleeping = shouldSleep
            engine?.setState(isSleeping ? .sleeping : AppState.shared.effectiveState)
        }
    }

    // MARK: - Event monitors

    private func addEventMonitors() {
        mouseDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            guard let self else { return event }
            MainActor.assumeIsolated {
                guard event.window === self.panel else { return }
                self.dragMouseStart    = NSEvent.mouseLocation
                self.dragOriginAtStart = self.panel?.frame.origin ?? .zero
            }
            return event
        }

        mouseDraggedMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDragged) { [weak self] event in
            guard let self else { return event }
            MainActor.assumeIsolated {
                let m = NSEvent.mouseLocation
                if !self.isDragging {
                    let dist = hypot(m.x - self.dragMouseStart.x, m.y - self.dragMouseStart.y)
                    guard self.dragMouseStart != .zero, dist > 3 else { return }
                    self.isDragging = true
                }
                guard let p = self.panel else { return }
                let dx = m.x - self.dragMouseStart.x
                let dy = m.y - self.dragMouseStart.y
                let newOrigin = self.clampToVisibleFrame(
                    NSPoint(x: self.dragOriginAtStart.x + dx, y: self.dragOriginAtStart.y + dy))
                p.setFrameOrigin(newOrigin)
                self.viewState?.lookOrigin = self.lookOriginFor(panel: p)
            }
            return event
        }

        // Local mouseUp (cursor still within panel)
        mouseUpMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp) { [weak self] event in
            guard let self else { return event }
            MainActor.assumeIsolated {
                let wasDragging = self.isDragging
                self.isDragging = false
                self.dragMouseStart = .zero
                if wasDragging {
                    self.handleDragRelease(at: NSEvent.mouseLocation)
                } else if event.window === self.panel {
                    self.handleClick(clickCount: event.clickCount)
                }
            }
            return event
        }

        // Global mouseUp (cursor moved outside panel during drag)
        globalMouseUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isDragging else { return }
                self.isDragging = false
                self.dragMouseStart = .zero
                self.handleDragRelease(at: NSEvent.mouseLocation)
            }
        }

    }

    // MARK: - Click / drag helpers

    private func handleClick(clickCount: Int) {
        if clickCount >= 2 {
            pendingSlapWorkItem?.cancel()
            walkHome()
        } else {
            pendingSlapWorkItem?.cancel()
            let item = DispatchWorkItem { [weak self] in self?.engine?.slap() }
            pendingSlapWorkItem = item
            DispatchQueue.main.asyncAfter(deadline: .now() + NSEvent.doubleClickInterval, execute: item)
        }
    }

    private func handleDragRelease(at mouse: NSPoint) {
        let islandController = (NSApp.delegate as? AppDelegate)?.islandController
        let inNotchZone = islandController?.window?.frame.contains(mouse) == true

        if inNotchZone {
            walkHome()
            return
        }

        if let ctx = islandController?.windowContextAtPoint(mouse) {
            // Attach window context; Klay returns to pre-drag position
            AppState.shared.promptContext = ctx
            SoundEngine.shared.play("approve")
            engine?.triggerEmote(.happy, duration: 0.6, silent: true)
            let origin = clampToVisibleFrame(dragOriginAtStart)
            panel?.setFrameOrigin(origin)
            persistPosition()
            islandController?.expandOutsideFSM(to: .prompt)
            return
        }
        // Elsewhere: keep new position
        persistPosition()
    }

    private func removeEventMonitors() {
        if let m = mouseDownMonitor     { NSEvent.removeMonitor(m); mouseDownMonitor     = nil }
        if let m = mouseDraggedMonitor  { NSEvent.removeMonitor(m); mouseDraggedMonitor  = nil }
        if let m = mouseUpMonitor       { NSEvent.removeMonitor(m); mouseUpMonitor       = nil }
        if let m = globalMouseUpMonitor { NSEvent.removeMonitor(m); globalMouseUpMonitor = nil }
    }

    // MARK: - Screen sleep / wake

    private func observeScreenSleep() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.screenSleeping = true
                self?.viewState?.paused = true
            }
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.screenSleeping = false
                self?.viewState?.paused = false
            }
        }
    }

    // MARK: - Screen lock / unlock

    private func observeScreenLock() {
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.screenIsLocked"), object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.screenSleeping = true
                self?.viewState?.paused = true
            }
        }
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.screenSleeping = false
                self?.viewState?.paused = false
            }
        }
    }

    // MARK: - Position helpers

    private func lookOriginFor(panel: NSPanel) -> CGPoint {
        DesktopKlayLogic.lookOrigin(
            panelMinX:  panel.frame.minX,
            panelMinY:  panel.frame.minY,
            desktopTop: IslandWindowController.desktopTop,
            panelSize:  DesktopKlayController.panelSize)
    }

    private func clampToVisibleFrame(_ origin: NSPoint) -> NSPoint {
        let screen = NSScreen.screens.min(by: {
            let da = hypot(origin.x - $0.visibleFrame.midX, origin.y - $0.visibleFrame.midY)
            let db = hypot(origin.x - $1.visibleFrame.midX, origin.y - $1.visibleFrame.midY)
            return da < db
        }) ?? NSScreen.main!
        let pt = DesktopKlayLogic.clampOrigin(
            CGPoint(x: origin.x, y: origin.y),
            panelSize:    DesktopKlayController.panelSize,
            visibleFrame: screen.visibleFrame,
            margin:       DesktopKlayLogic.clampMargin)
        return NSPoint(x: pt.x, y: pt.y)
    }

    private func loadSavedPosition() -> NSPoint {
        let ud = UserDefaults.standard
        guard ud.object(forKey: DesktopKlayController.posXKey) != nil else {
            return defaultPosition()
        }
        let x = CGFloat(ud.double(forKey: DesktopKlayController.posXKey))
        let y = CGFloat(ud.double(forKey: DesktopKlayController.posYKey))
        return clampToVisibleFrame(NSPoint(x: x, y: y))
    }

    private func defaultPosition() -> NSPoint {
        let s      = DesktopKlayController.panelSize
        let margin = DesktopKlayLogic.clampMargin
        let vf     = (NSScreen.main ?? NSScreen.screens[0]).visibleFrame
        return NSPoint(x: vf.maxX - s - margin, y: vf.minY + margin)
    }

    private func persistPosition() {
        guard let p = panel else { return }
        let o = p.frame.origin
        UserDefaults.standard.set(Double(o.x), forKey: DesktopKlayController.posXKey)
        UserDefaults.standard.set(Double(o.y), forKey: DesktopKlayController.posYKey)
    }
}
