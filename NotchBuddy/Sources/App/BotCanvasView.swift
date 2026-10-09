import SwiftUI
import QuartzCore

/// SwiftUI wrapper: TimelineView drives a Canvas that calls BotEngine.draw().
/// Uses a shared engine per-task; the main bot uses AppState's shared engine.
struct BotCanvasView: View {
    @ObservedObject var state: AppState
    var particleOverhang: CGFloat = 0
    /// When set, overrides island-based eye-tracking (used by desktop Klay).
    /// CGPoint in the same coord space as state.mousePosition (DesktopSpace, y-down).
    var lookOriginOverride: CGPoint? = nil

    // One engine per view instance (main bot)
    @StateObject private var engine = BotEngine()

    var body: some View {
        // One frame per display refresh while the island shows, none while it is hidden.
        TimelineView(.animation(paused: state.mode == .hidden)) { timeline in
            Canvas { context, size in
                // dt comes from the engine's own clock (CACurrentMediaTime, as in update):
                // timeline.date counts from 2001 and the engine from boot, so mixing the two
                // pinned dt at its 0.05 s cap whatever the frame rate.
                _ = timeline.date
                let dt = KlayMotion.frameDelta(now: CACurrentMediaTime(), last: engine.lastTime)
                engine.lookX = lookX(state: state, size: size)
                engine.lookY = lookY(state: state, size: size)
                engine.particleOverhang = particleOverhang
                // Integration pills have a fixed brand color → use it as bodyColor.
                // Claude Code tasks use state-based gradient (working=blue, thinking=purple, etc.).
                if state.showingPlanDetail {
                    let hex = ClaudePlanGauge.color(for: state.claudePlanUsage.flatMap { ClaudePlanGauge.dominantPct($0) })
                    engine.bodyColor = cgColorFromHex(hex)
                } else {
                    engine.bodyColor = (state.focusTask?.isIntegration == true)
                        ? cgColorFromHex(state.focusTask!.color)
                        : nil
                }

                // Compute shouldDance per-frame (no observer lag)
                let dancing: Bool = {
                    let active = AppState.shared.activeIntegrations
                    let spotify = SpotifyController.shared.isPlaying && active.contains(SpotifyController.pillId)
                    guard spotify else { return false }
                    let allowed: Set<BotState> = [.idle, .working, .thinking, .searching, .finished]
                    guard allowed.contains(state.effectiveState) else { return false }
                    if state.mode == .compact { return true }
                    guard state.mode == .expanded && state.view == .overview else { return false }
                    return state.focusId == SpotifyController.pillId
                }()
                engine.setDancing(dancing)

                engine.update(dt: dt)
                var ctx = context
                engine.applyDance(&ctx, size: size)
                // Klay (glow, limbs, glyph, eyes) spins as a whole on a roll;
                // the badge and particles are drawn on top and do not spin.
                engine.draw(context: ctx, size: size)
                engine.drawHandsAndExtras(context: ctx, size: size)
            }
        }
        .onChange(of: state.effectiveState) { _, newState in
            engine.setState(newState)
        }
        .onReceive(NotificationCenter.default.publisher(for: .triggerEmote)) { notif in
            if let emote = notif.object as? BotEmote {
                engine.triggerEmote(emote)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .triggerSlap)) { _ in
            engine.slap()
        }
        .onReceive(NotificationCenter.default.publisher(for: .botBlink)) { _ in
            engine.blink()
        }
        .onReceive(NotificationCenter.default.publisher(for: .botSetTgEs)) { notif in
            if let v = notif.object as? CGFloat {
                engine.tgEs = v
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .botGreet)) { _ in
            engine.greet()
        }
        .onAppear {
            engine.setState(state.effectiveState, force: true)
        }
    }

    private func lookX(state: AppState, size: CGSize) -> CGFloat {
        if let origin = lookOriginOverride {
            return tanh((state.mousePosition.x - origin.x) / 260)
        }
        let (islandW, islandH) = islandSize(mode: state.mode, view: state.view,
                                             progress: state.uploadProgress,
                                             nw: state.notchWidth, nh: state.notchHeight)
        let (botCx, botCy, _, _) = botPosition(mode: state.mode, view: state.view,
                                                islandW: islandW, islandH: islandH,
                                                uploadProgress: state.uploadProgress)
        let bot = islandBotPoint(islandW: islandW, botCx: botCx, botCy: botCy)
        return tanh((state.mousePosition.x - bot.x) / 260)
    }

    /// Bot centre in DesktopSpace, like state.mousePosition. The island is centred at the
    /// top of its screen, which can be any display, anywhere in the arrangement.
    private func islandBotPoint(islandW: CGFloat, botCx: CGFloat, botCy: CGFloat) -> CGPoint {
        let screen = IslandWindowController.islandScreen().frame
        return DesktopSpace.topDown(CGPoint(x: screen.midX - islandW / 2 + botCx,
                                            y: screen.maxY - botCy),
                                    desktopTop: IslandWindowController.desktopTop)
    }

    private func lookY(state: AppState, size: CGSize) -> CGFloat {
        if let origin = lookOriginOverride {
            return -tanh((state.mousePosition.y - origin.y) / 200)
        }
        let (islandW, islandH) = islandSize(mode: state.mode, view: state.view,
                                             progress: state.uploadProgress,
                                             nw: state.notchWidth, nh: state.notchHeight)
        let actualH: CGFloat = (state.mode == .expanded && state.view == .prompt)
            ? min(300, 240 + CGFloat(state.chatHistory.count) * 40)
            : islandH
        let (botCx, botCy, _, _) = botPosition(mode: state.mode, view: state.view,
                                                islandW: islandW, islandH: actualH,
                                                uploadProgress: state.uploadProgress)
        let bot = islandBotPoint(islandW: islandW, botCx: botCx, botCy: botCy)
        return -tanh((state.mousePosition.y - bot.y) / 200)
    }
}
