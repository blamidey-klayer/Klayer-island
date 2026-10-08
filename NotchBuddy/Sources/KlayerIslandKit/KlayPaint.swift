import SwiftUI

/// Klay's look, shared by every surface that draws him: BotEngine (the island, the
/// mini Klays, the desktop Klay), the launch greeting and the upload
/// sequence.
///
/// The body is the Klayer glyph (KlayGlyph), white on the dark island and never
/// reshaped. Klay's character comes from what is added around it: two round white eyes
/// with a teal-deep rim on the solid hub under the rays, noodle arms with round hands,
/// two little legs with oval feet, and a glow of the state's colour behind the rays.
///
/// Sizes are in glyph units (the glyph is 797 × 512, y down). "Klay's frame" has its
/// origin on the hub, the solid part of the glyph under the rays, where the face sits.
/// Port of the Draw section of tools/klay-preview/src/engine.ts.
enum KlayPaint {

    // MARK: - Geometry (glyph units)

    /// Hub centre in the glyph.
    static let hub = CGPoint(x: 398.5, y: 400)
    /// Eyes, relative to the hub centre: two round eyes, white with a teal-deep rim.
    static let eyeDX: CGFloat = 56
    static let eyeDY: CGFloat = -6
    static let eyeR: CGFloat = 52
    static let eyeRim: CGFloat = 9
    /// The pupil (or whatever shape the eye takes) inside each eye.
    static let eyeW: CGFloat = 33
    static let eyeH: CGFloat = 52
    /// Shoulders and hips, relative to the hub centre (right side; the left mirrors).
    /// The shoulders sit on the hub, inside the rays.
    static let shoulder = CGPoint(x: 82, y: 50)
    static let hip = CGPoint(x: 17, y: 104)
    /// Where the hands and feet rest (right side; the left mirrors).
    static let handRest = CGPoint(x: 168, y: 150)
    static let footRest = CGPoint(x: 36, y: 212)
    static let limbW: CGFloat = 26
    /// Teal-deep rim around the arms, which are drawn in front of the glyph.
    static let limbRim: CGFloat = 7
    static let handR: CGFloat = 26
    static let footRX: CGFloat = 32
    static let footRY: CGFloat = 15
    /// Binoculars of the searching state, held up in front of the eyes: two rounded
    /// teal-deep barrels joined by a bridge, a teal-light lens with a brume rim and a
    /// white glint at the front of each barrel. Barrel centre (right side; the left mirrors).
    static let binoBarrel = CGPoint(x: 56, y: -10)
    static let binoBarrelW: CGFloat = 92
    static let binoBarrelH: CGFloat = 104
    static let binoBarrelR: CGFloat = 34
    static let binoBridgeW: CGFloat = 40
    static let binoBridgeH: CGFloat = 30
    static let binoLensR: CGFloat = 36
    static let binoLensRim: CGFloat = 8
    /// Glint centre, from the lens centre.
    static let binoGlint = CGPoint(x: -13, y: -13)
    static let binoGlintR: CGFloat = 9
    /// How far the binoculars follow the look sweep: x offset = yaw × this.
    static let binoLook: CGFloat = 18
    /// Where both hands hold the barrels (right side; the left mirrors).
    static let binoHand = CGPoint(x: 112, y: 18)
    /// Top and bottom of the whole character (glyph top, soles), relative to the hub.
    static let top: CGFloat = -400
    static let bottom: CGFloat = 212 + 15
    /// Vertical offset that centres the character's full height on a canvas centre.
    static let centerY: CGFloat = (top + bottom) / 2
    /// Fraction of the canvas width the glyph spans (main Klay).
    static let glyphSpan: CGFloat = 0.62
    /// Below this glyph width (px) the limbs would be sub-pixel noise: they are left out.
    static let limbsMinPx: CGFloat = 30

    // MARK: - Colours

    /// Glyph white on the dark island (the brand's glyph-white).
    static let body = Color.white
    /// Eyes, pupils and slot: Klayer teal-deep #071B20.
    static let ink = Color(red: 7 / 255, green: 27 / 255, blue: 32 / 255)
    /// Klayer brume #ECEDE7, the bottom of the mailbox gradient and the rim of the binocular lenses.
    static let brume = Color(red: 236 / 255, green: 237 / 255, blue: 231 / 255)
    /// Binocular lenses: Klayer teal-light #3E7280.
    static let lensColor = Color(red: 62 / 255, green: 114 / 255, blue: 128 / 255)
    static let heartColor = Color(red: 232 / 255, green: 68 / 255, blue: 94 / 255)   // #E8445E
    static let starColor = Color(red: 227 / 255, green: 162 / 255, blue: 26 / 255)   // #E3A21A
    static let blushColor = Color(red: 1, green: 120 / 255, blue: 150 / 255)

    // MARK: - Limbs

    /// Hands and feet in Klay's frame (glyph units).
    struct Limbs: Equatable, Sendable {
        var lh: CGPoint
        var rh: CGPoint
        var lf: CGPoint
        var rf: CGPoint

        static let rest = Limbs(
            lh: CGPoint(x: -KlayPaint.handRest.x, y: KlayPaint.handRest.y),
            rh: KlayPaint.handRest,
            lf: CGPoint(x: -KlayPaint.footRest.x, y: KlayPaint.footRest.y),
            rf: KlayPaint.footRest)

        /// Moves every point a fraction `k` of the way towards `target`.
        func eased(towards target: Limbs, _ k: CGFloat) -> Limbs {
            func e(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
                CGPoint(x: a.x + (b.x - a.x) * k, y: a.y + (b.y - a.y) * k)
            }
            return Limbs(lh: e(lh, target.lh), rh: e(rh, target.rh),
                         lf: e(lf, target.lf), rf: e(rf, target.rf))
        }
    }

    /// Where the hands and feet want to be for a state, at time `t` (seconds).
    /// `waving` (0…1) blends the right hand into the hello wave.
    static func limbTargets(state: BotState, t: CGFloat, waving: CGFloat) -> Limbs {
        func rest(_ sd: CGFloat) -> CGPoint {
            CGPoint(x: sd * handRest.x, y: handRest.y + sin(t * 1.8 + sd) * 3)
        }
        var l = Limbs(lh: rest(-1), rh: rest(1),
                      lf: CGPoint(x: -footRest.x, y: footRest.y),
                      rf: CGPoint(x: footRest.x, y: footRest.y))

        switch state {
        case .working:
            // Busy hands, typing in turn, and a little march in place.
            let k = sin(t * 9)
            l.lh = CGPoint(x: -132, y: 104 + k * 14)
            l.rh = CGPoint(x: 132, y: 104 - k * 14)
            l.lf = CGPoint(x: -footRest.x, y: footRest.y - max(0, sin(t * 6)) * 10)
            l.rf = CGPoint(x: footRest.x, y: footRest.y - max(0, -sin(t * 6)) * 10)
        case .thinking:
            // Hand on the chin.
            l.rh = CGPoint(x: 52 + sin(t * 2) * 3, y: 92)
        case .searching:
            // Both hands hold the binoculars (drawBinoculars) by the barrels.
            l.lh = CGPoint(x: -binoHand.x, y: binoHand.y)
            l.rh = binoHand
        case .approval:
            // Both arms up, waving for attention.
            let k = sin(t * 11)
            l.lh = CGPoint(x: -196, y: -66 + k * 14)
            l.rh = CGPoint(x: 196, y: -66 - k * 14)
        case .question:
            // Scratching the side of the head.
            l.rh = CGPoint(x: 150, y: -40 + sin(t * 14) * 6)
        case .error:
            l.lh = CGPoint(x: -112, y: 150)
            l.rh = CGPoint(x: 112, y: 150)
        case .finished:
            // Arms up in a V.
            l.lh = CGPoint(x: -214, y: -96 + sin(t * 4) * 5)
            l.rh = CGPoint(x: 214, y: -96 - sin(t * 4) * 5)
        case .ratelimit:
            l.lh = CGPoint(x: -118, y: 158)
            l.rh = CGPoint(x: 118, y: 158)
        case .sleeping:
            l.lh = CGPoint(x: -122, y: 146)
            l.rh = CGPoint(x: 122, y: 146)
        case .dizzy:
            l.lh = CGPoint(x: -170 + sin(t * 7) * 30, y: 40 + cos(t * 9) * 50)
            l.rh = CGPoint(x: 170 + sin(t * 8 + 1) * 30, y: 40 + cos(t * 7 + 2) * 50)
            l.lf = CGPoint(x: -footRest.x - max(0, sin(t * 5)) * 12, y: footRest.y)
            l.rf = CGPoint(x: footRest.x + max(0, -sin(t * 5)) * 12, y: footRest.y)
        case .idle:
            break
        }

        if waving > 0 {
            // The hello: right hand up, waving fast.
            l.rh = blend(l.rh, waveHand(t: t), waving)
        }
        return l
    }

    /// The right hand's position in the hello wave at time `t` (seconds).
    static func waveHand(t: CGFloat) -> CGPoint {
        CGPoint(x: 206 + cos(13 * t) * 16, y: -40 - sin(13 * t) * 26)
    }

    static func blend(_ a: CGPoint, _ b: CGPoint, _ k: CGFloat) -> CGPoint {
        CGPoint(x: a.x + (b.x - a.x) * k, y: a.y + (b.y - a.y) * k)
    }

    /// The "arms open" pose of the drop zone: both hands out to the sides at (±200, −40),
    /// welcoming the file. In Klay's frame (glyph units).
    static func armsOpenTargets() -> (lh: CGPoint, rh: CGPoint) {
        (lh: CGPoint(x: -200, y: -40), rh: CGPoint(x: 200, y: -40))
    }

    // MARK: - Body parts (all in Klay's frame, glyph units)

    /// The glyph itself, filled white, positioned so the hub sits on the origin.
    static func drawGlyph(_ ctx: GraphicsContext) {
        var c = ctx
        c.translateBy(x: -hub.x, y: -hub.y)
        c.fill(KlayGlyph.path, with: .color(body))
    }

    /// Legs with little oval feet, drawn behind the glyph.
    static func drawLegs(_ ctx: GraphicsContext, lf: CGPoint, rf: CGPoint) {
        let style = StrokeStyle(lineWidth: limbW, lineCap: .round, lineJoin: .round)
        let legs: [(CGFloat, CGPoint)] = [(-1, lf), (1, rf)]
        for (sd, foot) in legs {
            let hipPt = CGPoint(x: sd * hip.x, y: hip.y)
            let knee = CGPoint(x: (hipPt.x + foot.x) / 2 + sd * 8, y: (hipPt.y + foot.y) / 2)
            var leg = Path()
            leg.move(to: hipPt)
            leg.addQuadCurve(to: CGPoint(x: foot.x, y: foot.y - footRY * 0.4), control: knee)
            ctx.stroke(leg, with: .color(body), style: style)
            let footRect = CGRect(x: foot.x + sd * 8 - footRX, y: foot.y - footRY,
                                  width: footRX * 2, height: footRY * 2)
            ctx.fill(Path(ellipseIn: footRect), with: .color(body))
        }
    }

    /// The noodle arm on side `sd` (-1 left, +1 right), from the shoulder to `hand`. The
    /// elbow bows outwards and down, which keeps the noodle look in every pose.
    static func armPath(side sd: CGFloat, hand: CGPoint) -> Path {
        let sh = CGPoint(x: sd * shoulder.x, y: shoulder.y)
        let elbow = CGPoint(x: (sh.x + hand.x) / 2 + sd * 26, y: (sh.y + hand.y) / 2 + 20)
        var arm = Path()
        arm.move(to: sh)
        arm.addQuadCurve(to: hand, control: elbow)
        return arm
    }

    /// Noodle arms with round hands, in front of the glyph and rimmed in teal-deep like
    /// the eyes, so a raised hand still reads over the white rays. A white disc over each
    /// shoulder hides where the rim starts, inside the hub. Port of drawKlayArms in
    /// tools/klay-preview/src/engine.ts.
    static func drawArms(_ ctx: GraphicsContext, lh: CGPoint, rh: CGPoint) {
        let style = StrokeStyle(lineWidth: limbW, lineCap: .round, lineJoin: .round)
        let rimStyle = StrokeStyle(lineWidth: limbW + 2 * limbRim, lineCap: .round, lineJoin: .round)
        let arms: [(CGFloat, CGPoint)] = [(-1, lh), (1, rh)]
        for (sd, hand) in arms {
            let arm = armPath(side: sd, hand: hand)
            ctx.stroke(arm, with: .color(ink), style: rimStyle)
            ctx.fill(circle(hand, handR + limbRim), with: .color(ink))
            ctx.stroke(arm, with: .color(body), style: style)
            ctx.fill(circle(hand, handR), with: .color(body))
            ctx.fill(circle(CGPoint(x: sd * shoulder.x, y: shoulder.y), limbW / 2 + limbRim + 1),
                     with: .color(body))
        }
    }

    /// Klay's body, in his frame: the legs behind the glyph, the glyph, then the
    /// binoculars (searching) and the arms in front of it, as the bench draws him.
    /// `limbs` nil leaves the legs and arms out (too small to read). `binoculars` is the
    /// yaw the binoculars follow, nil when Klay is not holding them. The caller draws
    /// the blush and the eyes on top, and no eyes while the binoculars are up.
    static func drawFigure(_ ctx: GraphicsContext, limbs: Limbs?, binoculars look: CGFloat? = nil) {
        if let limbs { drawLegs(ctx, lf: limbs.lf, rf: limbs.rf) }
        drawGlyph(ctx)
        if let look { drawBinoculars(in: ctx, look: look) }
        if let limbs { drawArms(ctx, lh: limbs.lh, rh: limbs.rh) }
    }

    /// The binoculars Klay holds up in the searching state, over the eyes (which are not
    /// drawn meanwhile). `look` is the yaw (−1…1): the binoculars follow the look sweep,
    /// x offset = yaw × 18. Port of drawKlayBinoculars in tools/klay-preview/src/engine.ts.
    static func drawBinoculars(in ctx: GraphicsContext, look: CGFloat) {
        var c = ctx
        c.translateBy(x: max(-1, min(1, look)) * binoLook, y: 0)
        c.fill(Path(CGRect(x: -binoBridgeW / 2, y: binoBarrel.y - binoBridgeH / 2,
                           width: binoBridgeW, height: binoBridgeH)),
               with: .color(ink))
        for sd: CGFloat in [-1, 1] {
            let center = CGPoint(x: sd * binoBarrel.x, y: binoBarrel.y)
            let barrel = CGRect(x: center.x - binoBarrelW / 2, y: center.y - binoBarrelH / 2,
                                width: binoBarrelW, height: binoBarrelH)
            c.fill(roundedRect(barrel, binoBarrelR), with: .color(ink))
            let lens = circle(center, binoLensR)
            c.fill(lens, with: .color(lensColor))
            c.stroke(lens, with: .color(brume), style: StrokeStyle(lineWidth: binoLensRim))
            c.fill(circle(CGPoint(x: center.x + binoGlint.x, y: center.y + binoGlint.y), binoGlintR),
                   with: .color(body))
        }
    }

    /// Klay in the drop zone: the glyph, wide eyes, legs at rest and both arms open
    /// (armsOpenTargets), centred on `center` in the context's coordinates. `height` is
    /// the figure's height, from the top of the glyph to the soles. `time` (seconds)
    /// drives the idle motion: a slow bob, hands that sway, a blink every 3.6 s. `look` is
    /// the gaze offset in glyph units, as in drawEyes. Port of drawKlayDrop in
    /// tools/klay-preview/src/engine.ts.
    static func drawDropInvite(_ ctx: GraphicsContext, center: CGPoint, height: CGFloat,
                               look: CGPoint = .zero, time: Double) {
        let s = height / (bottom - top)
        let t = CGFloat(time)
        let bob = sin(t * 1.8) * 8
        let pose = armsOpenTargets()
        let lh = CGPoint(x: pose.lh.x, y: pose.lh.y + sin(t * 1.8 - 1) * 6)
        let rh = CGPoint(x: pose.rh.x, y: pose.rh.y + sin(t * 1.8 + 1) * 6)
        let phase = time.truncatingRemainder(dividingBy: 3.6)
        let eyeOpen: CGFloat = phase < 0.14 ? CGFloat(abs(phase / 0.07 - 1)) : 1

        var c = ctx
        c.translateBy(x: center.x, y: center.y - centerY * s)
        c.scaleBy(x: s, y: s)
        c.translateBy(x: 0, y: bob)
        drawFigure(c, limbs: Limbs(lh: lh, rh: rh, lf: Limbs.rest.lf, rf: Limbs.rest.rf))
        drawEyes(c, shape: .wide, mult: 1, look: look, open: eyeOpen, time: t)
    }

    /// Pink cheeks under the eyes, `amount` 0…1.
    static func drawBlush(_ ctx: GraphicsContext, amount b: CGFloat) {
        guard b > 0.01 else { return }
        for sd: CGFloat in [-1, 1] {
            let rect = CGRect(x: sd * 74 - 20, y: 44 - 11, width: 40, height: 22)
            ctx.fill(Path(ellipseIn: rect), with: .color(blushColor.opacity(Double(0.55 * b))))
        }
    }

    /// The glow of the state's colour behind the rays, in canvas coordinates.
    static func drawGlow(_ ctx: GraphicsContext, center: CGPoint, radius: CGFloat,
                         color: Color, amount: CGFloat) {
        guard amount > 0.01, radius > 0 else { return }
        let gradient = Gradient(stops: [
            .init(color: color.opacity(Double(0.55 * amount)), location: 0),
            .init(color: color.opacity(Double(0.22 * amount)), location: 0.55),
            .init(color: color.opacity(0), location: 1),
        ])
        let side = radius * 2.1
        let rect = CGRect(x: center.x - side / 2, y: center.y - side / 2, width: side, height: side)
        ctx.fill(Path(rect), with: .radialGradient(gradient, center: center,
                                                   startRadius: 0, endRadius: radius))
    }

    /// The mailbox body: a white → brume rounded box of half-size (hw, hh), centred on the origin.
    static func drawBoxBody(_ ctx: GraphicsContext, hw: CGFloat, hh: CGFloat, corner: CGFloat) {
        let box = roundedRect(CGRect(x: -hw, y: -hh, width: hw * 2, height: hh * 2), corner)
        ctx.fill(box, with: .linearGradient(Gradient(colors: [body, brume]),
                                            startPoint: CGPoint(x: 0, y: -hh),
                                            endPoint: CGPoint(x: 0, y: hh)))
    }

    /// The mailbox slot, teal-deep, fully rounded.
    static func drawSlot(_ ctx: GraphicsContext, rect: CGRect) {
        guard rect.width > 0, rect.height > 0 else { return }
        ctx.fill(roundedRect(rect, min(rect.width / 2, rect.height / 2)), with: .color(ink))
    }

    // MARK: - Eyes

    /// Both eyes, in Klay's frame around `center`. `look` is the gaze offset in glyph
    /// units (x within ±14, y within ±12, y down): the eye follows it by 40 %, the pupil
    /// by 80 %. `mult` scales the eyes (minis and the mailbox use their own size).
    static func drawEyes(_ ctx: GraphicsContext, shape: EyeShape, mult: CGFloat,
                         center: CGPoint = .zero, look: CGPoint = .zero,
                         scale es: CGFloat = 1, open: CGFloat = 1, time: CGFloat) {
        let ew = eyeW * es * mult
        let eh = eyeH * es * mult
        let er = eyeR * es * mult
        let dx = eyeDX * mult
        let rimStyle = StrokeStyle(lineWidth: eyeRim * mult)
        for sd: CGFloat in [-1, 1] {
            var c = ctx
            c.translateBy(x: center.x + sd * dx + look.x * 0.4 * mult,
                          y: center.y + eyeDY * mult + look.y * 0.4 * mult)
            let eye = Path(ellipseIn: CGRect(x: -er, y: -er, width: er * 2, height: er * 2))
            c.fill(eye, with: .color(body))
            c.stroke(eye, with: .color(ink), style: rimStyle)
            c.translateBy(x: look.x * 0.8 * mult, y: look.y * 0.8 * mult)
            drawEyeShape(&c, shape: shape, w: ew, h: eh, sd: sd, open: open, time: time)
        }
    }

    /// One eye's pupil shape, centred on the origin. `sd` is -1 for the left eye, +1 for the right.
    static func drawEyeShape(_ ctx: inout GraphicsContext, shape: EyeShape, w: CGFloat, h: CGFloat,
                             sd: CGFloat, open: CGFloat, time t: CGFloat) {
        switch shape {
        case .wide:
            drawEyeShape(&ctx, shape: .pill, w: w * 1.16, h: h * 1.12, sd: sd, open: open, time: t)

        case .pill:
            let hh = max(h * open, w * 0.3)
            ctx.fill(roundedRect(CGRect(x: -w / 2, y: -hh / 2, width: w, height: hh), min(w / 2, hh / 2)),
                     with: .color(ink))

        case .dot:
            ctx.fill(Path(ellipseIn: CGRect(x: -w * 0.5, y: -w * 0.5, width: w, height: w)), with: .color(ink))

        case .line:
            ctx.rotate(by: .radians(Double(-sd * 0.25)))
            ctx.fill(roundedRect(CGRect(x: -w * 0.8, y: -w * 0.22, width: w * 1.6, height: w * 0.44), w * 0.22),
                     with: .color(ink))

        case .flat:
            ctx.fill(roundedRect(CGRect(x: -w * 0.75, y: -w * 0.21, width: w * 1.5, height: w * 0.42), w * 0.21),
                     with: .color(ink))

        case .happy:
            ctx.stroke(happyArc(w: w, h: h), with: .color(ink),
                       style: StrokeStyle(lineWidth: w * 0.42, lineCap: .round))

        case .closed:
            var p = Path()
            p.addArc(center: CGPoint(x: 0, y: -h * 0.12), radius: w * 0.68,
                     startAngle: .radians(.pi * 0.18), endAngle: .radians(.pi * 0.82), clockwise: false)
            ctx.stroke(p, with: .color(ink), style: StrokeStyle(lineWidth: w * 0.34, lineCap: .round))

        case .spiral:
            var p = Path()
            var a: CGFloat = 0
            while a < 4.4 * .pi {
                let r = w * 0.06 + a * w * 0.055
                let aa = a + t * 9 * sd
                let pt = CGPoint(x: cos(aa) * r, y: sin(aa) * r)
                if a == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
                a += 0.2
            }
            ctx.stroke(p, with: .color(ink), style: StrokeStyle(lineWidth: w * 0.2, lineCap: .round))

        case .heart:
            ctx.fill(heartShape(size: w * 1.15), with: .color(heartColor))

        case .star:
            ctx.rotate(by: .radians(Double(t * 1.5 * sd)))
            ctx.fill(starShape(outer: w, inner: w * 0.44), with: .color(starColor))

        case .tired:
            ctx.fill(roundedRect(CGRect(x: -w / 2, y: -h * 0.02, width: w, height: h * 0.38), w / 2),
                     with: .color(ink))
            ctx.fill(roundedRect(CGRect(x: -w * 0.62, y: -h * 0.1, width: w * 1.24, height: w * 0.22), w * 0.11),
                     with: .color(ink))

        case .wink:
            if sd < 0 {
                drawEyeShape(&ctx, shape: .pill, w: w, h: h, sd: sd, open: open, time: t)
            } else {
                ctx.stroke(happyArc(w: w, h: h), with: .color(ink),
                           style: StrokeStyle(lineWidth: w * 0.42, lineCap: .round))
            }

        case .cup:
            // Flat top, rounded bottom corners (U shape): the eyes while the slot is open.
            let hh = max(h * open, w * 0.3)
            let cr = min(w / 2, hh / 2)
            var p = Path()
            p.move(to: CGPoint(x: -w / 2, y: -hh / 2))
            p.addLine(to: CGPoint(x: w / 2, y: -hh / 2))
            p.addLine(to: CGPoint(x: w / 2, y: hh / 2 - cr))
            p.addQuadCurve(to: CGPoint(x: w / 2 - cr, y: hh / 2), control: CGPoint(x: w / 2, y: hh / 2))
            p.addLine(to: CGPoint(x: -w / 2 + cr, y: hh / 2))
            p.addQuadCurve(to: CGPoint(x: -w / 2, y: hh / 2 - cr), control: CGPoint(x: -w / 2, y: hh / 2))
            p.closeSubpath()
            ctx.fill(p, with: .color(ink))
        }
    }

    /// The upturned arc of the happy (and winking) eye.
    private static func happyArc(w: CGFloat, h: CGFloat) -> Path {
        var p = Path()
        p.addArc(center: CGPoint(x: 0, y: h * 0.2), radius: w * 0.7,
                 startAngle: .radians(.pi * 1.15), endAngle: .radians(.pi * 1.85), clockwise: false)
        return p
    }

    // MARK: - Shapes

    /// A circle of radius `r` around `c`.
    static func circle(_ c: CGPoint, _ r: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
    }

    /// A rounded rectangle whose radius never exceeds half its width or height.
    static func roundedRect(_ rect: CGRect, _ radius: CGFloat) -> Path {
        let r = max(0, min(radius, rect.width / 2, rect.height / 2))
        return Path(roundedRect: rect, cornerSize: CGSize(width: r, height: r), style: .circular)
    }

    static func heartShape(size s: CGFloat) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 0, y: s * 0.38))
        p.addCurve(to: CGPoint(x: 0, y: -s * 0.38),
                   control1: CGPoint(x: -s * 1.05, y: -s * 0.15),
                   control2: CGPoint(x: -s * 0.5, y: -s * 0.95))
        p.addCurve(to: CGPoint(x: 0, y: s * 0.38),
                   control1: CGPoint(x: s * 0.5, y: -s * 0.95),
                   control2: CGPoint(x: s * 1.05, y: -s * 0.15))
        p.closeSubpath()
        return p
    }

    static func starShape(outer ro: CGFloat, inner ri: CGFloat) -> Path {
        var p = Path()
        for i in 0..<10 {
            let r = i.isMultiple(of: 2) ? ro : ri
            let a = -CGFloat.pi / 2 + CGFloat(i) * .pi / 5
            let pt = CGPoint(x: cos(a) * r, y: sin(a) * r)
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        p.closeSubpath()
        return p
    }
}
