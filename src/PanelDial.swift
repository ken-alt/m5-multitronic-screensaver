//
//  PanelDial.swift
//  The fittings the original chronometer panel has and the later ones do not:
//  a slotted reset dial, engraving that follows a circle, and the two-headed
//  arc that shows a control turns both ways.
//
//  Everything here is lit from `CounterChrome.lightX/lightY`, like the rest of
//  the panel, and engraving goes through `CounterChrome.etchFill` so a dial
//  marking is cut to the same depth as a caption.
//

import Cocoa

// MARK: - Reset dial

extension Hardware {

    /// Cached like the screws and toggles: static hardware with far too much
    /// detail — a hundred knurls and two gradients — to redraw every frame.
    private static var dialCache: [Int: CGImage] = [:]

    /// A small slotted reset dial: a knurled chrome skirt, a domed crown, and
    /// a screwdriver slot across it. `angle` turns the slot, so a row of dials
    /// does not read as one dial stamped twice.
    static func drawDial(_ ctx: CGContext, at c: CGPoint, radius r: CGFloat,
                         angle: CGFloat = 0.5) {
        // Rendered with margin for the contact shadow, as `drawScrew` does.
        let px = max(16, Int((r * 2.6).rounded()))
        let img: CGImage
        if let cached = dialCache[px] {
            img = cached
        } else {
            guard let made = renderDial(px: px) else { return }
            dialCache[px] = made
            img = made
        }
        let side = CGFloat(px)
        ctx.saveGState()
        ctx.translateBy(x: c.x, y: c.y)
        ctx.rotate(by: angle)
        ctx.draw(img, in: CGRect(x: -side / 2, y: -side / 2, width: side, height: side))
        ctx.restoreGState()
    }

    private static func renderDial(px: Int) -> CGImage? {
        let side = CGFloat(px)
        guard let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue)
        else { return nil }

        let c = CGPoint(x: side / 2, y: side / 2)
        let r = side / 2.6                       // leaving room for the shadow
        let body = CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)
        let lx = CounterChrome.lightX, ly = CounterChrome.lightY
        let lit = CGPoint(x: c.x + lx * r, y: c.y + ly * r)
        let dark = CGPoint(x: c.x - lx * r, y: c.y - ly * r)

        // Contact shadow: the dial stands off the plate.
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: r * 0.12, height: -r * 0.20),
                      blur: r * 0.34, color: black(0.85))
        ctx.setFillColor(steel(0.20))
        ctx.fillEllipse(in: body)
        ctx.restoreGState()

        // Skirt: brighter than a screw head — this is polished, not satin.
        ctx.saveGState()
        ctx.addEllipse(in: body)
        ctx.clip()
        if let g = grad([(0.0, steel(0.86)), (0.38, steel(0.62)),
                         (0.72, steel(0.30)), (1.0, steel(0.52))]) {
            ctx.drawLinearGradient(g, start: lit, end: dark,
                                   options: [.drawsBeforeStartLocation,
                                             .drawsAfterEndLocation])
        }

        // Knurling around the skirt only. Each flute is a facet: it lights or
        // shades according to which way it faces the lamp.
        let n = 96
        let lightAngle = atan2(ly, lx)
        ctx.setLineWidth(max(0.6, r * 0.036))
        for i in 0 ..< n {
            let a = CGFloat(i) / CGFloat(n) * .pi * 2
            let facing = cos(a - lightAngle)
            let v = 0.13 * facing
            ctx.setStrokeColor(v <= 0 ? black(min(0.22, -v)) : white(v))
            ctx.move(to: CGPoint(x: c.x + cos(a) * r * 0.70, y: c.y + sin(a) * r * 0.70))
            ctx.addLine(to: CGPoint(x: c.x + cos(a) * r * 1.02, y: c.y + sin(a) * r * 1.02))
            ctx.strokePath()
        }
        ctx.restoreGState()

        // Crown, standing above the skirt: its own shadow onto the knurling is
        // what separates the two tiers.
        let cr = r * 0.68
        let crown = CGRect(x: c.x - cr, y: c.y - cr, width: cr * 2, height: cr * 2)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: r * 0.05, height: -r * 0.08),
                      blur: r * 0.12, color: black(0.8))
        ctx.setFillColor(steel(0.5))
        ctx.fillEllipse(in: crown)
        ctx.restoreGState()

        ctx.saveGState()
        ctx.addEllipse(in: crown)
        ctx.clip()
        if let g = grad([(0.0, steel(0.97)), (0.42, steel(0.70)),
                         (0.80, steel(0.32)), (1.0, steel(0.50))]) {
            ctx.drawRadialGradient(g,
                                   startCenter: CGPoint(x: c.x + lx * cr * 0.42,
                                                        y: c.y + ly * cr * 0.42),
                                   startRadius: 0, endCenter: c, endRadius: cr * 1.14,
                                   options: [])
        }
        // Tight specular where the lamp lands.
        if let g = grad([(0, white(0.85)), (1, white(0.0))]) {
            let sc = CGPoint(x: c.x + lx * cr * 0.44, y: c.y + ly * cr * 0.44)
            ctx.drawRadialGradient(g, startCenter: sc, startRadius: 0,
                                   endCenter: sc, endRadius: cr * 0.38, options: [])
        }
        ctx.restoreGState()

        // Screwdriver slot across the crown. A flat dark bar reads as paint,
        // so it is a groove: one wall lit, the floor nearly black.
        let halfW = cr * 0.085
        let slot = CGRect(x: c.x - cr * 0.78, y: c.y - halfW,
                          width: cr * 1.56, height: halfW * 2)
        ctx.saveGState()
        ctx.addEllipse(in: crown)
        ctx.clip()
        ctx.addRect(slot)
        ctx.clip()
        if let g = grad([(0.0, steel(0.30)), (0.34, black(0.92)),
                         (1.0, steel(0.20))]) {
            ctx.drawLinearGradient(g, start: CGPoint(x: slot.minX, y: slot.maxY),
                                   end: CGPoint(x: slot.minX, y: slot.minY), options: [])
        }
        ctx.restoreGState()

        return ctx.makeImage()
    }
}

// MARK: - Engraving that follows a circle

extension CounterChrome {

    /// Glyph outlines laid along a circular arc, reading left to right around
    /// the bottom of the circle with their tops toward its centre.
    ///
    /// Each glyph is set on the tangent at its own advance midpoint, so real
    /// kerning is preserved: rotating a whole rendered line would shear the
    /// letterforms instead.
    ///
    /// Returns the path and the angle it subtends, so a caller can size text
    /// to a sweep it has room for rather than guessing.
    static func arcTextPath(_ text: String, font: NSFont, kern: CGFloat,
                            centeredOn c: CGPoint, radius R: CGFloat)
        -> (path: CGPath, sweep: CGFloat) {
        let out = CGMutablePath()
        let attr = NSAttributedString(string: text, attributes: [.font: font, .kern: kern])
        let line = CTLineCreateWithAttributedString(attr)
        // Drop the trailing kern, which would otherwise push the text
        // off-centre by half a letterspace.
        let total = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil)) - kern
        guard R > 0, total > 0, let runs = CTLineGetGlyphRuns(line) as? [CTRun] else {
            return (out, 0)
        }

        for run in runs {
            let dict = CTRunGetAttributes(run)
            let key = Unmanaged.passUnretained(kCTFontAttributeName).toOpaque()
            guard let raw = CFDictionaryGetValue(dict, key) else { continue }
            let f = unsafeBitCast(raw, to: CTFont.self)
            let n = CTRunGetGlyphCount(run)
            guard n > 0 else { continue }
            var glyphs = [CGGlyph](repeating: 0, count: n)
            var pos = [CGPoint](repeating: .zero, count: n)
            CTRunGetGlyphs(run, CFRangeMake(0, n), &glyphs)
            CTRunGetPositions(run, CFRangeMake(0, n), &pos)

            for i in 0 ..< n {
                guard let g = CTFontCreatePathForGlyph(f, glyphs[i], nil) else { continue }
                // Sit each glyph on the tangent at the middle of its own cell,
                // then slide it back along that tangent to its true origin.
                let x0 = pos[i].x
                let x1 = (i + 1 < n) ? pos[i + 1].x : total
                let mid = (x0 + x1) / 2
                let phi = (mid - total / 2) / R
                let t = CGAffineTransform(translationX: c.x, y: c.y)
                    .rotated(by: phi)
                    .translatedBy(x: 0, y: -R)
                    .translatedBy(x: x0 - mid, y: 0)
                out.addPath(g, transform: t)
            }
        }
        return (out, total / R)
    }

    /// The largest size at which every one of `texts` fits inside `maxSweep`,
    /// never larger than `size`. Derived rather than tuned per label: the two
    /// dial legends are different lengths and would otherwise be set at
    /// different sizes, which reads as a mistake.
    static func arcLabelSize(fitting texts: [String], radius R: CGFloat,
                             size: CGFloat, maxSweep: CGFloat) -> CGFloat {
        var best = size
        for t in texts {
            let font = NSFont(name: "Helvetica", size: size) ?? .systemFont(ofSize: size)
            let (_, sweep) = arcTextPath(t, font: font, kern: size * arcKernFraction,
                                         centeredOn: .zero, radius: R)
            // Sweep is linear in size at fixed radius, so one measurement fits it.
            if sweep > maxSweep, sweep > 0 { best = min(best, size * maxSweep / sweep) }
        }
        return best
    }

    /// Tighter than a straight caption's: the curve already opens the text out
    /// along its outer edge.
    static let arcKernFraction: CGFloat = 0.12

    /// A caption engraved around the underside of a dial, centred on the
    /// bottom of the circle.
    static func drawArcLabel(_ ctx: CGContext, _ text: String,
                             centeredOn c: CGPoint, radius R: CGFloat, size: CGFloat) {
        let font = NSFont(name: "Helvetica", size: size) ?? .systemFont(ofSize: size)
        let (path, sweep) = arcTextPath(text, font: font, kern: size * arcKernFraction,
                                        centeredOn: c, radius: R)
        guard sweep > 0 else { return }
        etchFill(ctx, path, depth: size * 0.055)
    }

    /// The two-headed arc under a dial: the marking that says the control turns
    /// both ways. Engraved, so it belongs to the same cut as its legend.
    static func drawArcArrow(_ ctx: CGContext, centeredOn c: CGPoint, radius R: CGFloat,
                             sweep: CGFloat, thickness: CGFloat) {
        // Position angle is measured from the bottom of the circle, so the
        // shaft is symmetric about it; CoreGraphics measures from +x, hence
        // the quarter turn.
        func point(_ phi: CGFloat, _ rad: CGFloat) -> CGPoint {
            return CGPoint(x: c.x + sin(phi) * rad, y: c.y - cos(phi) * rad)
        }
        let half = sweep / 2
        let headHalfWidth = thickness * 1.45
        // Heads as long as they are wide, in arc length.
        let headSweep = min(half * 0.5, headHalfWidth * 2.1 / R)

        let arrow = CGMutablePath()

        // Shaft, stopping where the heads begin so it does not show through them.
        let shaft = CGMutablePath()
        shaft.addArc(center: c, radius: R,
                     startAngle: -half + headSweep - .pi / 2,
                     endAngle: half - headSweep - .pi / 2,
                     clockwise: false)
        arrow.addPath(shaft.copy(strokingWithWidth: thickness, lineCap: .butt,
                                 lineJoin: .round, miterLimit: 4))

        // A head at each end, on the tangent, base square across the radius.
        for sign in [CGFloat(-1), CGFloat(1)] {
            let tip = point(sign * half, R)
            let basePhi = sign * (half - headSweep)
            let base = point(basePhi, R)
            let radial = CGPoint(x: sin(basePhi), y: -cos(basePhi))
            let head = CGMutablePath()
            head.move(to: tip)
            head.addLine(to: CGPoint(x: base.x + radial.x * headHalfWidth,
                                     y: base.y + radial.y * headHalfWidth))
            head.addLine(to: CGPoint(x: base.x - radial.x * headHalfWidth,
                                     y: base.y - radial.y * headHalfWidth))
            head.closeSubpath()
            arrow.addPath(head)
        }

        etchFill(ctx, arrow, depth: thickness * 0.42)
    }
}
