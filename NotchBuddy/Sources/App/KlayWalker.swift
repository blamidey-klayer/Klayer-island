import AppKit
import SwiftUI

// MARK: - Walker view

/// Klay walking home, drawn in the walker's panel by the island's engine (BotEngine), in the
/// idle state (its colour for the glow), posed by the walk every frame (KlayWalker.pose).
struct KlayWalkerView: View {
    let walker: KlayWalker
    let engine: BotEngine

    var body: some View {
        // One frame per display refresh. The panel, and this view with it, goes when he is home:
        // nothing is left drawing.
        TimelineView(.animation) { timeline in
            Canvas { ctx, size in
                // dt from the engine's own clock, as in BotCanvasView.
                _ = timeline.date
                let now = CACurrentMediaTime()
                let dt = KlayMotion.frameDelta(now: now, last: engine.lastTime)
                walker.pose(engine, at: now)
                engine.update(dt: dt)
                engine.draw(context: ctx, size: size)
                engine.drawHandsAndExtras(context: ctx, size: size)
            }
        }
    }
}

// MARK: - Walker

/// Klay walking back into the island: after a drag of Klay, wherever it ends, and on every way
/// home from the desktop (double-click, ⌃⌥D, a request that calls him back). One walker for all.
///
/// He walks in a straight line from where he is to just under his place in the island (under
/// the notch when the island is closed), at walking speed, then hops up into the island Klay's
/// place, shrinking or growing to his size, with the `peek` sound. On arrival the walker's panel
/// is hidden and closed in the same main-actor turn as the island's Klay is shown (he is hidden
/// while `AppState.klayWalkingHome` is true): never two Klays, at worst one frame with none.
/// The plan and the gait are KlayWalk's, tested on Linux (scripts/test-klay-walk.sh).
///
/// CPU: a display link of the walker's own view moves the panel at the display's rate and the
/// panel's TimelineView draws him, both only during the walk; nothing is left running once he is
/// home. A one-shot fallback ends a walk whose link never fired, 1 s after its planned end.
@MainActor
final class KlayWalker {
    static let shared = KlayWalker()
    private init() {}

    /// True from the first step until the island's Klay takes over.
    private(set) var isWalking = false

    private var panel: NSPanel?
    private var engine: BotEngine?
    private var displayLink: CADisplayLink?
    private var plan: KlayWalk.Plan?
    private var start: Double = 0
    /// The walker's width while he walks: his panel's width when he set off.
    private var width: CGFloat = 0
    /// Where he hops to, fixed when the hop starts: the island Klay's place then.
    private var hopTarget: IslandWindowController.KlayHome?
    /// What to do once he is home (DesktopKlayController after a request called him back).
    private var arrived: [() -> Void] = []
    /// Counts the walks: the fallback of one walk never ends a later one.
    private var walkCount = 0

    /// Walks Klay home from `given`, the panel he is drawn in (the drag ghost, the desktop Klay's
    /// panel), from where it is. The walker takes the panel over: its content becomes the walking
    /// Klay and it closes when he is home. `then` runs once he is home and the island's Klay shows.
    func walkHome(panel given: NSPanel?, then: (() -> Void)? = nil) {
        // One Klay at a time: a walk still under way ends at once (it never happens in use, the
        // island's Klay is hidden and cannot be dragged while a walker is out).
        if isWalking { arrive(sound: false) }
        AppState.shared.klayWalkingHome = true
        isWalking = true
        if let then { arrived.append(then) }

        let p = given ?? Self.makePanel()
        p.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 4)
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        p.ignoresMouseEvents = true
        p.alphaValue = 1
        let frame = p.frame
        let from = CGPoint(x: frame.midX, y: frame.midY)
        width = max(1, frame.width)

        let eng = BotEngine()
        // The default state's colour for the glow while he walks; no badge.
        eng.setState(.idle, force: true)
        engine = eng
        let hosting = NSHostingView(rootView: KlayWalkerView(walker: self, engine: eng))
        hosting.frame = CGRect(origin: .zero, size: frame.size)
        hosting.autoresizingMask = [.width, .height]
        p.contentView = hosting
        if !p.isVisible { p.orderFront(nil) }
        panel = p

        let home = Self.island?.klayHome() ?? IslandWindowController.KlayHome.fallback
        let doorstep = KlayWalk.doorstep(place: home.center, notchBottom: home.notchBottom,
                                         walkerWidth: width)
        let route = KlayWalk.Plan(from: from, to: doorstep)
        plan = route
        hopTarget = nil
        start = CACurrentMediaTime()

        // The display link of the walker's own view: one step per frame of the screen he is on.
        displayLink?.invalidate()
        let link = hosting.displayLink(target: WalkerFrames(self), selector: #selector(WalkerFrames.step(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link

        // Should the link never fire, Klay would stay hidden: 1 s after this walk should have
        // ended, hop included, the same walk still on ends at once, without the `peek`.
        walkCount += 1
        let thisWalk = walkCount
        DispatchQueue.main.asyncAfter(deadline: .now() + route.total + 1) { [weak self] in
            guard let self, self.isWalking, self.walkCount == thisWalk else { return }
            self.arrive(sound: false)
        }
        tick()
    }

    /// Ends the walk at once, without the `peek`: a file dragged onto the island brings the drop
    /// canvas and its own Klay, so the walker goes (never two Klays). Nothing when he is home.
    func finishNow() {
        guard isWalking else { return }
        arrive(sound: false)
    }

    /// The walk's pose for the engine at `now` (KlayWalkerView reads it every frame): the gait
    /// while he walks, his rest pose in the hop; his eyes on where he goes.
    func pose(_ engine: BotEngine, at now: Double) {
        guard let plan else {
            engine.walk = nil
            return
        }
        let t = now - start
        engine.walk = plan.hopProgress(at: t) == nil ? plan.pose(at: t) : nil
        // Looking where he walks: the way to the island, up when he is already there.
        let h = plan.heading == .zero ? CGPoint(x: 0, y: 1) : plan.heading
        engine.lookX = h.x
        engine.lookY = h.y
    }

    // MARK: - Frames

    /// One frame of the walk (WalkerFrames, on the display link): the panel follows the plan.
    fileprivate func tick() {
        guard let plan, let panel else { return }
        let t = CACurrentMediaTime() - start
        guard let u = plan.hopProgress(at: t) else {
            place(panel, center: plan.position(at: t), width: width)
            return
        }
        if hopTarget == nil {
            // The hop starts: his place in the island now (it may have opened or closed meanwhile).
            hopTarget = Self.island?.klayHome() ?? IslandWindowController.KlayHome.fallback
            engine?.squash()
        }
        guard let home = hopTarget else { return }
        // From where the walk left him: the doorstep, or where he was dropped when there was no walk.
        let f = KlayWalk.hop(u, from: plan.hopStart, to: home.center, fromWidth: width,
                             toWidth: home.shown ? home.width : 0, fades: !home.shown)
        place(panel, center: f.center, width: max(1, f.width))
        panel.alphaValue = f.alpha
        if u >= 1 { arrive(sound: true) }
    }

    private func place(_ panel: NSPanel, center c: CGPoint, width w: CGFloat) {
        panel.setFrame(NSRect(x: c.x - w / 2, y: c.y - w / 2, width: w, height: w), display: true)
    }

    /// He is home: the `peek` sound (unless `sound` is false), the display link stops, the
    /// walker's panel is hidden and closed and the island's Klay shown in this same main-actor
    /// turn, so the two never show together; then what waited for him runs.
    private func arrive(sound: Bool) {
        displayLink?.invalidate()
        displayLink = nil
        if sound { SoundEngine.shared.play("peek") }
        let leaving = panel
        panel = nil
        engine = nil
        plan = nil
        hopTarget = nil
        isWalking = false
        leaving?.alphaValue = 0
        leaving?.close()
        AppState.shared.klayWalkingHome = false
        let waiting = arrived
        arrived = []
        waiting.forEach { $0() }
    }

    // MARK: - Helpers

    private static var island: IslandWindowController? {
        (NSApp.delegate as? AppDelegate)?.islandController
    }

    /// A panel for a walker that has none (never in use: the drag ghost and the desktop Klay
    /// always hand theirs over), at the drag ghost's size under the pointer.
    private static func makePanel() -> NSPanel {
        let s: CGFloat = KlaySize.canvasWidth(diameter: 40)
        let m = NSEvent.mouseLocation
        let p = NSPanel(contentRect: NSRect(x: m.x - s / 2, y: m.y - s / 2, width: s, height: s),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = false
        return p
    }
}

// MARK: - Display link target

/// The display link's target (it needs an Objective-C object): one walker step per frame of the
/// screen the walker is on. The link retains it; invalidating the link at the end of the walk
/// releases both.
@MainActor
private final class WalkerFrames: NSObject {
    private weak var walker: KlayWalker?

    init(_ walker: KlayWalker) {
        self.walker = walker
    }

    @objc func step(_ link: CADisplayLink) {
        walker?.tick()
    }
}
