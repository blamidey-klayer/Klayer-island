import Foundation
import CoreGraphics
import QuartzCore
import SwiftUI

// Klay — the Klayer Island character. The state machine, tweens and particles keep
// the engine's original timings (MIT code from Coucou); the drawing is Klay's own
// (KlayPaint, KlayGlyph), and the springs, gaze, lean and idle fidgets come from
// KlayMotion, all ported from tools/klay-preview/src/engine.ts and motion.ts.

// MARK: - Easing functions (same as prototype: E.out, E.inOut, E.back, E.lin)

enum Ease {
    static func out(_ t: CGFloat) -> CGFloat   { 1 - pow(1 - t, 3) }
    static func inOut(_ t: CGFloat) -> CGFloat { t < 0.5 ? 4*t*t*t : 1 - pow(-2*t+2, 3)/2 }
    static func back(_ t: CGFloat) -> CGFloat  { let c1: CGFloat = 1.7; let c3 = c1+1; return 1+c3*pow(t-1,3)+c1*pow(t-1,2) }
    static func lin(_ t: CGFloat) -> CGFloat   { t }
}

// MARK: - Tween key: [target, duration_ms, easing]

struct TweenKey {
    let target: CGFloat
    let duration: CGFloat    // milliseconds
    let ease: (CGFloat) -> CGFloat
}

struct Tween {
    let property: String
    var keys: [TweenKey]
    var keyIndex: Int = 0
    var from: CGFloat
    var startTime: Double    // CACurrentMediaTime() * 1000
    var onComplete: (() -> Void)? = nil
}

// MARK: - Particle

struct Particle {
    enum ParticleType { case heart, star, spark, sweat, z }
    var type: ParticleType
    var x, y, vx, vy: CGFloat
    var age: Double        // seconds
    var life: Double
    var rot: CGFloat
    var size: CGFloat
}

// MARK: - Bot state config (mirrors STATES in prototype)

struct BotStateCfg {
    let color: CGColor
    let tint: CGFloat
    let eye: EyeShape
    let badge: BadgeType?
    let badgeColor: CGColor
    let glow: CGColor
    let glowOpacity: CGFloat
    let bounces: Bool
    let scans: Bool
    let breathes: Bool
    let zz: Bool
    let sweat: Bool
    let look: CGPoint?     // fixed look direction (yaw, pitch); pitch > 0 looks up
    let tilt: CGFloat
    let sound: String?
}

enum EyeShape: String {
    case pill, wide, dot, line, flat, happy, closed, spiral, heart, star, tired, wink
}

enum BadgeType {
    case dots(CGColor)
    case bang(CGColor)
    case question(CGColor)
    case dot(CGColor)
}

// MARK: - State colours

/// The colour of each state (Klay's glow and badge, the island's halo behind him):
/// lightened variants of the Klayer brand colours, readable on the black island (the
/// exact brand values are too dark on black). Mirror of C in tools/klay-preview/src/engine.ts.
enum StateColor {
    static let idle      = rgb(0x3E7280)  // teal-light
    static let working   = rgb(0x4FA3B5)  // teal, lightened
    static let thinking  = rgb(0x7FB8C4)  // teal, lightened
    static let searching = rgb(0xA8D0D8)  // teal, lightened
    static let approval  = rgb(0xD69A3A)  // etat-tension, lightened
    static let question  = rgb(0xE2B866)  // etat-tension, lightened
    static let error     = rgb(0xD0663F)  // brick, lightened
    static let finished  = rgb(0x6FA35E)  // etat-tenu, lightened
    static let ratelimit = rgb(0xB0761C)  // etat-tension
    static let sleeping  = rgb(0xC9CAC3)  // filet
    static let dizzy     = rgb(0xE08A6A)  // brick, lightened

    /// The colour of `state`.
    static func of(_ state: BotState) -> CGColor {
        switch state {
        case .idle:      return idle
        case .working:   return working
        case .thinking:  return thinking
        case .searching: return searching
        case .approval:  return approval
        case .question:  return question
        case .error:     return error
        case .finished:  return finished
        case .ratelimit: return ratelimit
        case .sleeping:  return sleeping
        case .dizzy:     return dizzy
        }
    }

    /// Above this luminance a badge fill is light. 0.2 is where white and teal-deep
    /// contrast equally; every state colour with a badge is above it and gets at least
    /// 4.6:1 with teal-deep.
    static let lightFill: CGFloat = 0.2

    /// The colour of a badge's marks (dots, "!", "?"): teal-deep on a light fill, white
    /// otherwise. Mirror of badgeMarkColor in tools/klay-preview/src/engine.ts.
    static func mark(on fill: CGColor) -> Color {
        luminance(fill) > lightFill ? KlayPaint.ink : .white
    }

    /// Relative luminance (WCAG 2) of a colour.
    private static func luminance(_ c: CGColor) -> CGFloat {
        let (r, g, b) = cgColorToTuple(c)
        func f(_ v: CGFloat) -> CGFloat { v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        return 0.2126 * f(r) + 0.7152 * f(g) + 0.0722 * f(b)
    }

    private static func rgb(_ hex: UInt32) -> CGColor {
        CGColor(red: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

// MARK: - Bot state configs

let BotStates: [BotState: BotStateCfg] = [
    .idle: BotStateCfg(
        color: StateColor.idle, tint: 0.35,
        eye: .pill, badge: nil,
        badgeColor: .white, glow: StateColor.idle, glowOpacity: 0.35,
        bounces: false, scans: false, breathes: false, zz: false, sweat: false,
        look: nil, tilt: 0, sound: nil),
    .working: BotStateCfg(
        color: StateColor.working, tint: 0.72,
        eye: .pill, badge: .dots(StateColor.working),
        badgeColor: StateColor.working, glow: StateColor.working, glowOpacity: 0.55,
        bounces: false, scans: false, breathes: false, zz: false, sweat: false,
        look: nil, tilt: 0, sound: "work"),
    .thinking: BotStateCfg(
        color: StateColor.thinking, tint: 0.72,
        eye: .pill, badge: .dots(StateColor.thinking),
        badgeColor: StateColor.thinking, glow: StateColor.thinking, glowOpacity: 0.5,
        bounces: false, scans: false, breathes: false, zz: false, sweat: false,
        look: CGPoint(x: 0.55, y: 0.55), tilt: 0, sound: "think"),
    .searching: BotStateCfg(
        color: StateColor.searching, tint: 0.72,
        eye: .pill, badge: .dots(StateColor.searching),
        badgeColor: StateColor.searching, glow: StateColor.searching, glowOpacity: 0.55,
        bounces: false, scans: true, breathes: false, zz: false, sweat: false,
        look: nil, tilt: 0, sound: "search"),
    .approval: BotStateCfg(
        color: StateColor.approval, tint: 0.78,
        eye: .wide, badge: .bang(StateColor.approval),
        badgeColor: StateColor.approval, glow: StateColor.approval, glowOpacity: 0.6,
        bounces: true, scans: false, breathes: false, zz: false, sweat: false,
        look: nil, tilt: 0, sound: "approval"),
    .question: BotStateCfg(
        color: StateColor.question, tint: 0.75,
        eye: .pill, badge: .question(StateColor.question),
        badgeColor: StateColor.question, glow: StateColor.question, glowOpacity: 0.55,
        bounces: false, scans: false, breathes: false, zz: false, sweat: false,
        look: nil, tilt: 0.12, sound: "question"),
    .error: BotStateCfg(
        color: StateColor.error, tint: 0.78,
        eye: .flat, badge: .dot(StateColor.error),
        badgeColor: StateColor.error, glow: StateColor.error, glowOpacity: 0.55,
        bounces: false, scans: false, breathes: false, zz: false, sweat: false,
        look: nil, tilt: 0, sound: "error"),
    .finished: BotStateCfg(
        color: StateColor.finished, tint: 0.5,
        eye: .happy, badge: .dot(StateColor.finished),
        badgeColor: StateColor.finished, glow: StateColor.finished, glowOpacity: 0.5,
        bounces: false, scans: false, breathes: false, zz: false, sweat: false,
        look: nil, tilt: 0, sound: "finish"),
    .ratelimit: BotStateCfg(
        color: StateColor.ratelimit, tint: 0.72,
        eye: .tired, badge: .dot(StateColor.ratelimit),
        badgeColor: StateColor.ratelimit, glow: StateColor.ratelimit, glowOpacity: 0.45,
        bounces: false, scans: false, breathes: false, zz: false, sweat: true,
        look: nil, tilt: 0, sound: "rate"),
    .sleeping: BotStateCfg(
        color: StateColor.sleeping, tint: 0.25,
        eye: .closed, badge: nil,
        badgeColor: .white, glow: StateColor.sleeping, glowOpacity: 0.2,
        bounces: false, scans: false, breathes: true, zz: true, sweat: false,
        look: nil, tilt: 0, sound: "sleep"),
    .dizzy: BotStateCfg(
        color: StateColor.dizzy, tint: 0.7,
        eye: .spiral, badge: nil,
        badgeColor: .white, glow: StateColor.dizzy, glowOpacity: 0.55,
        bounces: false, scans: false, breathes: false, zz: false, sweat: false,
        look: nil, tilt: 0, sound: "dizzy"),
]

// MARK: - Bot engine

@MainActor
final class BotEngine: ObservableObject {
    var isMini: Bool = false
    var bodyColor: CGColor? = nil    // disc colour behind a mini Klay (agents, services)

    // Animation state (mirrors prototype 's' object)
    var yaw:    CGFloat = 0
    var pitch:  CGFloat = 0          // positive looks up
    var roll:   CGFloat = 0          // whole-body spin (finished, dizzy)
    var tilt:   CGFloat = 0
    var open:   CGFloat = 1          // eye open amount
    var sx:     CGFloat = 1          // scale X
    var sy:     CGFloat = 1          // scale Y
    var oy:     CGFloat = 0          // offset Y (bounce)
    var ox:     CGFloat = 0          // offset X (shake)
    var tint:   CGFloat = 0          // glow strength
    var hands:  CGFloat = 0          // hello wave amount
    var blush:  CGFloat = 0
    var es:     CGFloat = 1          // eye scale
    var badgeS: CGFloat = 0          // badge scale

    /// Hands and feet in Klay's frame: damped springs pulled towards KlayPaint.limbTargets
    /// every frame, carried by the body's motion (KlayMotion.hand, KlayMotion.foot).
    var limbs: KlayPaint.Limbs = .rest
    private var springLH = KlaySpring2(KlayPaint.Limbs.rest.lh)
    private var springRH = KlaySpring2(KlayPaint.Limbs.rest.rh)
    private var springLF = KlaySpring2(KlayPaint.Limbs.rest.lf)
    private var springRF = KlaySpring2(KlayPaint.Limbs.rest.rf)
    /// The body's place last frame, so its motion can be taken out of the limbs (inertia).
    private var bodyPrev: BodyPose? = nil

    // Gaze springs (yaw, pitch) and the lean of the whole figure (x from yaw, y from pitch).
    private var yawVel: CGFloat = 0
    private var pitchVel: CGFloat = 0
    private var lean = KlaySpring2(.zero)
    /// Hover: the island sets tgEs above 1 while the pointer is on Klay.
    private var hovered = false
    /// 0…1, eased: how far Klay has lifted towards a pointer on him.
    private var hoverLift: CGFloat = 0

    // Pointer stillness, glances and idle fidgets.
    private var lastLookX: CGFloat = 0
    private var lastLookY: CGFloat = 0
    private var pointerStillSince: Double = CACurrentMediaTime()
    private var stillLook: Double = Double.random(in: KlayMotion.Idle.stillLook)
    /// While the pointer is still: where Klay glances (nil = back at the pointer).
    private var glance: CGPoint? = nil
    private var glanceNext: Double = 0
    /// A foot tap or a stretch under way, the next fidget, the next stretch or yawn.
    private var fidget: Fidget? = nil
    private var nextFidget: Double = CACurrentMediaTime() + Double.random(in: KlayMotion.Idle.fidget)
    private var nextLong: Double = 0
    private var longYawn = true

    private struct Fidget {
        enum Kind { case tap, stretch }
        let kind: Kind
        let start: Double
        let side: CGFloat
    }

    private struct BodyPose {
        var x: CGFloat, y: CGFloat, lean: CGFloat, tilt: CGFloat
    }

    /// Glyph units in one R (R = 0.3 × canvas width; ox, oy and the dance are in R).
    private static let unitsPerR = 0.3 * KlayGlyph.width / KlayPaint.glyphSpan

    // Targets
    var tgYaw:    CGFloat = 0
    var tgPitch:  CGFloat = 0
    var tgTilt:   CGFloat = 0
    var tgSy:     CGFloat = 1
    var tgSx:     CGFloat = 1
    var tgEs:     CGFloat = 1   // eye-scale target (hover love: 1.08, normal: 1)

    // Particle canvas overhang (extra canvas height at top for hearts to fly into)
    var particleOverhang: CGFloat = 0

    // Color (animated)
    var col:  (CGFloat, CGFloat, CGFloat) = (0.243, 0.447, 0.502)  // idle
    var colT: (CGFloat, CGFloat, CGFloat) = (0.243, 0.447, 0.502)

    // State
    var state: BotState = .idle
    var cfg: BotStateCfg = BotStates[.idle]!

    // Eye override (emote)
    var eyeOverride: EyeShape? = nil
    var eyeOverrideUntil: Double = 0   // CACurrentMediaTime()
    var permanentEye: EyeShape? = nil   // restored after temporary emote/blink expires
    var permanentEmote: BotEmote? = nil // stored so doMiniBehaviorLoop can switch on it
    var miniNextBehavior: Double = 0    // CACurrentMediaTime() of next periodic mini action

    // Badge animation
    var badge: BadgeType? = nil
    var badgeKey: String = "none"
    var badgeToken: Int = 0

    // Tweens (keyed by property name)
    var tweens: [String: Tween] = [:]
    var locks:  Set<String> = []

    // Particles
    var particles: [Particle] = []

    /// Where the pointer is, −1…1 each way (tanh of the distance); lookY > 0 is above Klay.
    var lookX: CGFloat = 0
    var lookY: CGFloat = 0

    // Timing
    var lastTime: Double = CACurrentMediaTime()
    var t0: Double = CACurrentMediaTime() - Double.random(in: 0...5)
    var nextBlink: Double = CACurrentMediaTime() + 1.5 + Double.random(in: 0...2)
    var waveUntil: Double = 0
    var waveStart: Double = 0     // CACurrentMediaTime() when wave animation began
    var greetToken: Int = 0       // incremented to invalidate stale greet closures
    var lastAmbient: Double = 0

    // Slap tracking (for dizzy on 3 slaps)
    var slapTimes: [Double] = []

    // Dancing (music playing)
    var isDancing: Bool = false
    var dancingLevel: CGFloat = 0   // 0→1 over 0.3s, 1→0 over 0.5s

    // Mini wandering look (random, ignores mouse)
    var miniLookTarget: CGPoint = .zero
    var miniLookNextTime: Double = 0

    // MARK: - Public API

    func setState(_ newState: BotState, force: Bool = false) {
        guard state != newState || force else { return }
        let prev = state
        state = newState
        cfg = BotStates[newState]!
        colT = cgColorToTuple(cfg.color)
        setTarget(key: "tint", value: cfg.tint)
        setTarget(key: "tilt", value: cfg.tilt)
        setBadge(cfg.badge)

        switch newState {
        case .finished:
            // A little jump and a full spin of the whole body, then sparks.
            anim("oy", keys: [
                TweenKey(target: -0.35, duration: 260, ease: Ease.out),
                TweenKey(target: 0,     duration: 380, ease: Ease.back),
            ])
            doRoll(duration: 700, turns: 1)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.emit(.spark, count: 5)
            }
        case .error:
            anim("ox", keys: [
                TweenKey(target: 0.08,  duration: 50,  ease: Ease.out),
                TweenKey(target: -0.08, duration: 70,  ease: Ease.inOut),
                TweenKey(target: 0.05,  duration: 70,  ease: Ease.inOut),
                TweenKey(target: 0,     duration: 90,  ease: Ease.out),
            ])
        case .approval:
            anim("oy", keys: [
                TweenKey(target: -0.2, duration: 150, ease: Ease.out),
                TweenKey(target: 0,    duration: 300, ease: Ease.back),
            ])
        case .dizzy:
            doRoll(duration: 1300, turns: 2)
        case .question:
            blink()
        case .ratelimit:
            emit(.sweat, count: 1)
        default:
            if prev != .idle || newState != .idle { blink() }
        }
    }

    func setBadge(_ b: BadgeType?) {
        let key = badgeString(b)
        guard key != badgeKey else { return }
        badgeKey = key
        let tok = badgeToken + 1
        badgeToken = tok
        anim("badgeS", keys: [TweenKey(target: 0, duration: 90, ease: Ease.inOut)])
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self, tok == self.badgeToken else { return }
            self.badge = b
            if b != nil {
                self.anim("badgeS", keys: [TweenKey(target: 1, duration: 280, ease: Ease.back)])
            }
        }
    }

    func blink() {
        guard !locks.contains("open") else { return }
        anim("open", keys: [
            TweenKey(target: 0.06, duration: 70,  ease: Ease.inOut),
            TweenKey(target: 1,    duration: 130, ease: Ease.out),
        ])
    }

    func squash() {
        anim("sy", keys: [
            TweenKey(target: 0.8,  duration: 70,  ease: Ease.out),
            TweenKey(target: 1.1,  duration: 130, ease: Ease.out),
            TweenKey(target: 1,    duration: 170, ease: Ease.inOut),
        ])
        anim("sx", keys: [
            TweenKey(target: 1.14, duration: 70,  ease: Ease.out),
            TweenKey(target: 0.95, duration: 130, ease: Ease.out),
            TweenKey(target: 1,    duration: 170, ease: Ease.inOut),
        ])
        // The hands carry on down as the body squashes.
        springLH.y.velocity += KlayMotion.Kick.squash
        springRH.y.velocity += KlayMotion.Kick.squash
    }

    // MARK: - Slap (dizzy mechanic)

    func slap() {
        interruptGreet()
        guard state != .dizzy else { return }
        let now = CACurrentMediaTime()
        slapTimes = slapTimes.filter { now - $0 < 1.7 }
        slapTimes.append(now)
        SoundEngine.shared.play("slap")
        squash()
        // The slap flings the hands up and to one side, the feet a little.
        let side: CGFloat = Bool.random() ? -1 : 1
        springLH.y.velocity -= KlayMotion.Kick.slapUp
        springRH.y.velocity -= KlayMotion.Kick.slapUp
        springLH.x.velocity += side * KlayMotion.Kick.slapSide
        springRH.x.velocity += side * KlayMotion.Kick.slapSide
        springLF.y.velocity -= KlayMotion.Kick.slapFeet
        springRF.y.velocity -= KlayMotion.Kick.slapFeet
        if slapTimes.count >= 3 {
            slapTimes = []
            NotificationCenter.default.post(name: .botDizzy, object: nil)
        } else {
            // Annoyed: line eyes for 800ms, annoyed sound after 60ms delay
            eyeOverride = .line
            eyeOverrideUntil = now + 0.8
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
                SoundEngine.shared.play("annoyed")
            }
        }
    }

    // MARK: - Dancing

    func setDancing(_ dancing: Bool) {
        guard isDancing != dancing else { return }
        isDancing = dancing
    }

    /// The perk-up as the pointer arrives on Klay: a little stretch, hands up.
    private func perk() {
        anim("sy", keys: [
            TweenKey(target: 1.07, duration: 110, ease: Ease.out),
            TweenKey(target: 1,    duration: 280, ease: Ease.back),
        ])
        anim("sx", keys: [
            TweenKey(target: 0.96, duration: 110, ease: Ease.out),
            TweenKey(target: 1,    duration: 280, ease: Ease.back),
        ])
        springLH.y.velocity -= KlayMotion.Kick.perk
        springRH.y.velocity -= KlayMotion.Kick.perk
    }

    // MARK: - Mini periodic behavior loop

    func doMiniBehaviorLoop() {
        switch permanentEmote {

        case .happy:
            // Little jump + squash
            guard !locks.contains("oy") else {
                miniNextBehavior = CACurrentMediaTime() + 0.4
                return
            }
            anim("oy", keys: [
                TweenKey(target: -0.30, duration: 120, ease: Ease.out),
                TweenKey(target:  0.03, duration: 200, ease: Ease.inOut),
                TweenKey(target:  0,    duration: 160, ease: Ease.back),
            ])
            anim("sy", keys: [
                TweenKey(target: 0.82, duration: 80,  ease: Ease.out),
                TweenKey(target: 1.18, duration: 130, ease: Ease.out),
                TweenKey(target: 0.88, duration: 160, ease: Ease.inOut),
                TweenKey(target: 1,    duration: 200, ease: Ease.back),
            ])
            anim("sx", keys: [
                TweenKey(target: 1.15, duration: 80,  ease: Ease.out),
                TweenKey(target: 0.88, duration: 130, ease: Ease.out),
                TweenKey(target: 1.06, duration: 160, ease: Ease.inOut),
                TweenKey(target: 1,    duration: 200, ease: Ease.back),
            ])
            miniNextBehavior = CACurrentMediaTime() + 2.2 + Double.random(in: 0...1.2)

        case .annoyed:
            // Rapid head shake
            guard !locks.contains("yaw") else {
                miniNextBehavior = CACurrentMediaTime() + 0.5
                return
            }
            anim("yaw", keys: [
                TweenKey(target: -0.65, duration: 50,  ease: Ease.out),
                TweenKey(target:  0.65, duration: 90,  ease: Ease.inOut),
                TweenKey(target: -0.5,  duration: 80,  ease: Ease.inOut),
                TweenKey(target:  0.4,  duration: 75,  ease: Ease.inOut),
                TweenKey(target: -0.2,  duration: 70,  ease: Ease.inOut),
                TweenKey(target:  0,    duration: 140, ease: Ease.out),
            ])
            miniNextBehavior = CACurrentMediaTime() + 3.0 + Double.random(in: 0...2.5)

        case .wink:
            // Brief wink: eye closes, head tilts slightly
            let now2 = CACurrentMediaTime()
            eyeOverride = .wink
            eyeOverrideUntil = now2 + 0.55
            anim("tilt", keys: [
                TweenKey(target:  0.13, duration: 100, ease: Ease.out),
                TweenKey(target:  0.13, duration: 320, ease: Ease.lin),
                TweenKey(target:  0,    duration: 200, ease: Ease.inOut),
            ])
            miniNextBehavior = CACurrentMediaTime() + 2.2 + Double.random(in: 0...2.0)

        case .love:
            // Emit hearts + gentle sway
            emit(.heart, count: 2)
            anim("tilt", keys: [
                TweenKey(target: -0.1, duration: 180, ease: Ease.out),
                TweenKey(target:  0.1, duration: 340, ease: Ease.inOut),
                TweenKey(target:  0,   duration: 220, ease: Ease.inOut),
            ])
            miniNextBehavior = CACurrentMediaTime() + 2.6 + Double.random(in: 0...1.5)

        default:
            miniNextBehavior = CACurrentMediaTime() + 3.0 + Double.random(in: 0...2.0)
        }
    }

    /// Spins the whole character `turns` times (finished, dizzy), then lands with a squash.
    func doRoll(duration: CGFloat, turns: CGFloat) {
        roll = 0
        anim("roll", keys: [TweenKey(target: .pi * 2 * turns, duration: duration, ease: Ease.inOut)]) { [weak self] in
            self?.roll = 0
            self?.squash()
        }
    }

    func greet() {
        let now = CACurrentMediaTime()
        greetToken += 1
        let tok = greetToken
        waveStart = now + 0.45   // wave begins at 0.45s
        waveUntil = now + 1.55   // wave ends at 1.55s

        // 0s: happy eyes for full greeting (2s — no gap, no flicker)
        eyeOverride = .happy
        eyeOverrideUntil = now + 2.0
        anim("oy", keys: [
            TweenKey(target: -0.06, duration: 220, ease: Ease.out),
            TweenKey(target:  0.0,  duration: 220, ease: Ease.back),
        ])

        // 0.25s: hand up + body squash + sound
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self, self.greetToken == tok else { return }
            self.anim("hands", keys: [TweenKey(target: 1, duration: 280, ease: Ease.out)])
            self.anim("sy", keys: [
                TweenKey(target: 0.95, duration: 100, ease: Ease.out),
                TweenKey(target: 1.0,  duration: 260, ease: Ease.back),
            ])
            self.anim("sx", keys: [
                TweenKey(target: 1.04, duration: 100, ease: Ease.out),
                TweenKey(target: 1.0,  duration: 260, ease: Ease.back),
            ])
            SoundEngine.shared.play("greet")
        }

        // 0.55s: first blink
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) { [weak self] in
            guard let self, self.greetToken == tok else { return }
            self.blink()
        }

        // 1.50s: second blink
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.50) { [weak self] in
            guard let self, self.greetToken == tok else { return }
            self.blink()
        }

        // 1.55s: hand back down
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.55) { [weak self] in
            guard let self, self.greetToken == tok else { return }
            self.waveUntil = 0
            self.anim("hands", keys: [TweenKey(target: 0, duration: 200, ease: Ease.inOut)])
        }

        // 1.75s: brief happy eyes then back to normal
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.75) { [weak self] in
            guard let self, self.greetToken == tok else { return }
            self.eyeOverride = .happy
            self.eyeOverrideUntil = CACurrentMediaTime() + 0.30
        }
    }

    /// Immediately interrupts an in-progress greeting (hand back down in 150 ms).
    func interruptGreet() {
        guard hands > 0.01 || CACurrentMediaTime() < waveUntil else { return }
        greetToken += 1   // invalidate any pending closures
        waveUntil = 0
        waveStart = 0
        anim("hands", keys: [TweenKey(target: 0, duration: 150, ease: Ease.inOut)])
    }

    /// Sets a permanent eye expression that survives blinks and transient emotes.
    func setPermanentEmote(_ emote: BotEmote?) {
        permanentEmote = emote
        // .wink fires periodically — don't freeze the eye (normal between winks)
        if emote == .wink {
            miniNextBehavior = CACurrentMediaTime() + Double.random(in: 0.8...2.5)
            return
        }
        permanentEye = emote.map { emoteEyeShape($0) }
        if let eye = permanentEye {
            eyeOverride = eye
            eyeOverrideUntil = .greatestFiniteMagnitude
        } else {
            if eyeOverrideUntil == .greatestFiniteMagnitude {
                eyeOverride = nil
                eyeOverrideUntil = 0
            }
        }
        // Stagger first periodic behavior so bots don't all fire at once
        miniNextBehavior = CACurrentMediaTime() + Double.random(in: 0.8...2.5)
    }

    func triggerEmote(_ emote: BotEmote, duration: Double = 1.8, silent: Bool = false) {
        let now = CACurrentMediaTime()
        eyeOverride = emoteEyeShape(emote)
        eyeOverrideUntil = now + duration

        switch emote {
        case .love:
            anim("blush", keys: [
                TweenKey(target: 1, duration: 300, ease: Ease.out),
                TweenKey(target: 1, duration: CGFloat((duration - 0.6) * 1000), ease: Ease.lin),
                TweenKey(target: 0, duration: 300, ease: Ease.inOut),
            ])
            emit(.heart, count: 4)
            anim("oy", keys: [
                TweenKey(target: -0.1, duration: 160, ease: Ease.out),
                TweenKey(target: 0,    duration: 300, ease: Ease.back),
            ])
        case .surprised:
            anim("oy", keys: [
                TweenKey(target: -0.3, duration: 140, ease: Ease.out),
                TweenKey(target: 0,    duration: 380, ease: Ease.back),
            ])
            anim("es", keys: [
                TweenKey(target: 1.25, duration: 120, ease: Ease.out),
                TweenKey(target: 1,    duration: 500, ease: Ease.inOut),
            ])
        case .proud:
            squash()
            emit(.star, count: 5)
            anim("tilt", keys: [
                TweenKey(target: -0.14, duration: 220, ease: Ease.out),
                TweenKey(target: -0.14, duration: CGFloat((duration - 0.5) * 1000), ease: Ease.lin),
                TweenKey(target: 0,     duration: 280, ease: Ease.inOut),
            ])
            anim("blush", keys: [
                TweenKey(target: 0.7, duration: 250, ease: Ease.out),
                TweenKey(target: 0.7, duration: CGFloat((duration - 0.5) * 1000), ease: Ease.lin),
                TweenKey(target: 0,   duration: 300, ease: Ease.inOut),
            ])
        case .wink:
            anim("tilt", keys: [
                TweenKey(target: 0.12, duration: 160, ease: Ease.out),
                TweenKey(target: 0.12, duration: CGFloat((duration - 0.4) * 1000), ease: Ease.lin),
                TweenKey(target: 0,    duration: 240, ease: Ease.inOut),
            ])
        case .yawn:
            anim("sy", keys: [
                TweenKey(target: 1.12, duration: 500, ease: Ease.inOut),
                TweenKey(target: 1,    duration: 500, ease: Ease.inOut),
            ])
            anim("sx", keys: [
                TweenKey(target: 0.94, duration: 500, ease: Ease.inOut),
                TweenKey(target: 1,    duration: 500, ease: Ease.inOut),
            ])
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
                self?.eyeOverride = .closed
                self?.emit(.z, count: 2)
            }
        case .happy:
            anim("blush", keys: [
                TweenKey(target: 0.6, duration: 200, ease: Ease.out),
                TweenKey(target: 0,   duration: 600, ease: Ease.inOut),
            ])
        case .annoyed:
            eyeOverride = .line
            eyeOverrideUntil = now + 0.8
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
                SoundEngine.shared.play("annoyed")
            }
        }
    }

    func emit(_ type: Particle.ParticleType, count: Int) {
        for i in 0..<count {
            let isZ = type == .z
            let p = Particle(
                type: type,
                x: (CGFloat.random(in: -0.5...0.5)) * 0.9 + (isZ ? 0.55 : 0),
                y: -0.7 - CGFloat.random(in: 0...0.2),
                vx: CGFloat.random(in: -0.5...0.5) * 0.35 + (isZ ? 0.18 : 0),
                vy: -(0.45 + CGFloat.random(in: 0...0.35)),
                age: -Double(i) * 0.14,
                life: 1.3 + Double.random(in: 0...0.5),
                rot: CGFloat.random(in: 0...(.pi * 2)),
                size: 0.15 + CGFloat.random(in: 0...0.08)
            )
            particles.append(p)
        }
    }

    // MARK: - Update (called every frame from TimelineView)

    func update(dt: Double) {
        let now = CACurrentMediaTime()
        let dtCG = CGFloat(dt)

        // Process tweens
        for key in tweens.keys {
            guard var tw = tweens[key] else { continue }
            let k = tw.keys[tw.keyIndex]
            let elapsed = now * 1000 - tw.startTime
            let p = min(1, max(0, CGFloat(elapsed) / k.duration))
            let val = tw.from + (k.target - tw.from) * k.ease(p)
            setProperty(key, value: val)

            if p >= 1 {
                tw.from = k.target
                tw.keyIndex += 1
                tw.startTime = now * 1000
                if tw.keyIndex >= tw.keys.count {
                    tweens.removeValue(forKey: key)
                    locks.remove(key)
                    tw.onComplete?()
                } else {
                    tweens[key] = tw
                }
            } else {
                tweens[key] = tw
            }
        }

        let t = CGFloat(now - t0)
        let kGen = CGFloat(1 - pow(0.0008, dt))

        // Hover: the island raises tgEs above 1 while the pointer is on Klay.
        let isHovered = !isMini && tgEs > 1.001
        if isHovered && !hovered { perk() }
        hovered = isHovered
        hoverLift += ((isHovered ? 1 : 0) - hoverLift) * kGen

        // How long the pointer has been still.
        if abs(lookX - lastLookX) + abs(lookY - lastLookY) > 0.002 {
            pointerStillSince = now
            stillLook = Double.random(in: KlayMotion.Idle.stillLook)
            glance = nil
            glanceNext = 0
        }
        lastLookX = lookX
        lastLookY = lookY
        let still = now - pointerStillSince

        // Where Klay looks: the pointer, through the response curve (closer still when on him).
        let gain = isHovered ? KlayMotion.Hover.gain : 1
        var ty = clamp(KlayMotion.pointerCurve(lookX) * gain, -1, 1) * KlayMotion.yawRange
        var tp = clamp(KlayMotion.pointerCurve(lookY) * gain, -1, 1) * KlayMotion.pitchRange

        if let fixedLook = cfg.look {
            ty = ty * 0.35 + fixedLook.x * 0.55
            tp = tp * 0.3  + fixedLook.y * 0.5
        }
        if cfg.scans {
            // The binoculars sweep left and right, a little above the horizon.
            ty = sin(t * 2.6) * 0.6
            tp = 0.06
        }
        if state == .sleeping { ty = 0; tp = -0.14 }
        if state == .dizzy    { ty = sin(t * 9) * 0.25 }

        // Mini bots: override look with random wandering (never follows mouse)
        if isMini && cfg.look == nil && !cfg.scans && state != .sleeping && state != .dizzy {
            if now > miniLookNextTime {
                miniLookTarget = CGPoint(
                    x: CGFloat.random(in: -0.88...0.88),
                    y: CGFloat.random(in: -0.55...0.45)
                )
                miniLookNextTime = now + Double.random(in: 0.5...2.0)
            }
            ty = miniLookTarget.x * 0.62
            tp = miniLookTarget.y * 0.5
        }

        // The main Klay, pointer still for a while: he looks around, now and then back at it.
        let glances = !isMini && !isHovered && cfg.look == nil && !cfg.scans
            && (state == .idle || state == .working || state == .finished)
        if glances && still > stillLook {
            if now >= glanceNext {
                let I = KlayMotion.Idle.self
                glance = Double.random(in: 0..<1) < I.back ? nil : CGPoint(
                    x: CGFloat.random(in: -I.glanceX...I.glanceX),
                    y: CGFloat.random(in: I.glanceDown...I.glanceUp))
                glanceNext = now + Double.random(in: I.glance)
            }
            if let g = glance {
                ty = g.x * KlayMotion.yawRange
                tp = g.y * KlayMotion.pitchRange
            }
        } else {
            glance = nil
        }

        tgYaw   = ty
        tgPitch = tp
        tgTilt  = cfg.tilt

        // Body sway during greeting wave
        let waving = now > waveStart && now < waveUntil
        if waving {
            let wt = CGFloat(now - waveStart)
            tgTilt = -0.04 + sin(2 * .pi * 1.2 * wt) * 0.05
        }

        let bounce = cfg.bounces ? -abs(sin(t * 5.2)) * 0.07 : CGFloat(0)
        // oy tween can override if not locked
        if !locks.contains("oy") { oy += (bounce - oy) * kGen }

        if cfg.breathes {
            let amp: CGFloat = isMini ? 0.07 : 0.035
            tgSy = 1 + sin(t * 1.8) * amp
            tgSx = 1 - sin(t * 1.8) * amp * 0.57
        } else if isMini {
            // Subtle idle pulse (unique phase per engine via t0)
            tgSy = 1 + sin(t * 2.2) * 0.04
            tgSx = 1 - sin(t * 2.2) * 0.02
        } else {
            // Awake, the main Klay breathes too, lightly.
            let B = KlayMotion.Breath.self
            tgSy = 1 + sin(t * B.speed) * B.amp
            tgSx = 1 - sin(t * B.speed) * B.amp * 0.5
        }

        // Mini bots: periodic dramatic behaviors
        if isMini && now > miniNextBehavior {
            doMiniBehaviorLoop()
        }

        // The gaze springs to its target: the eyes dart, overshoot a touch and settle.
        if !locks.contains("yaw") {
            var sp = KlaySpring(value: yaw, velocity: yawVel)
            sp.step(towards: tgYaw, dt: dt, response: KlayMotion.gazeResponse, damping: KlayMotion.gazeDamping)
            yaw = sp.value
            yawVel = sp.velocity
        } else {
            yawVel = 0
        }
        if !locks.contains("pitch") {
            var sp = KlaySpring(value: pitch, velocity: pitchVel)
            sp.step(towards: tgPitch, dt: dt, response: KlayMotion.gazeResponse, damping: KlayMotion.gazeDamping)
            pitch = sp.value
            pitchVel = sp.velocity
        } else {
            pitchVel = 0
        }
        if !locks.contains("tilt")  { tilt  += (tgTilt   - tilt)  * kGen  }
        if !locks.contains("sy")    { sy    += (tgSy     - sy)    * kGen  }
        if !locks.contains("sx")    { sx    += (tgSx     - sx)    * kGen  }
        if !locks.contains("es")    { es    += (tgEs     - es)    * kGen  }

        // The whole figure leans towards where Klay looks, after the eyes.
        if !isMini {
            let L = KlayMotion.Lean.self
            lean.step(towards: CGPoint(x: clamp(tgYaw / KlayMotion.yawRange, -1, 1),
                                       y: clamp(tgPitch / KlayMotion.pitchRange, -1, 1)),
                      dt: dt, response: L.response, damping: L.damping)
        }

        // Animate color
        col = mixColor(col, colT, 1 - pow(0.002, dt))

        // Dance level: fade in 0.3s, out 0.5s
        let dancingTarget: CGFloat = isDancing ? 1 : 0
        if dancingLevel < dancingTarget {
            dancingLevel = min(dancingTarget, dancingLevel + dtCG / 0.3)
        } else if dancingLevel > dancingTarget {
            dancingLevel = max(dancingTarget, dancingLevel - dtCG / 0.5)
        }

        updateFidget(now: now, still: still)

        // Limbs: springs pulled towards the pose, carried by the body's motion.
        if !isMini { updateLimbs(now: now, t: t, dt: dt, waving: waving) }

        // Blink
        if now > nextBlink {
            if state != .sleeping && state != .dizzy {
                blink()
                if Double.random(in: 0...1) < 0.22 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.23) { [weak self] in self?.blink() }
                }
            }
            nextBlink = now + 2.2 + Double.random(in: 0...3.2)
        }

        // Clear expired eye override (restore permanent if set)
        if eyeOverride != nil && now > eyeOverrideUntil {
            eyeOverride = permanentEye
            if permanentEye != nil { eyeOverrideUntil = .greatestFiniteMagnitude }
        }

        // Ambient particles
        if now - lastAmbient > 1.3 {
            lastAmbient = now
            if cfg.zz { emit(.z, count: 1) }   // ZZZ works for mini too
            if !isMini && cfg.sweat && Double.random(in: 0...1) < 0.5 { emit(.sweat, count: 1) }
        }

        // Age particles
        for i in particles.indices { particles[i].age += dt }
        particles.removeAll { $0.age >= $0.life }

        lastTime = now
    }

    /// Idle fidgets of the main Klay: a foot tap every few seconds, and when the pointer has
    /// been still a long while, a stretch or a yawn in turn. Only while idle and calm.
    private func updateFidget(now: Double, still: Double) {
        if let f = fidget {
            let dur = f.kind == .tap ? KlayMotion.Tap.dur : KlayMotion.Stretch.dur
            if now - f.start >= dur || state != .idle || hovered { fidget = nil }
            return
        }
        let calm = !isMini && state == .idle && !hovered && dancingLevel < 0.01
            && now >= waveUntil && eyeOverride == nil && !locks.contains("sy")
        guard calm else {
            nextFidget = max(nextFidget, now + 2)
            return
        }
        guard now >= nextFidget else { return }
        let I = KlayMotion.Idle.self
        nextFidget = now + Double.random(in: I.fidget)
        if still > I.longAfter && now >= nextLong {
            nextLong = now + Double.random(in: I.longEvery)
            longYawn.toggle()
            if longYawn {
                triggerEmote(.yawn, duration: 2.2)
                return
            }
            fidget = Fidget(kind: .stretch, start: now, side: 1)
            let S = KlayMotion.Stretch.self
            let up = CGFloat(S.up * 1000)
            let hold = CGFloat((S.hold - S.up) * 1000)
            let down = CGFloat((S.dur - S.hold) * 1000)
            anim("sy", keys: [
                TweenKey(target: 1.06, duration: up,   ease: Ease.inOut),
                TweenKey(target: 1.06, duration: hold, ease: Ease.lin),
                TweenKey(target: 1,    duration: down, ease: Ease.back),
            ])
            anim("sx", keys: [
                TweenKey(target: 0.97, duration: up,   ease: Ease.inOut),
                TweenKey(target: 0.97, duration: hold, ease: Ease.lin),
                TweenKey(target: 1,    duration: down, ease: Ease.back),
            ])
            return
        }
        fidget = Fidget(kind: .tap, start: now, side: Bool.random() ? -1 : 1)
    }

    /// Where the body is, for the limbs' inertia: glyph units and radians.
    private func bodyPose(now: Double) -> BodyPose {
        let L = KlayMotion.Lean.self
        let u = BotEngine.unitsPerR
        var x = ox * u + lean.x.value * L.shift
        var y = oy * u - (lean.y.value * L.rise + hoverLift * KlayMotion.Hover.rise)
        if dancingLevel > 0.001 {
            let d = KlayMotion.dance(time: now, level: dancingLevel)
            x += d.dx * u
            y += d.dy * u
        }
        return BodyPose(x: x, y: y, lean: lean.x.value * L.tilt, tilt: tilt)
    }

    private func updateLimbs(now: Double, t: CGFloat, dt: Double, waving: Bool) {
        var target = KlayPaint.limbTargets(state: state, t: t, waving: waving ? hands : 0, look: yaw)
        if let f = fidget {
            let ft = now - f.start
            switch f.kind {
            case .tap:
                if f.side < 0 { target.lf.y -= KlayMotion.footTapLift(ft) }
                else { target.rf.y -= KlayMotion.footTapLift(ft) }
            case .stretch:
                let k = KlayMotion.stretchAmount(ft)
                let h = KlayMotion.Stretch.hands
                target.lh = KlayPaint.blend(target.lh, CGPoint(x: -h.x, y: h.y), k)
                target.rh = KlayPaint.blend(target.rh, h, k)
            }
        }

        // The body's motion since last frame, seen from Klay's frame: a limb keeps `inertia`
        // of its place in the world, then its spring brings it back (lag, overshoot, settle).
        let body = bodyPose(now: now)
        let prev = bodyPrev ?? body
        bodyPrev = body
        let dx = clamp(body.x - prev.x, -KlayMotion.maxStep, KlayMotion.maxStep)
        let dy = clamp(body.y - prev.y, -KlayMotion.maxStep, KlayMotion.maxStep)
        let dLean = clamp(body.lean - prev.lean, -KlayMotion.maxTurn, KlayMotion.maxTurn)
        let dTilt = clamp(body.tilt - prev.tilt, -KlayMotion.maxTurn, KlayMotion.maxTurn)
        let soles = CGPoint(x: 0, y: KlayPaint.bottom)
        func carry(_ sp: inout KlaySpring2, to p: CGPoint, _ c: KlayMotion.Limb) {
            sp.shift(dx: -dx * c.inertia, dy: -dy * c.inertia)
            sp.rotate(about: soles, by: -dLean * c.inertia)
            sp.rotate(about: .zero, by: -dTilt * c.inertia)
            sp.step(towards: p, dt: dt, response: c.response, damping: c.damping)
        }
        carry(&springLH, to: target.lh, KlayMotion.hand)
        carry(&springRH, to: target.rh, KlayMotion.hand)
        carry(&springLF, to: target.lf, KlayMotion.foot)
        carry(&springRF, to: target.rf, KlayMotion.foot)
        limbs = KlayPaint.Limbs(lh: springLH.point, rh: springRH.point,
                                lf: springLF.point, rf: springRF.point)
    }

    // MARK: - Geometry

    /// Glyph units → canvas points for the main Klay in a canvas of width `W`.
    private func glyphScale(_ W: CGFloat) -> CGFloat {
        KlayPaint.glyphScale(canvasWidth: W)
    }

    /// World-space centre of Klay's full height (glyph top to soles) or of the mini disc.
    func bodyCenter(size: CGSize) -> CGPoint {
        let R = size.width * 0.3
        return CGPoint(x: size.width / 2 + ox * R,
                       y: size.height / 2 + particleOverhang / 2 + oy * R)
    }

    // MARK: - Dance transform

    /// Applies a 112-BPM dance bounce/sway around Klay's feet (KlayMotion.dance).
    /// Call this on a copy of the GraphicsContext before drawing.
    func applyDance(_ ctx: inout GraphicsContext, size: CGSize) {
        guard dancingLevel > 0.001 else { return }
        let W = size.width, R = W * 0.3
        let c = bodyCenter(size: size)
        let footOffset = isMini ? R : (KlayPaint.bottom - KlayPaint.centerY) * glyphScale(W)
        let px = c.x
        let py = c.y + footOffset
        let d = KlayMotion.dance(time: CACurrentMediaTime(), level: dancingLevel)
        ctx.translateBy(x: px + d.dx * R, y: py + d.dy * R)
        ctx.rotate(by: .radians(Double(d.rot)))
        ctx.scaleBy(x: d.sx, y: d.sy)
        ctx.translateBy(x: -px, y: -py)
    }

    // MARK: - Draw

    /// Draws Klay: the glow of the state's colour, legs, glyph, arms, then his eyes and blush;
    /// while searching, the binoculars instead: two round lenses around his eyes, which show
    /// magnified inside them, over the arms and the cheeks, the hands gripping their sides in
    /// front. For a mini Klay, the white glyph and eyes on a disc of its colour.
    /// The badge and particles are drawn by drawHandsAndExtras, on top.
    func draw(context: GraphicsContext, size: CGSize) {
        let W = size.width
        let R = W * 0.3
        let c = bodyCenter(size: size)
        if isMini {
            drawMini(context, R: R, cx: c.x, cy: c.y)
        } else {
            drawMain(context, W: W, cx: c.x, cy: c.y)
        }
    }

    /// Badge and particles, drawn over Klay (they don't spin with him).
    func drawHandsAndExtras(context: GraphicsContext, size: CGSize) {
        let R = size.width * 0.3
        let c = bodyCenter(size: size)

        // Badge
        if let badge = badge, badgeS > 0.01 {
            drawBadge(context: context, badge: badge, R: R, cx: c.x, cy: c.y)
        }

        // Particles
        drawParticles(context: context, R: R, cx: c.x, cy: c.y)
    }

    // MARK: - Private draw helpers

    private func drawMain(_ context: GraphicsContext, W: CGFloat, cx: CGFloat, cy: CGFloat) {
        let s = glyphScale(W)              // canvas points per glyph unit
        let hubX = cx
        let hubY = cy - KlayPaint.centerY * s

        // Glow of the state colour behind the rays.
        if tint > 0.01 {
            KlayPaint.drawGlow(context, center: CGPoint(x: hubX, y: hubY - 70 * s),
                               radius: 380 * s, color: colorFromTuple(col), amount: tint)
        }

        var ctx = context
        ctx.translateBy(x: hubX, y: hubY)
        // Lean: the whole figure turns towards where Klay looks, about the soles; looking
        // up lifts and stretches him a little, and he rises towards a pointer on him.
        let L = KlayMotion.Lean.self
        let soles = KlayPaint.bottom * s
        ctx.translateBy(x: lean.x.value * L.shift * s,
                        y: -(lean.y.value * L.rise + hoverLift * KlayMotion.Hover.rise) * s)
        ctx.translateBy(x: 0, y: soles)
        ctx.rotate(by: .radians(Double(lean.x.value * L.tilt)))
        ctx.scaleBy(x: 1, y: 1 + lean.y.value * L.stretch)
        ctx.translateBy(x: 0, y: -soles)
        if abs(roll) > 0.001 {
            // Spins turn the whole of Klay around the middle of its height.
            ctx.translateBy(x: 0, y: KlayPaint.centerY * s)
            ctx.rotate(by: .radians(Double(roll)))
            ctx.translateBy(x: 0, y: -KlayPaint.centerY * s)
        }
        if tilt != 0 { ctx.rotate(by: .radians(Double(tilt))) }
        ctx.scaleBy(x: sx * s, y: sy * s)
        let showLimbs = W * KlayPaint.glyphSpan >= KlayPaint.limbsMinPx
        // Searching: binoculars up around the eyes, which show magnified in them, over the
        // arms and the cheeks; the hands grip their sides in front.
        let binoculars = state == .searching
            ? KlayPaint.Binoculars(look: yaw, shape: currentEyeShape(),
                                   gaze: KlayMotion.gaze(yaw: yaw, pitch: pitch), scale: es, open: open,
                                   time: CGFloat(CACurrentMediaTime()))
            : nil
        KlayPaint.drawFigure(ctx, limbs: showLimbs ? limbs : nil, binoculars: binoculars)
        if binoculars == nil {
            KlayPaint.drawBlush(ctx, amount: blush,
                                dx: KlayMotion.gaze(yaw: yaw, pitch: pitch).eye.x * 0.8)
            drawEyes(ctx, mult: 1, center: .zero)
        }
    }

    /// Mini Klay: the white glyph and eyes on a disc of the agent's or service's colour.
    private func drawMini(_ context: GraphicsContext, R: CGFloat, cx: CGFloat, cy: CGFloat) {
        let disc = bodyColor.map { Color(cgColor: $0) } ?? colorFromTuple(cgColorToTuple(StateColor.idle))
        var ctx = context
        ctx.translateBy(x: cx, y: cy)
        if tilt != 0 { ctx.rotate(by: .radians(Double(tilt))) }
        ctx.scaleBy(x: sx, y: sy)
        ctx.fill(Path(ellipseIn: CGRect(x: -R, y: -R, width: R * 2, height: R * 2)), with: .color(disc))

        // The glyph fills the disc: 1.55 R wide, its hub a touch below the centre.
        let s = R * 1.55 / KlayGlyph.width
        ctx.scaleBy(x: s, y: s)
        ctx.translateBy(x: 0, y: 70)
        KlayPaint.drawGlyph(ctx)
        drawEyes(ctx, mult: 1.1, center: .zero)
    }

    /// The eye shape for this frame: emote or state, happy while dancing, shut mid-stretch.
    private func currentEyeShape() -> EyeShape {
        var shape = eyeOverride ?? cfg.eye
        // Dance: happy eyes in calm states
        if isDancing && dancingLevel > 0.15 && !isMini && (state == .idle || state == .finished) {
            shape = .happy
        }
        // Stretching: eyes shut in the middle of it.
        if let f = fidget, f.kind == .stretch, eyeOverride == nil {
            let ft = CACurrentMediaTime() - f.start
            if ft > KlayMotion.Stretch.eyesFrom && ft < KlayMotion.Stretch.eyesTo { shape = .closed }
        }
        return shape
    }

    /// Eyes in Klay's frame (glyph units), placed by the gaze (KlayMotion.gaze): the whites
    /// shift and narrow on the side he turns to, the pupils move further inside.
    private func drawEyes(_ ctx: GraphicsContext, mult: CGFloat, center: CGPoint) {
        KlayPaint.drawEyes(ctx, shape: currentEyeShape(), mult: mult, center: center,
                           gaze: KlayMotion.gaze(yaw: yaw, pitch: pitch), scale: es, open: open,
                           time: CGFloat(CACurrentMediaTime()))
    }

    private func drawBadge(context: GraphicsContext, badge: BadgeType, R: CGFloat, cx: CGFloat, cy: CGFloat) {
        let bs = badgeS * (isMini ? 1.25 : 1)
        let bx = cx - R * (isMini ? 0.72 : 0.95) * sx
        let by = cy - R * (isMini ? 0.72 : 0.62) * sy
        var ctx = context
        ctx.translateBy(x: bx, y: by)
        ctx.scaleBy(x: bs, y: bs)
        let now = CGFloat(CACurrentMediaTime())

        switch badge {
        case .dots(let col):
            if isMini {
                // Mini: animated pulsing dot
                let phase = (now * 2.4).truncatingRemainder(dividingBy: 1)
                let dotR = R * 0.22 * (1 + 0.25 * sin(phase * .pi * 2))
                var outer = Path()
                outer.addEllipse(in: CGRect(x: -R*0.2, y: -R*0.2, width: R*0.4, height: R*0.4))
                ctx.fill(outer, with: .color(.black))
                var dot = Path()
                dot.addEllipse(in: CGRect(x: -dotR, y: -dotR, width: dotR*2, height: dotR*2))
                ctx.fill(dot, with: .color(Color(cgColor: col)))
            } else {
                // Pill badge with animated dots (prototype style)
                let pw: CGFloat = R * 0.72
                let ph: CGFloat = R * 0.36
                ctx.fill(KlayPaint.roundedRect(CGRect(x: -pw/2, y: -ph/2, width: pw, height: ph), ph/2),
                         with: .color(Color(cgColor: col)))
                for i in 0..<3 {
                    let phase = ((now * 2.4 - CGFloat(i) * 0.22).truncatingRemainder(dividingBy: 1) + 1).truncatingRemainder(dividingBy: 1)
                    let dotR = R * 0.055 * (1 + 0.4 * max(0, sin(phase * .pi * 2)))
                    var dot = Path()
                    dot.addEllipse(in: CGRect(x: (CGFloat(i)-1)*R*0.18 - dotR, y: -dotR, width: dotR*2, height: dotR*2))
                    ctx.fill(dot, with: .color(StateColor.mark(on: col)))
                }
            }

        case .bang(let col), .question(let col):
            var ring = Path()
            ring.addEllipse(in: CGRect(x: -R*0.3, y: -R*0.3, width: R*0.6, height: R*0.6))
            ctx.fill(ring, with: .color(.black))
            var inner = Path()
            inner.addEllipse(in: CGRect(x: -R*0.23, y: -R*0.23, width: R*0.46, height: R*0.46))
            ctx.fill(inner, with: .color(Color(cgColor: col)))
            if !isMini {
                let text = badge == .bang(col) ? "!" : "?"
                ctx.draw(Text(text).font(.system(size: R*0.32, weight: .black)).foregroundColor(StateColor.mark(on: col)),
                         at: CGPoint(x: 0, y: R*0.02))
            }

        case .dot(let col):
            var outer = Path()
            outer.addEllipse(in: CGRect(x: -R*0.2, y: -R*0.2, width: R*0.4, height: R*0.4))
            ctx.fill(outer, with: .color(.black))
            var inner = Path()
            inner.addEllipse(in: CGRect(x: -R*0.135, y: -R*0.135, width: R*0.27, height: R*0.27))
            ctx.fill(inner, with: .color(Color(cgColor: col)))
        }
    }

    private func drawParticles(context: GraphicsContext, R: CGFloat, cx: CGFloat, cy: CGFloat) {
        for p in particles {
            guard p.age > 0 else { continue }
            let k = CGFloat(p.age / p.life)
            let a = k < 0.2 ? k / 0.2 : 1 - (k - 0.2) / 0.8
            let px = cx + (p.x + p.vx * CGFloat(p.age)) * R * 1.3
            let py = cy + (p.y + p.vy * CGFloat(p.age)) * R * 1.3
            let sz = R * p.size * (1 + k * 0.4)

            var pctx = context
            pctx.translateBy(x: px, y: py)
            pctx.opacity *= Double(min(max(a, 0), 1))

            switch p.type {
            case .heart:
                pctx.rotate(by: .radians(sin(CGFloat(p.age) * 6) * 0.3))
                pctx.fill(KlayPaint.heartShape(size: sz), with: .color(KlayPaint.heartColor))
            case .star:
                pctx.rotate(by: .radians(p.rot + CGFloat(p.age) * 2))
                pctx.fill(KlayPaint.starShape(outer: sz, inner: sz*0.45), with: .color(KlayPaint.starColor))
            case .spark:
                pctx.rotate(by: .radians(p.rot))
                pctx.fill(KlayPaint.starShape(outer: sz*0.8, inner: sz*0.18), with: .color(.white))
            case .sweat:
                var drop = Path()
                drop.move(to: CGPoint(x: 0, y: -sz))
                drop.addQuadCurve(to: CGPoint(x: 0, y: sz*0.6), control: CGPoint(x: sz*0.8, y: sz*0.2))
                drop.addQuadCurve(to: CGPoint(x: 0, y: -sz), control: CGPoint(x: -sz*0.8, y: sz*0.2))
                pctx.fill(drop, with: .color(Color(hex: "#7CC7FF")))
            case .z:
                pctx.draw(Text("z").font(.system(size: sz*1.9, weight: .bold)).foregroundColor(Color(red: 0.82, green: 0.86, blue: 0.92)),
                          at: .zero)
            }
        }
    }

    // MARK: - Tween helpers

    func anim(_ key: String, keys: [TweenKey], onComplete: (() -> Void)? = nil) {
        let current = getProperty(key)
        tweens[key] = Tween(property: key, keys: keys, keyIndex: 0,
                            from: current, startTime: CACurrentMediaTime() * 1000,
                            onComplete: onComplete)
        locks.insert(key)
    }

    private func setTarget(key: String, value: CGFloat) {
        guard !locks.contains(key) else { return }
        switch key {
        case "tint":  tint  += (value - tint)  // immediate target, smoothed in update
        case "tilt":  tgTilt = value
        default: break
        }
    }

    private func setProperty(_ key: String, value: CGFloat) {
        switch key {
        case "yaw":           yaw           = value
        case "pitch":         pitch         = value
        case "roll":          roll          = value
        case "tilt":          tilt          = value
        case "open":          open          = value
        case "sx":            sx            = value
        case "sy":            sy            = value
        case "oy":            oy            = value
        case "ox":            ox            = value
        case "tint":          tint          = value
        case "hands":         hands         = value
        case "blush":         blush         = value
        case "es":            es            = value
        case "badgeS":        badgeS        = value
        default: break
        }
    }

    private func getProperty(_ key: String) -> CGFloat {
        switch key {
        case "yaw":           return yaw
        case "pitch":         return pitch
        case "roll":          return roll
        case "tilt":          return tilt
        case "open":          return open
        case "sx":            return sx
        case "sy":            return sy
        case "oy":            return oy
        case "ox":            return ox
        case "tint":          return tint
        case "hands":         return hands
        case "blush":         return blush
        case "es":            return es
        case "badgeS":        return badgeS
        default:              return 0
        }
    }
}

// MARK: - Math helpers

func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat { a + (b-a) * t }
private func clamp(_ v: CGFloat, _ lo: CGFloat, _ hi: CGFloat) -> CGFloat { max(lo, min(hi, v)) }

private func cgColorToTuple(_ c: CGColor) -> (CGFloat, CGFloat, CGFloat) {
    guard let comps = c.components, comps.count >= 3 else { return (1,1,1) }
    return (comps[0], comps[1], comps[2])
}

private func mix3(_ a: (CGFloat,CGFloat,CGFloat), _ b: (CGFloat,CGFloat,CGFloat), _ t: CGFloat) -> (CGFloat,CGFloat,CGFloat) {
    (lerp(a.0,b.0,t), lerp(a.1,b.1,t), lerp(a.2,b.2,t))
}

private func mixColor(_ a: (CGFloat,CGFloat,CGFloat), _ b: (CGFloat,CGFloat,CGFloat), _ t: CGFloat) -> (CGFloat,CGFloat,CGFloat) {
    mix3(a, b, t)
}

private func colorFromTuple(_ t: (CGFloat,CGFloat,CGFloat)) -> Color {
    Color(red: Double(t.0), green: Double(t.1), blue: Double(t.2))
}

private func badgeString(_ b: BadgeType?) -> String {
    guard let b else { return "none" }
    func hex(_ c: CGColor) -> String {
        guard let k = c.components, k.count >= 3 else { return "?" }
        return "\(Int(k[0]*255)).\(Int(k[1]*255)).\(Int(k[2]*255))"
    }
    switch b {
    case .dots(let c):     return "dots-\(hex(c))"
    case .bang(let c):     return "bang-\(hex(c))"
    case .question(let c): return "q-\(hex(c))"
    case .dot(let c):      return "dot-\(hex(c))"
    }
}

private func emoteEyeShape(_ e: BotEmote) -> EyeShape {
    switch e {
    case .love:      return .heart
    case .surprised: return .dot
    case .proud:     return .star
    case .wink:      return .wink
    case .yawn:      return .tired
    case .happy:     return .happy
    case .annoyed:   return .line
    }
}

// Equatable for BadgeType (needed for comparing)
extension BadgeType: Equatable {
    static func == (lhs: BadgeType, rhs: BadgeType) -> Bool {
        switch (lhs, rhs) {
        case (.dots, .dots): return true
        case (.bang, .bang): return true
        case (.question, .question): return true
        case (.dot, .dot): return true
        default: return false
        }
    }
}
