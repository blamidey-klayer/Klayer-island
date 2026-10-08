import SwiftUI

// MARK: - Timing constants

private enum GT {
    static let pop0:     Double = 1.30
    static let pop1:     Double = 1.45
    static let content0: Double = 2.40
    static let tuck0:    Double = 2.45
    static let tuck1:    Double = 2.70
    static let badge:    Double = 2.72
    static let down0:    Double = 2.85
    static let down1:    Double = 3.45
    static let blink2:   Double = 3.70
    static let tint0:    Double = 3.85
    static let tint1:    Double = 4.15
    static let end:      Double = 4.60
    static let autoLeave:Double = 4.90
    static let COLLAPSE: Double = 0.34
}

// MARK: - Geometry constants (640×150 reference space)

private let GC0     = CGPoint(x: 320, y: 90)
private let GHB:    CGFloat = 58
private let GEAR_X: CGFloat = 40
private let GEAR_HB:CGFloat = 17
private let GCARD   = CGRect(x: 10, y: 36, width: 620, height: 104)
private let GCARD_R:CGFloat = 20

// MARK: - Easing

private enum GE {
    static func out(_ t: Double)    -> Double { 1 - pow(1 - t, 3) }
    static func easeIn(_ t: Double) -> Double { t * t * t }
    static func inOut(_ t: Double)  -> Double {
        t < 0.5 ? 4*t*t*t : 1 - pow(-2*t+2, 3)/2
    }
    static func back(_ t: Double)   -> Double {
        let c1=1.70158, c3=c1+1
        return 1 + c3*pow(t-1,3) + c1*pow(t-1,2)
    }
}

private func gClamp(_ v: Double, _ a: Double, _ b: Double) -> Double { max(a, min(b, v)) }
private func gLerp(_ a: Double, _ b: Double, _ t: Double)  -> Double { a + (b - a) * t }
private func gSeg(_ t: Double, _ a: Double, _ b: Double)   -> Double { gClamp((t-a)/(b-a), 0, 1) }
private func gLerpF(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat { a + (b-a)*t }

// MARK: - Pose

private enum GEyeType { case dot, happy, content }

private struct GreetPose {
    var hb, x, y, sx, sy, tilt: Double
    var eye: GEyeType; var open, eyeRoll: Double
    var lookX, lookY: Double
    var handL, handR, wave: Double
    var badge, tint, halo, haloBlue, fx: Double
    var header, card: Double
    var iw, ih: Double
}

// MARK: - Particle data (seeded LCG, seed=7)

private struct GWarpStreak { let xNorm, speed, len, thick, alpha, t0: Double }
private struct GRingDot    { let a, j, s, al: Double }

private let greetParticles: (warps: [GWarpStreak], ring: [GRingDot]) = {
    var seed: UInt32 = 7
    func rnd() -> Double {
        seed = (seed &* 1103515245 &+ 12345) & 0x7fffffff
        return Double(seed) / Double(0x7fff_ffff)
    }
    // ~70 white warp streaks for the fall-in (0 → 0.55 s)
    let warps = (0..<70).map { _ in
        GWarpStreak(xNorm: rnd(),
                    speed: 400 + rnd() * 300,
                    len:   6   + rnd() * 16,
                    thick: 1   + rnd() * 0.5,
                    alpha: 0.25 + rnd() * 0.55,
                    t0:   rnd() * 0.35)
    }
    // Single burst ring at 0.45 s, ~90 dots, white
    let ring = (0..<90).map { _ in
        GRingDot(a: rnd() * .pi * 2, j: (rnd()-0.5)*0.22,
                 s: 0.7+rnd()*0.9,   al: 0.45+rnd()*0.55)
    }
    return (warps, ring)
}()

// MARK: - Pose computation

private func greetPose(_ t: Double, compact: IslandRestingLayout) -> GreetPose {
    // Island size (reference for clip / warp spread)
    let gx = gSeg(t, 0, 0.5)
    let g  = sin(.pi*gx/2) + 0.04*sin(.pi*gx)*gx
    let iw = gLerp(Double(compact.width - 160), 640, g)
    let ih = gLerp(Double(compact.height), 150, g)

    let GH = Double(GHB)   // 58
    let cx = Double(GC0.x) // 320
    let cy = Double(GC0.y) // 90

    // Body height: invisible before 0.20, grows 0.15→1.0 with back ease
    let hb: Double = t < 0.20 ? 0 : gLerp(GH * 0.15, GH, GE.back(gSeg(t, 0.20, 0.60)))

    // Landmark y positions (absolute, GC0-relative in multiples of GH)
    let restY   = cy
    let landY   = cy + 0.12 * GH   // landing: y=+0.12
    let peakY   = cy - 0.15 * GH   // bounce peak: y=−0.15
    let dipY    = cy + 0.36 * GH   // plunge low: y=+0.36
    let springY = cy - 0.10 * GH   // spring high: y=−0.10
    let sinkY   = cy + 0.30 * GH   // sink for tuck: y=+0.30

    // Landmark x positions
    let restX   = cx
    let drift1  = cx - 0.16 * GH
    let drift2  = cx - 0.45 * GH
    let drift3  = cx - 0.57 * GH
    let drift4  = cx - 0.85 * GH

    // --- X (lateral travel) ---
    var x: Double
    if t < 0.85 {
        x = restX
    } else if t < 1.20 {
        x = gLerp(restX,  drift1, GE.inOut(gSeg(t, 0.85, 1.20)))
    } else if t < 1.30 {
        x = gLerp(drift1, drift2, GE.easeIn(gSeg(t, 1.20, 1.30)))
    } else if t < 1.45 {
        x = gLerp(drift2, drift3, GE.inOut(gSeg(t, 1.30, 1.45)))
    } else if t < 2.40 {
        x = gLerp(drift3, drift4, GE.inOut(gSeg(t, 1.45, 2.40)))
    } else if t < 2.85 {
        x = drift4
    } else {
        x = gLerp(drift4, restX,  GE.inOut(gSeg(t, 2.85, 3.45)))
    }

    // --- Y (vertical travel, base without bob) ---
    var y: Double
    if t < 0.20 {
        y = Double(compact.botCenterY)
    } else if t < 0.60 {
        y = gLerp(Double(compact.botCenterY), landY, GE.easeIn(gSeg(t, 0.20, 0.60)))
    } else if t < 0.73 {
        y = gLerp(landY,   peakY,   GE.out(gSeg(t, 0.60, 0.73)))
    } else if t < 0.90 {
        y = gLerp(peakY,   restY,   GE.inOut(gSeg(t, 0.73, 0.90)))
    } else if t < 1.20 {
        y = restY
    } else if t < 1.30 {
        y = gLerp(restY,   dipY,    GE.easeIn(gSeg(t, 1.20, 1.30)))
    } else if t < 1.45 {
        y = gLerp(dipY,    springY, GE.out(gSeg(t, 1.30, 1.45)))
    } else if t < 1.60 {
        y = gLerp(springY, restY,   GE.inOut(gSeg(t, 1.45, 1.60)))
    } else if t < 2.40 {
        y = restY
    } else if t < 2.70 {
        y = gLerp(restY,   sinkY,   GE.inOut(gSeg(t, 2.40, 2.70)))
    } else if t < 2.85 {
        y = sinkY
    } else {
        y = gLerp(sinkY,   restY,   GE.inOut(gSeg(t, 2.85, 3.45)))
    }

    // Body bob: in phase with hand wave, active pop1 → tuck0, ramp-in 0.08 s
    if t >= GT.pop1 && t < GT.tuck0 {
        let w = t - GT.pop1
        let rampIn = gClamp(w / 0.08, 0, 1)
        y += sin(w * 2 * .pi * 5.0) * 0.02 * GH * rampIn
    }

    // --- Scale ---
    var sx = 1.0, sy = 1.0

    // Landing squash (peak at 0.60, pulse 0.52→0.68)
    let landSqK = (t >= 0.52 && t < 0.68) ? sin(.pi * gSeg(t, 0.52, 0.68)) : 0
    // Bounce stretch (peak at 0.73, resolves 0.62→0.84)
    let bounceK  = (t >= 0.62 && t < 0.84) ? sin(.pi * gSeg(t, 0.62, 0.84)) : 0
    sx = 1.0 + 0.14 * landSqK - 0.10 * bounceK
    sy = 1.0 - 0.14 * landSqK + 0.18 * bounceK

    // Plunge squash (peaks at 1.30, pulse 1.18→1.42)
    let plungeK = (t >= 1.18 && t < 1.42) ? sin(.pi * gSeg(t, 1.18, 1.42)) : 0
    // Spring stretch (peak at 1.38, resolves 1.30→1.46)
    let springK = (t >= 1.30 && t < 1.46) ? sin(.pi * gSeg(t, 1.30, 1.46)) : 0
    sx += 0.12 * plungeK - 0.18 * springK
    sy -= 0.12 * plungeK - 0.25 * springK

    // Sink squash (peak at 2.70)
    let sinkK: Double
    if t >= 2.38 && t < 2.70 {
        sinkK = GE.inOut(gSeg(t, 2.38, 2.70))
    } else if t >= 2.70 && t < 2.85 {
        sinkK = 1 - GE.inOut(gSeg(t, 2.70, 2.85))
    } else {
        sinkK = 0
    }
    sx += 0.18 * sinkK
    sy -= 0.14 * sinkK

    // Micro squash at 3.70 (with blink)
    let microK = (t >= 3.70 && t < 3.82) ? sin(.pi * gSeg(t, 3.70, 3.82)) : 0
    sx += 0.08 * microK
    sy -= 0.07 * microK

    // --- Eyes ---
    var eye: GEyeType = .dot
    if t >= 0.55  && t < 0.80      { eye = .happy   }
    if t >= GT.content0 && t < GT.tuck1 { eye = .content }

    let blink: (Double) -> Double = { tb in
        let k = gSeg(t, tb, tb + 0.12)
        return (k > 0 && k < 1) ? 1 - sin(.pi * k) * 0.94 : 1
    }
    let openVal = min(blink(1.95), min(blink(3.05), blink(GT.blink2)))

    // --- Look ---
    var lookX = 0.0, lookY = 0.0
    if t >= GT.pop1 && t < GT.content0 {         // wave: up-right
        lookX = 0.55; lookY = -0.45
    } else if t >= GT.content0 && t < GT.down0 { // tuck: down-left
        lookX = -0.3; lookY = 0.6
    } else if t >= GT.down0 && t < GT.down1 {    // slide: down-right (returning)
        lookX = 0.3;  lookY = 0.6
    } else if t >= GT.down1 {
        let k = GE.inOut(gSeg(t, GT.down1, GT.down1 + 0.35))
        lookX = gLerp(0.3, 0, k); lookY = gLerp(0.6, 0, k)
    }

    // --- Hands ---
    let handL = t < GT.tuck0
        ? GE.back(gSeg(t, GT.pop0, GT.pop0 + 0.14))
        : 1 - GE.easeIn(gSeg(t, GT.tuck0, GT.tuck1 - 0.03))
    let handR = t < GT.tuck0
        ? GE.back(gSeg(t, GT.pop0 + 0.04, GT.pop0 + 0.18))
        : 1 - GE.easeIn(gSeg(t, GT.tuck0 + 0.03, GT.tuck1))
    let wave = (t >= GT.pop1 && t < GT.tuck0) ? t - GT.pop1 : -1.0

    return GreetPose(
        hb: hb, x: x, y: y, sx: sx, sy: sy, tilt: 0,
        eye: eye, open: openVal, eyeRoll: 0,
        lookX: lookX, lookY: lookY,
        handL: handL, handR: handR, wave: wave,
        badge:    GE.back(gSeg(t, GT.badge, GT.badge + 0.28)),
        tint:     0.6 * GE.inOut(gSeg(t, GT.tint0, GT.tint1)),
        halo:     GE.out(gSeg(t, 0.3, 0.7)),
        haloBlue: gSeg(t, GT.tint0, GT.tint1),
        fx: 1,
        header: gSeg(t, 0.35, 0.6), card: gSeg(t, 0.18, 0.45),
        iw: iw, ih: ih
    )
}

private func smallPose(_ compact: IslandRestingLayout) -> GreetPose {
    let sw = Double(compact.width)
    return GreetPose(
        hb: Double(GEAR_HB * compact.botDiameter / 20),
        x: 320 - sw/2 + Double(GEAR_X),
        y: Double(compact.botCenterY),
        sx: 1, sy: 1, tilt: 0,
        eye: .dot, open: 1, eyeRoll: 0,
        lookX: 0, lookY: 0,
        handL: 0, handR: 0, wave: -1,
        badge: 1, tint: 0.6, halo: 0.6, haloBlue: 1,
        fx: 1,
        header: 0, card: 0,
        iw: sw, ih: Double(compact.height)
    )
}

private func pose(_ t: Double, tc: Double, compact: IslandRestingLayout) -> GreetPose {
    if t < tc { return greetPose(min(t, GT.end + 10), compact: compact) }
    let a = greetPose(tc, compact: compact)
    let b = smallPose(compact)
    let e = GE.inOut(gSeg(t, tc, tc + GT.COLLAPSE))
    var p = a
    p.iw = gLerp(a.iw, b.iw, e); p.ih = gLerp(a.ih, b.ih, e)
    p.x  = gLerp(a.x, b.x, e);   p.y  = gLerp(a.y, b.y, e)
    p.hb = gLerp(a.hb, b.hb, e)
    p.badge    = gLerp(a.badge, b.badge, e)
    p.tint     = gLerp(a.tint,  b.tint,  e)
    p.halo     = gLerp(a.halo,  b.halo,  e)
    p.haloBlue = gLerp(a.haloBlue, b.haloBlue, e)
    p.header   = a.header * (1 - gSeg(t, tc, tc+0.1))
    p.card     = a.card   * (1 - gSeg(t, tc, tc+0.18))
    p.handL    = a.handL  * (1 - gSeg(t, tc, tc+0.15))
    p.handR    = a.handR  * (1 - gSeg(t, tc, tc+0.15))
    p.wave     = a.wave >= 0 ? a.wave : -1
    p.tilt     = a.tilt * (1 - e)
    p.sx       = gLerp(a.sx, 1, e); p.sy = gLerp(a.sy, 1, e)
    p.eyeRoll  = a.eyeRoll * (1 - e)
    let bk = gSeg(t, tc+0.14, tc+0.26)
    p.eye = .dot; p.open = (bk > 0 && bk < 1) ? 1 - sin(.pi*bk)*0.94 : 1
    p.lookX = a.lookX*(1-e); p.lookY = a.lookY*(1-e)
    p.fx    = 1 - gSeg(t, tc, tc+0.2)
    return p
}

// MARK: - Drawing helpers

private func gHex(_ hex: String, alpha: CGFloat = 1) -> CGColor {
    let h = hex.trimmingCharacters(in: CharacterSet(charactersIn:"#"))
    let v = UInt64(h, radix: 16) ?? 0
    return CGColor(red: CGFloat((v>>16)&0xFF)/255,
                   green: CGFloat((v>>8)&0xFF)/255,
                   blue: CGFloat(v&0xFF)/255, alpha: alpha)
}

private func gRR(_ ctx: CGContext, _ x: CGFloat, _ y: CGFloat,
                 _ w: CGFloat, _ h: CGFloat, _ r: CGFloat) {
    let r = max(0, min(r, w/2, h/2))
    ctx.beginPath()
    ctx.move(to: CGPoint(x: x+r, y: y))
    ctx.addArc(tangent1End: CGPoint(x: x+w, y: y),   tangent2End: CGPoint(x: x+w, y: y+h), radius: r)
    ctx.addArc(tangent1End: CGPoint(x: x+w, y: y+h), tangent2End: CGPoint(x: x,   y: y+h), radius: r)
    ctx.addArc(tangent1End: CGPoint(x: x,   y: y+h), tangent2End: CGPoint(x: x,   y: y),   radius: r)
    ctx.addArc(tangent1End: CGPoint(x: x,   y: y),   tangent2End: CGPoint(x: x+r, y: y),   radius: r)
    ctx.closePath()
}

// MARK: - Klay (GraphicsContext, drawn over the CG layer)

/// Glyph width as a multiple of the pose's body height `hb`: Klay keeps the old
/// character's footprint in the greeting card (78 pt wide at rest).
private let GGLYPH_PER_HB: CGFloat = 1.34

/// Klay in the greeting: the white glyph with its glow, limbs and eyes. (p.x, p.y) is
/// the middle of Klay's full height; the right hand waves, the left one swings out.
private func drawKlay(_ context: GraphicsContext, p: GreetPose) {
    let hb = CGFloat(p.hb)
    guard hb > 0.8 else { return }
    let s = hb * GGLYPH_PER_HB / KlayGlyph.width   // points per glyph unit
    let px = CGFloat(p.x), py = CGFloat(p.y)

    // Glow behind the rays: golden on arrival, then the working state's teal
    // (StateColor.working, #4FA3B5) as the island wakes up.
    let glow = CGFloat(0.45 * p.halo + 0.4 * p.tint)
    if glow > 0.01 {
        let bl = CGFloat(p.haloBlue)
        let color = Color(red: Double(gLerpF(232/255, 79/255, bl)),
                          green: Double(gLerpF(195/255, 163/255, bl)),
                          blue: Double(gLerpF(154/255, 181/255, bl)))
        let hubY = py - KlayPaint.centerY * s
        KlayPaint.drawGlow(context, center: CGPoint(x: px, y: hubY - 70 * s),
                           radius: 380 * s, color: color, amount: glow)
    }

    // Pose frame: centred on the middle of Klay's height, tilted and squashed there.
    var frame = context
    frame.translateBy(x: px, y: py)
    frame.rotate(by: .radians(p.tilt))
    frame.scaleBy(x: CGFloat(p.sx), y: CGFloat(p.sy))

    // Klay's frame: origin on the hub, glyph units.
    var c = frame
    c.translateBy(x: 0, y: -KlayPaint.centerY * s)
    c.scaleBy(x: s, y: s)

    KlayPaint.drawFigure(c, limbs: KlayGlyph.width * s >= KlayPaint.limbsMinPx ? greetLimbs(p) : nil)

    let shape: EyeShape
    switch p.eye {
    case .dot:     shape = .pill
    case .happy:   shape = .happy
    case .content: shape = .closed
    }
    KlayPaint.drawEyes(c, shape: shape, mult: 1,
                       look: CGPoint(x: CGFloat(p.lookX) * 14, y: CGFloat(p.lookY) * 12),
                       open: CGFloat(p.open), time: 0)

    // Activity badge, top left of the rays
    if p.badge > 0.01 {
        let bs = CGFloat(p.badge)
        let br = hb * 0.15
        var b = frame
        b.translateBy(x: -hb * 0.62, y: -hb * 0.40)
        b.scaleBy(x: bs, y: bs)
        let ring = br + hb * 0.035
        b.fill(Path(ellipseIn: CGRect(x: -ring, y: -ring, width: ring * 2, height: ring * 2)),
               with: .color(.black))
        b.fill(Path(ellipseIn: CGRect(x: -br, y: -br, width: br * 2, height: br * 2)),
               with: .color(Color(cgColor: StateColor.working)))
        for i: CGFloat in [-1, 0, 1] {
            b.fill(Path(ellipseIn: CGRect(x: i * br * 0.5 - br * 0.17, y: -br * 0.17,
                                          width: br * 0.34, height: br * 0.34)),
                   with: .color(Color(cgColor: gHex("#0B1B3A"))))
        }
    }
}

/// Hands and feet for a greeting pose. handR raises the right hand into the wave,
/// handL swings the left one out; both follow the wave's 0.08 s ramp-in.
private func greetLimbs(_ p: GreetPose) -> KlayPaint.Limbs {
    var l = KlayPaint.Limbs.rest
    var ramp: CGFloat = 0
    var wt: CGFloat = 0
    if p.wave >= 0 {
        let w = p.wave
        let waveEnd = GT.tuck0 - GT.pop1
        let rampIn = gClamp(w / 0.08, 0, 1)
        let rampOut = 1 - gClamp((w - waveEnd) / (GT.tuck1 - GT.tuck0), 0, 1)
        ramp = CGFloat(rampIn * rampOut)
        wt = CGFloat(w)
    }
    let raised = CGPoint(x: 206, y: -40)
    let waving = KlayPaint.blend(raised, KlayPaint.waveHand(t: wt), ramp)
    l.rh = KlayPaint.blend(l.rh, waving, CGFloat(p.handR))
    let out = CGPoint(x: -190, y: 70 + sin(wt * 2 * .pi * 2.5) * 12 * ramp)
    l.lh = KlayPaint.blend(l.lh, out, CGFloat(p.handL))
    return l
}

private func drawParticles(_ ctx: CGContext, t: Double, tc: Double, p: GreetPose) {
    guard p.card > 0 || p.fx < 1 else { return }
    let fx = p.fx

    // WARP STREAKS: white vertical lines, fall-in 0 → 0.55 s
    if t < 0.55 {
        for s in greetParticles.warps {
            guard t >= s.t0 else { continue }
            let elapsed = t - s.t0
            let yBot = CGFloat(elapsed * s.speed)
            let yTop = yBot - CGFloat(s.len)
            guard yBot > 0 else { continue }
            let streakX  = CGFloat(320 - p.iw/2 + s.xNorm * p.iw)
            let fadeOut  = 1 - gSeg(t, 0.40, 0.55)
            let alpha    = CGFloat(s.alpha * fx * fadeOut)
            ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: alpha))
            ctx.setLineWidth(CGFloat(s.thick)); ctx.setLineCap(.butt)
            ctx.beginPath()
            ctx.move(to:    CGPoint(x: streakX, y: max(0, yTop)))
            ctx.addLine(to: CGPoint(x: streakX, y: min(150, yBot)))
            ctx.strokePath()
        }
    }

    // RING: single white burst at 0.45 s, ~90 dots
    let ringT0 = 0.45
    let k = gSeg(t, ringT0, ringT0 + 1.35)
    if k > 0 && k < 1 {
        let rx   = gLerpF(14, 380, CGFloat(GE.out(k)))
        let ry   = rx * 0.34
        let fade = CGFloat((1-k) * (k < 0.08 ? k/0.08 : 1) * fx * p.card)
        for dot in greetParticles.ring {
            let r: CGFloat = 1 + CGFloat(dot.j)
            ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1,
                                     alpha: CGFloat(dot.al) * fade))
            let dx = CGFloat(GC0.x) + cos(CGFloat(dot.a)) * rx * r
            let dy = CGFloat(GC0.y) + sin(CGFloat(dot.a)) * ry * r
            ctx.fill(CGRect(x: dx, y: dy, width: CGFloat(dot.s), height: CGFloat(dot.s)))
        }
    }
}

private func drawHeader(_ ctx: CGContext, alpha: Double) {
    guard alpha > 0 else { return }
    ctx.saveGState()
    ctx.setAlpha(CGFloat(alpha))
    gRR(ctx, 18, 4, 44, 26, 13)
    ctx.setFillColor(gHex("#1D1F23")); ctx.fillPath()
    ctx.setFillColor(gHex("#F5F6F8"))
    ctx.beginPath()
    ctx.move(to: CGPoint(x: 33, y: 20)); ctx.addLine(to: CGPoint(x: 40, y: 13))
    ctx.addLine(to: CGPoint(x: 47, y: 20)); ctx.addLine(to: CGPoint(x: 47, y: 25))
    ctx.addLine(to: CGPoint(x: 33, y: 25)); ctx.closePath(); ctx.fillPath()
    ctx.setFillColor(gHex("#8E939C"))
    ctx.addEllipse(in: CGRect(x: 75.5, y: 10.5, width: 13, height: 13)); ctx.fillPath()
    ctx.addEllipse(in: CGRect(x: 572, y: 11, width: 12, height: 12)); ctx.fillPath()
    ctx.setFillColor(gHex("#000000"))
    ctx.addEllipse(in: CGRect(x: 575.6, y: 14.6, width: 4.8, height: 4.8)); ctx.fillPath()
    ctx.restoreGState()
}

// MARK: - Full draw

/// The card and its particles (CoreGraphics). Klay is drawn over it by `drawKlay`.
private func drawGreeting(_ ctx: CGContext, p: GreetPose, t: Double, tc: Double) {
    if p.card > 0 {
        ctx.saveGState()
        ctx.setAlpha(CGFloat(p.card))
        gRR(ctx, GCARD.minX, GCARD.minY, GCARD.width, GCARD.height, GCARD_R)
        ctx.setFillColor(gHex("#141518")); ctx.fillPath()
        ctx.restoreGState()

        ctx.saveGState()
        gRR(ctx, GCARD.minX, GCARD.minY, GCARD.width, GCARD.height, GCARD_R)
        ctx.clip()
        drawParticles(ctx, t: t, tc: tc, p: p)
        ctx.restoreGState()
    } else if tc.isFinite && t >= tc {
        ctx.saveGState()
        drawParticles(ctx, t: t, tc: tc, p: p)
        ctx.restoreGState()
    }
}

// MARK: - SwiftUI View

struct GreetingCanvasView: View {
    @ObservedObject var state: AppState

    @State private var startDate = Date()
    @State private var tc: Double = .infinity
    @State private var greetFired = false
    @State private var doneWork: DispatchWorkItem? = nil

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSince(startDate)
            Canvas { context, _ in
                let compact = IslandRestingLayout(width: state.notchWidth + 160,
                                                  height: state.notchHeight)
                let p = pose(t, tc: tc, compact: compact)
                context.withCGContext { cgCtx in
                    drawGreeting(cgCtx, p: p, t: t, tc: tc)
                }
                drawKlay(context, p: p)
            }
            .onChange(of: !greetFired && t >= GT.end && tc >= GT.autoLeave) { _, trigger in
                if trigger { fireGreetComplete() }
            }
        }
        .onAppear {
            startDate = Date()
            tc = .infinity
            greetFired = false
            // Original score plays from the start; greet.wav and blip.wav kept for other uses
            SoundEngine.shared.play("greeting")
            // Safety fallback: fire done if timeline onChange misses it
            let item = DispatchWorkItem { fireGreetComplete() }
            doneWork = item
            DispatchQueue.main.asyncAfter(deadline: .now() + GT.end + 0.05, execute: item)
        }
        .onDisappear {
            doneWork?.cancel(); doneWork = nil
            SoundEngine.shared.fadeOut("greeting", duration: 0.2)
            // Left before its end (an alert took its place, or it was interrupted): its end is still
            // posted, so the desktop Klay's launch flight happens and nothing waits for it.
            if !greetFired { fireGreetComplete() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .greetingHover)) { _ in
            if tc >= GT.autoLeave { tc = .infinity }
        }
        .onReceive(NotificationCenter.default.publisher(for: .greetingInterrupt)) { _ in
            let t = Date().timeIntervalSince(startDate)
            if tc.isInfinite || tc > t { tc = t }
            doneWork?.cancel(); doneWork = nil
            SoundEngine.shared.fadeOut("greeting", duration: 0.25)
        }
    }

    private func fireGreetComplete() {
        guard !greetFired else { return }
        greetFired = true
        doneWork?.cancel(); doneWork = nil
        // Note: greeting music continues for ~0.3 s after greetComplete — intentional queue overlap
        NotificationCenter.default.post(name: .greetComplete, object: nil)
    }
}
