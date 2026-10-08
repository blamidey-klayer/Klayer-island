import Foundation

/// Pure 4-state FSM for island open/close logic.
/// No AppKit / AppState dependencies — communicates via `onTransition` and `onGreet`.
///
/// The island opens on hover only, never on a click (spec §4): the pointer near the notch
/// brings Klay out (`petit`) with a greeting, resting on the notch opens it after
/// `hoverOpenDelay`, and a click outside closes it.
@MainActor
final class IslandStateMachine {

    enum State: Equatable {
        case hidden   // island invisible (notch size)
        case petit    // compact island (notch + ears)
        case home     // expanded, overview
        case klayer   // expanded, greeting animation
    }

    private(set) var state: State = .hidden

    /// Fired on every transition: (from, to)
    var onTransition: ((State, State) -> Void)?

    /// Fired when the pointer approaches the notch while the island is hidden or compact,
    /// once per approach: not again until `pointerFar()` has been called.
    var onGreet: (() -> Void)?

    /// When non-nil and returns true (a pending permission or question), timers and
    /// pointer-leave never collapse or hide the island.
    var isHeldOpen: (() -> Bool)?

    /// When the open island folds on the auto-close timer (the user clicked inside, then the
    /// pointer left), else nil: the countdown bar draws only from it. Never set for the short
    /// hover grace; cleared when that fold is cancelled, happens, or is refused (a request holds).
    private(set) var foldDeadline: Date? {
        didSet { if foldDeadline != oldValue { onFoldDeadline?(foldDeadline) } }
    }

    /// Fired when `foldDeadline` changes.
    var onFoldDeadline: ((Date?) -> Void)?

    /// home → petit delay (seconds) once the user clicked inside the open island,
    /// kept in sync with the auto-close preference.
    var homeToPetitDelay: TimeInterval = 15 {
        didSet {
            guard homeToPetitDelay != oldValue, state == .home,
                  homeClose == .autoClose, homeCollapseWork != nil else { return }
            scheduleHomeCollapse()
        }
    }
    /// petit → hidden delay (seconds) once the pointer is away from the notch. Override for debug.
    var petitToHiddenDelay: TimeInterval = 60
    /// klayer → petit delay after greeting animation ends (no hover). ~0.6s syncs with canvas collapse.
    var greetAutoCollapseDelay: TimeInterval = 0.6
    /// klayer → petit delay when mouse is hovering over the greeting.
    var greetHoverCollapseDelay: TimeInterval = 10
    /// How long the pointer rests on the notch before the island opens.
    var hoverOpenDelay: TimeInterval = 0.25
    /// Grace period after the pointer leaves an island opened by hovering (no flicker at the edge).
    var hoverCloseDelay: TimeInterval = 0.6

    /// How the open island folds once the pointer leaves it.
    private enum HomeClose {
        /// Opened by hovering: folds `hoverCloseDelay` after the pointer leaves.
        case hover
        /// Opened by the app (alert, finished session): no timer until the pointer has been on it.
        case untilHovered
        /// The user clicked inside: folds `homeToPetitDelay` after the pointer leaves.
        case autoClose
    }
    private var homeClose: HomeClose = .hover

    /// The pointer is around the notch, between `pointerNear()` and `pointerFar()`.
    private var pointerIsNear = false
    /// The pointer is on the island, between `mouseEntered()` and `mouseLeft()`.
    private var pointerIsOver = false

    private var petitHideWork: DispatchWorkItem?
    private var hoverOpenWork: DispatchWorkItem?
    private var homeCollapseWork: DispatchWorkItem?
    private var greetCollapseWork: DispatchWorkItem?

    // MARK: – Inputs

    /// App launched or debug "launch greeting"
    func launch() {
        cancelTimers()
        transition(to: .klayer)
    }

    /// The pointer came near the notch: Klay comes out (hidden → petit) and greets, once per
    /// approach, also when Klay is already out. The island never opens from here, only resting
    /// on the notch opens it. While the pointer stays near, the compact island does not hide.
    func pointerNear() {
        let newApproach = !pointerIsNear
        pointerIsNear = true
        switch state {
        case .hidden:
            // Held while hidden: the app expanded the island without telling the FSM
            // (see `mouseEntered()`), so do not fold it to petit.
            guard newApproach, isHeldOpen?() != true else { return }
            cancelTimers()
            transition(to: .petit)
            if state == .petit { onGreet?() }
        case .petit:
            cancelPetitHide()
            if newApproach { onGreet?() }
        case .home, .klayer:
            break
        }
    }

    /// The pointer moved away from the notch. A compact island with no pending request
    /// hides after `petitToHiddenDelay`; the next `pointerNear()` greets again.
    func pointerFar() {
        pointerIsNear = false
        guard state == .petit, isHeldOpen?() != true else { return }
        schedulePetitHide()
    }

    /// The pointer is on the island. From hidden or petit, Klay peeks at once and the island
    /// opens after `hoverOpenDelay` if the pointer is still there (`mouseLeft()` cancels it).
    func mouseEntered() {
        pointerIsOver = true
        switch state {
        case .hidden:
            if isHeldOpen?() == true {
                // Island already expanded by an external call — sync FSM state without transition
                cancelTimers()
                homeClose = .hover
                state = .home
            } else {
                cancelTimers()
                transition(to: .petit)
                scheduleHoverOpen()
            }
        case .petit:
            cancelPetitHide()
            scheduleHoverOpen()
        case .home:
            cancelHomeCollapse()
            // An island the app opened on its own has now been seen: leaving it folds it.
            if homeClose == .untilHovered { homeClose = .hover }
        case .klayer:
            // Mouse hovering during greeting — cancel short auto-collapse, extend to hover delay
            scheduleGreetCollapse(delay: greetHoverCollapseDelay)
        }
    }

    /// The pointer left the island.
    func mouseLeft() {
        pointerIsOver = false
        cancelHoverOpen()
        switch state {
        case .hidden:
            break
        case .petit:
            // Klay stays out while the pointer is still near the notch; `pointerFar()` hides it.
            if !pointerIsNear { schedulePetitHide() }
        case .home:
            guard isHeldOpen?() != true, homeClose != .untilHovered else { return }
            scheduleHomeCollapse()
        case .klayer:
            if isHeldOpen?() != true {
                // Interrupt greeting immediately → compact (overrides 10s auto-collapse)
                greetCollapseWork?.cancel(); greetCollapseWork = nil
                transition(to: .petit)
            }
        }
    }

    /// A click landed outside the open island (or Escape): it closes, or folds to petit when
    /// a request is pending (Klay keeps its badge and hovering reopens it). A request that
    /// arrived during the launch greeting folds the same way; otherwise the greeting plays
    /// to its end. Nothing happens to a hidden or compact island.
    func clickedOutside() {
        switch state {
        case .home:
            cancelTimers()
            transition(to: isHeldOpen?() == true ? .petit : .hidden)
        case .klayer:
            guard isHeldOpen?() == true else { return }
            cancelTimers()
            transition(to: .petit)
        case .hidden, .petit:
            break
        }
    }

    /// The user clicked inside the open island: once the pointer leaves, it folds after the
    /// normal auto-close delay instead of the short hover grace, so typing in the chat after
    /// moving the pointer away does not fold it.
    func userInteracted() {
        guard state == .home else { return }
        homeClose = .autoClose
        if homeCollapseWork != nil { scheduleHomeCollapse() }
    }

    /// The app hid the island on its own (e.g. `AppState.syncMode()` when the last
    /// task ends). Mirror it without side effects, so the next hover peeks again
    /// instead of being swallowed by a FSM that still thinks the island is `.petit`.
    func hiddenExternally() {
        guard state == .petit else { return }
        cancelTimers()
        state = .hidden
    }

    /// The compact island is on screen while the FSM has it hidden: something showed it outside
    /// the FSM. Mirror it as petit without side effects and start the hide timer, so Klay hides
    /// 60 s after the pointer is away instead of staying out for good (spec §4, rule 2).
    func shownExternally() {
        guard state == .hidden else { return }
        cancelTimers()
        state = .petit
        if !pointerIsNear && !pointerIsOver { schedulePetitHide() }
    }

    /// The app expanded the island externally (an alert, a finished session).
    /// Sync state to `.home` without firing `onTransition` and start no timer: the island
    /// stays open until the pointer has been on it and left, or a click lands outside.
    /// Also during the launch greeting: the view replaces the greeting, so its timers go and the
    /// island follows the same rule (the greeting canvas still posts its end when it leaves).
    func openedExternally() {
        cancelTimers()
        homeClose = .untilHovered
        state = .home
    }

    /// The view the app opened went stale (the session of a finished view started a new turn):
    /// it folds to petit, unless the pointer is on the island or the user clicked in it (the view
    /// is in use), or a request holds the island.
    func externalViewWentStale() {
        guard state == .home, !pointerIsOver, homeClose != .autoClose, isHeldOpen?() != true else { return }
        cancelTimers()
        transition(to: .petit)
    }

    /// The app folded the island itself (Escape, Settings, OK button, auto-close).
    /// Move to `.petit` right away so hover keeps working; waiting for the
    /// 15 s home timer left the island compact on screen while the FSM still said `.home`.
    func collapse() {
        guard state == .home || state == .klayer else { return }
        cancelTimers()
        transition(to: .petit)
    }

    /// Greeting animation finished (called at T.end ≈ 4.60 s).
    /// Schedules auto-collapse. Does not override a longer hover timer already running.
    func greetComplete() {
        guard state == .klayer else { return }
        // If mouse entered before this fires (hover timer already running), don't override it
        if greetCollapseWork == nil {
            scheduleGreetCollapse(delay: greetAutoCollapseDelay)
        }
    }

    /// Non-alert work event: show compact from hidden (HookServer reveal)
    func reveal() {
        guard state == .hidden else { return }
        cancelTimers()
        transition(to: .petit)
        schedulePetitHide()
    }

    // MARK: – Timers
    // Each work item checks the state it expects before acting, so a timer that outlived
    // the input which scheduled it never fires a transition from a stale state.

    private func scheduleGreetCollapse(delay: TimeInterval) {
        greetCollapseWork?.cancel()
        let item = DispatchWorkItem { [weak self] in
            // A request that arrived during the greeting stays open until it is answered.
            guard let self, self.state == .klayer, self.isHeldOpen?() != true else { return }
            self.transition(to: .petit)
        }
        greetCollapseWork = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    private func scheduleHoverOpen() {
        hoverOpenWork?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self, self.state == .petit, self.pointerIsOver else { return }
            self.cancelTimers()
            self.homeClose = .hover
            self.transition(to: .home)
        }
        hoverOpenWork = item
        DispatchQueue.main.asyncAfter(deadline: .now() + hoverOpenDelay, execute: item)
    }

    private func schedulePetitHide() {
        petitHideWork?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self, self.state == .petit, !self.pointerIsNear, !self.pointerIsOver,
                  self.isHeldOpen?() != true else { return }
            self.transition(to: .hidden)
        }
        petitHideWork = item
        DispatchQueue.main.asyncAfter(deadline: .now() + petitToHiddenDelay, execute: item)
    }

    private func scheduleHomeCollapse() {
        homeCollapseWork?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            // Fired: no fold is pending any more, whether it happens or not.
            self.homeCollapseWork = nil
            self.foldDeadline = nil
            guard self.state == .home, !self.pointerIsOver,
                  self.isHeldOpen?() != true else { return }
            self.transition(to: .petit)
        }
        homeCollapseWork = item
        let delay = homeClose == .autoClose ? homeToPetitDelay : hoverCloseDelay
        foldDeadline = homeClose == .autoClose ? Date().addingTimeInterval(delay) : nil
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    private func cancelPetitHide() {
        petitHideWork?.cancel(); petitHideWork = nil
    }

    private func cancelHoverOpen() {
        hoverOpenWork?.cancel(); hoverOpenWork = nil
    }

    private func cancelHomeCollapse() {
        homeCollapseWork?.cancel(); homeCollapseWork = nil
        foldDeadline = nil
    }

    func cancelTimers() {
        cancelPetitHide()
        cancelHoverOpen()
        cancelHomeCollapse()
        greetCollapseWork?.cancel(); greetCollapseWork = nil
    }

    private func transition(to new: State) {
        guard new != state else { return }
        let old = state
        if new != .home { foldDeadline = nil }
        state = new
        onTransition?(old, new)
    }

}
