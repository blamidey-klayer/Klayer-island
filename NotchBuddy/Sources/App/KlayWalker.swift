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
/// the notch when the island is closed), at walking speed, then hops up and shrinks into the
/// island Klay's place and size, with the `peek` sound; the island's Klay then shows (it is hidden
/// while `AppState.klayWalkingHome` is true) and the walker's panel closes. The plan and the gait
/// are KlayWalk's, tested on Linux (scripts/test-klay-walk.sh).
///
/// CPU: a 60 Hz timer moves the panel and the panel's TimelineView draws him, both only during
/// the walk; nothing is left running once he is home.
@MainActor
final class KlayWalker {
    static let shared = KlayWalker()
    private init() {}

    /// True from the first step until the island's Klay takes over.
    private(set) var isWalking = false

    private var panel: NSPanel?
    private var engine: BotEngine?
    private var timer: Timer?
    private var plan: KlayWalk.Plan?
    private var start: Double = 0
    /// The walker's width while he walks: his panel's width when he set off.
    private var width: CGFloat = 0
    /// Where he hops to, fixed when the hop starts: the island Klay's place then.
    private var hopTarget: IslandWindowController.KlayHome?
    /// What to do once he is home (DesktopKlayController after a request called him back).
    private var arrived: [() -> Void] = []

    /// Walks Klay home from `given`, the panel he is drawn in (the drag ghost, the desktop Klay's
    /// panel), from where it is. The walker takes the panel over: its content becomes the walking
    /// Klay and it closes when he is home. `then` runs once he is home and the island's Klay shows.
    func walkHome(panel given: NSPanel?, then: (() -> Void)? = nil) {
        // One Klay at a time: a walk still under way ends at once (it never happens in use, the
        // island's Klay is hidden and cannot be dragged while a walker is out).
        if isWalking { arrive(closingAt: 0) }
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
        plan = KlayWalk.Plan(from: from, to: doorstep)
        hopTarget = nil
        start = CACurrentMediaTime()

        timer?.invalidate()
        let t = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            // Scheduled on the main run loop: already on the main actor.
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        tick()
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

    private func tick() {
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
        let f = KlayWalk.hop(u, from: plan.to, to: home.center, fromWidth: width,
                             toWidth: home.shown ? home.width : 0, fades: !home.shown)
        place(panel, center: f.center, width: max(1, f.width))
        panel.alphaValue = f.alpha
        if u >= 1 {
            // Into a shown place, the island's Klay draws on its next frame at the same place and
            // size: the walker stays one more instant so there is never a frame without Klay.
            arrive(closingAt: home.shown ? 1.0 / 30 : 0)
        }
    }

    private func place(_ panel: NSPanel, center c: CGPoint, width w: CGFloat) {
        panel.setFrame(NSRect(x: c.x - w / 2, y: c.y - w / 2, width: w, height: w), display: true)
    }

    /// He is home: the `peek` sound, the island's Klay shows, the timer stops, the panel closes
    /// after `delay` seconds, and what waited for him runs.
    private func arrive(closingAt delay: Double) {
        timer?.invalidate()
        timer = nil
        SoundEngine.shared.play("peek")
        let leaving = panel
        panel = nil
        engine = nil
        plan = nil
        hopTarget = nil
        isWalking = false
        AppState.shared.klayWalkingHome = false
        if delay > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { leaving?.close() }
        } else {
            leaving?.close()
        }
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
