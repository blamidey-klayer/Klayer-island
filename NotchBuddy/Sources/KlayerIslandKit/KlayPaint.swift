import SwiftUI

/// Klay's look, shared by every surface that draws him: BotEngine (the island, the
/// mini Klays, the desktop Klay), the launch greeting and the drop sequence
/// (UploadCanvasView).
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
    /// Binoculars of the searching state, held up over the eyes and seen a little from
    /// above, so the length of the barrels shows: two teal-deep barrels, a narrow
    /// eyepiece tube on top (behind) over a wider objective tube whose end faces the
    /// viewer, with the teal-light glass in a brume rim; a central hinge with a focus
    /// knob joins them. Right side; the left mirrors. Mirror of BINO in engine.ts.
    enum Bino {
        /// Barrel axis.
        static let x: CGFloat = 84
        /// Eyepiece tube: top, bottom, half width, corner radius; brume ring across it.
        static let eyeTop: CGFloat = -142
        static let eyeBottom: CGFloat = -94
        static let eyeHW: CGFloat = 24
        static let eyeR: CGFloat = 10
        static let ringY: CGFloat = -128
        static let ringH: CGFloat = 8
        /// Objective tube: top, half width, top corner radius; its end (ellipse) at objY.
        static let objTop: CGFloat = -104
        static let objY: CGFloat = 0
        static let objHW: CGFloat = 52
        static let objR: CGFloat = 18
        static let objRY: CGFloat = 22
        /// Glass in the objective end: half axes, brume rim width.
        static let glassRX: CGFloat = 40
        static let glassRY: CGFloat = 15
        static let glassRim: CGFloat = 8
        /// White streak of light on the glass: an arc of a smaller ellipse, angles in π.
        static let shineRX: CGFloat = 28
        static let shineRY: CGFloat = 9
        static let shineFrom: CGFloat = 1.08
        static let shineTo: CGFloat = 1.42
        static let shineW: CGFloat = 6
        /// Central hinge, the bridge between the eyepiece tubes, the focus knob on top.
        static let hingeHW: CGFloat = 10
        static let hingeTop: CGFloat = -138
        static let hingeBottom: CGFloat = -36
        static let bridgeHW: CGFloat = 62
        static let bridgeTop: CGFloat = -124
        static let bridgeBottom: CGFloat = -106
        static let knobY: CGFloat = -142
        static let knobHW: CGFloat = 23
        static let knobHH: CGFloat = 13
        static let knobR: CGFloat = 9
        static let knobBand: CGFloat = 8
        /// The sweep: x offset = yaw × sweep, rotation = yaw × turn (rad) about the pivot.
        static let sweep: CGFloat = 45
        static let turn: CGFloat = 0.13
        static let pivot = CGPoint(x: 0, y: -60)
        /// Where each hand grips the outer side of an objective tube.
        static let hand = CGPoint(x: 146, y: -52)
    }
    /// Top and bottom of the whole character (glyph top, soles), relative to the hub.
    static let top: CGFloat = -400
    static let bottom: CGFloat = 212 + 15
    /// Vertical offset that centres the character's full height on a canvas centre.
    static let centerY: CGFloat = (top + bottom) / 2
    /// Fraction of the canvas width the glyph spans (main Klay): KlaySize's rule.
    static let glyphSpan: CGFloat = KlaySize.glyphSpan
    /// Below this glyph width (px) the limbs would be sub-pixel noise: they are left out.
    static let limbsMinPx: CGFloat = 30

    /// Canvas points per glyph unit of the main Klay drawn in a canvas `width` wide.
    static func glyphScale(canvasWidth width: CGFloat) -> CGFloat {
        width * glyphSpan / KlayGlyph.width
    }

    /// Canvas points per glyph unit of the island's Klay of layout diameter `d` (KlaySize): the
    /// island (BotEngine in BotPlacement's canvas) and the drop canvas draw him at this scale.
    static func glyphScale(diameter d: CGFloat) -> CGFloat {
        glyphScale(canvasWidth: KlaySize.canvasWidth(diameter: d))
    }

    // MARK: - Colours

    /// Glyph white on the dark island (the brand's glyph-white).
    static let body = Color.white
    /// Eyes and pupils: Klayer teal-deep #071B20.
    static let ink = Color(red: 7 / 255, green: 27 / 255, blue: 32 / 255)
    /// Klayer brume #ECEDE7, the rings and the rim of the binocular lenses.
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

    }

    /// Where the hands and feet want to be for a state, at time `t` (seconds).
    /// `waving` (0…1) blends the right hand into the hello wave.
    /// `look` is the yaw: in searching the hands follow the binoculars' sweep.
    static func limbTargets(state: BotState, t: CGFloat, waving: CGFloat, look: CGFloat = 0) -> Limbs {
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
            // Both hands grip the binoculars (drawBinoculars) and follow their sweep.
            l.lh = binocularsPoint(CGPoint(x: -Bino.hand.x, y: Bino.hand.y), look: look)
            l.rh = binocularsPoint(Bino.hand, look: look)
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

    /// Hands and feet of Klay in the drop sequence (UploadCanvasView): `arms` (0…1, a little
    /// over 1 while the pose overshoots) raises both hands from rest to the open pose
    /// (armsOpenTargets), where they sway a little with `time` (seconds); the feet stay at rest.
    /// Port of dropLimbs in tools/klay-preview/src/engine.ts.
    static func dropLimbs(arms: CGFloat, time: Double) -> Limbs {
        let t = CGFloat(time)
        let open = armsOpenTargets()
        var l = Limbs.rest
        l.lh = blend(l.lh, CGPoint(x: open.lh.x, y: open.lh.y + sin(t * 1.8 - 1) * 6), arms)
        l.rh = blend(l.rh, CGPoint(x: open.rh.x, y: open.rh.y + sin(t * 1.8 + 1) * 6), arms)
        return l
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

    /// Where a point of the binoculars (Klay's frame, at rest) is once they follow `look`.
    static func binocularsPoint(_ p: CGPoint, look: CGFloat) -> CGPoint {
        let k = max(-1, min(1, look))
        let a = k * Bino.turn
        let dx = p.x - Bino.pivot.x
        let dy = p.y - Bino.pivot.y
        return CGPoint(x: Bino.pivot.x + dx * cos(a) - dy * sin(a) + k * Bino.sweep,
                       y: Bino.pivot.y + dx * sin(a) + dy * cos(a))
    }

    /// The binoculars Klay holds up in the searching state, over the eyes (which are not
    /// drawn meanwhile). `look` is the yaw (−1…1): they follow the look sweep, x offset =
    /// yaw × 45 and a turn of yaw × 0.13 rad about the pivot (±0.08 rad at the scan's
    /// ±0.6). The hands grip them at Bino.hand (limbTargets). Port of
    /// drawKlayBinoculars in tools/klay-preview/src/engine.ts.
    static func drawBinoculars(in ctx: GraphicsContext, look: CGFloat) {
        typealias B = Bino
        let k = max(-1, min(1, look))
        var c = ctx
        c.translateBy(x: B.pivot.x + k * B.sweep, y: B.pivot.y)
        c.rotate(by: .radians(Double(k * B.turn)))
        c.translateBy(x: -B.pivot.x, y: -B.pivot.y)
        // Hinge, bridge and the eyepiece tubes with their brume rings, behind.
        c.fill(roundedRect(CGRect(x: -B.hingeHW, y: B.hingeTop,
                                  width: B.hingeHW * 2, height: B.hingeBottom - B.hingeTop), B.hingeHW),
               with: .color(ink))
        c.fill(Path(CGRect(x: -B.bridgeHW, y: B.bridgeTop,
                           width: B.bridgeHW * 2, height: B.bridgeBottom - B.bridgeTop)),
               with: .color(ink))
        for sd: CGFloat in [-1, 1] {
            let cx = sd * B.x
            c.fill(roundedRect(CGRect(x: cx - B.eyeHW, y: B.eyeTop,
                                      width: B.eyeHW * 2, height: B.eyeBottom - B.eyeTop), B.eyeR),
                   with: .color(ink))
            c.fill(Path(CGRect(x: cx - B.eyeHW, y: B.ringY - B.ringH / 2, width: B.eyeHW * 2, height: B.ringH)),
                   with: .color(brume))
        }
        // Objective tubes, their ends towards the viewer: glass in a brume rim, a streak of light.
        for sd: CGFloat in [-1, 1] {
            let end = CGPoint(x: sd * B.x, y: B.objY)
            c.fill(roundedRect(CGRect(x: end.x - B.objHW, y: B.objTop,
                                      width: B.objHW * 2, height: B.objY - B.objTop + B.objR), B.objR),
                   with: .color(ink))
            c.fill(ellipse(end, B.objHW, B.objRY), with: .color(ink))
            let glass = ellipse(end, B.glassRX, B.glassRY)
            c.fill(glass, with: .color(lensColor))
            c.stroke(glass, with: .color(brume), style: StrokeStyle(lineWidth: B.glassRim))
            var shine = Path()
            shine.addArc(center: .zero, radius: 1, startAngle: .radians(Double(.pi * B.shineFrom)),
                         endAngle: .radians(Double(.pi * B.shineTo)), clockwise: false)
            c.stroke(shine.applying(CGAffineTransform(translationX: end.x, y: end.y)
                                        .scaledBy(x: B.shineRX, y: B.shineRY)),
                     with: .color(body), style: StrokeStyle(lineWidth: B.shineW, lineCap: .round))
        }
        // Focus knob on top of the hinge.
        c.fill(roundedRect(CGRect(x: -B.knobHW, y: B.knobY - B.knobHH,
                                  width: B.knobHW * 2, height: B.knobHH * 2), B.knobR),
               with: .color(ink))
        c.fill(Path(CGRect(x: -B.knobHW, y: B.knobY - B.knobBand / 2, width: B.knobHW * 2, height: B.knobBand)),
               with: .color(brume))
    }

    /// Pink cheeks under the eyes, `amount` 0…1, shifted by `dx` with the eyes.
    static func drawBlush(_ ctx: GraphicsContext, amount b: CGFloat, dx: CGFloat = 0) {
        guard b > 0.01 else { return }
        for sd: CGFloat in [-1, 1] {
            let rect = CGRect(x: sd * 74 + dx - 20, y: 44 - 11, width: 40, height: 22)
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

    // MARK: - Eyes

    /// Both eyes, in Klay's frame around `center`, for the scripted figures (launch greeting,
    /// drop sequence; the engine uses drawEyes(gaze:)). `look` is the gaze offset in glyph
    /// units (x within ±14, y within ±12, y down): the eye follows it by 40 %, the pupil
    /// by 80 %. `mult` scales the eyes.
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

    /// The engine's eyes, in Klay's frame around `center`, placed by a gaze (KlayMotion.gaze):
    /// the whites shift and the eye on the side Klay turns to narrows, the pupils move further
    /// inside and never leave the white (clipped inside the rim). Port of drawKlayEyesGaze in
    /// tools/klay-preview/src/engine.ts.
    static func drawEyes(_ ctx: GraphicsContext, shape: EyeShape, mult: CGFloat,
                         center: CGPoint = .zero, gaze g: KlayGaze,
                         scale es: CGFloat = 1, open: CGFloat = 1, time: CGFloat) {
        let ew = eyeW * es * mult
        let eh = eyeH * es * mult
        let er = eyeR * es * mult
        let dx = eyeDX * mult * g.spacing
        let rimStyle = StrokeStyle(lineWidth: eyeRim * mult)
        for sd: CGFloat in [-1, 1] {
            var c = ctx
            c.translateBy(x: center.x + sd * dx + g.eye.x * mult,
                          y: center.y + eyeDY * mult + g.eye.y * mult)
            c.scaleBy(x: g.squeeze(side: sd), y: 1)
            let eye = Path(ellipseIn: CGRect(x: -er, y: -er, width: er * 2, height: er * 2))
            c.fill(eye, with: .color(body))
            c.stroke(eye, with: .color(ink), style: rimStyle)
            // The pupil stays inside the white, inside the rim.
            c.clip(to: circle(.zero, max(0, er - eyeRim * mult / 2)))
            c.translateBy(x: g.pupil.x * mult, y: g.pupil.y * mult)
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

    /// An ellipse of half axes (`rx`, `ry`) around `c`.
    static func ellipse(_ c: CGPoint, _ rx: CGFloat, _ ry: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: c.x - rx, y: c.y - ry, width: rx * 2, height: ry * 2))
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
