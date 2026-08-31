//
//  Hardware.swift
//  Photoreal panel fittings: screws, toggle switches, and the cover glass.
//
//  Everything here is lit from above-left and casts down-right, so the whole
//  panel agrees on one light direction. That consistency is most of what makes
//  drawn hardware read as real.
//

import Cocoa

enum Hardware {

    // MARK: Helpers

    static func grad(_ stops: [(CGFloat, CGColor)]) -> CGGradient? {
        return CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                          colors: stops.map { $0.1 } as CFArray,
                          locations: stops.map { $0.0 })
    }
    static func steel(_ v: CGFloat, _ a: CGFloat = 1) -> CGColor {
        return CGColor(red: v, green: v * 0.995, blue: v * 0.985, alpha: a)
    }
    static func black(_ a: CGFloat) -> CGColor { CGColor(red: 0, green: 0, blue: 0, alpha: a) }
    static func white(_ a: CGFloat) -> CGColor { CGColor(red: 1, green: 1, blue: 1, alpha: a) }

    // MARK: Screw

    /// Rendered screws are cached by pixel size and blitted. A convincing head
    /// needs ~100 radial machining strokes, which is far too much to redraw
    /// every frame for every screw — but it never changes, so it is drawn once.
    private static var screwCache: [Int: CGImage] = [:]

    /// A socket head cap screw, lit from upper-left: a domed head with radial
    /// machining marks, a chamfered rim that is bright on the light side and
    /// dark on the far side, and a hex recess with one lit wall and one in
    /// shadow. The recess is what sells the depth — a flat dark hexagon reads
    /// as a sticker.
    static func drawScrew(_ ctx: CGContext, at c: CGPoint, radius r: CGFloat, angle: CGFloat = 0.4) {
        let px = max(8, Int((r * 2.6).rounded()))
        let img: CGImage
        if let cached = screwCache[px] {
            img = cached
        } else {
            guard let made = renderScrew(px: px) else { return }
            screwCache[px] = made
            img = made
        }
        let side = CGFloat(px)
        ctx.saveGState()
        ctx.translateBy(x: c.x, y: c.y)
        ctx.rotate(by: angle)          // vary the driver angle per screw
        ctx.draw(img, in: CGRect(x: -side / 2, y: -side / 2, width: side, height: side))
        ctx.restoreGState()
    }

    private static func renderScrew(px: Int) -> CGImage? {
        let side = CGFloat(px)
        guard let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue)
        else { return nil }
        let c = CGPoint(x: side / 2, y: side / 2)
        let r = side / 2.6                       // head radius, leaving room for the shadow
        let head = CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)
        // Light from upper-left, matching every other fitting on the panel.
        let lx: CGFloat = -0.66, ly: CGFloat = 0.66
        let lit = CGPoint(x: c.x + lx * r, y: c.y + ly * r)
        let dark = CGPoint(x: c.x - lx * r, y: c.y - ly * r)

        // Contact shadow.
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: r * 0.10, height: -r * 0.18),
                      blur: r * 0.36, color: black(0.85))
        ctx.setFillColor(steel(0.18))
        ctx.fillEllipse(in: head)
        ctx.restoreGState()

        ctx.saveGState()
        ctx.addEllipse(in: head)
        ctx.clip()

        // Satin face. Mid-toned: a near-white head reads as plastic.
        if let g = grad([(0.0, steel(0.60)), (0.50, steel(0.42)),
                         (0.85, steel(0.26)), (1.0, steel(0.19))]) {
            ctx.drawRadialGradient(g,
                                   startCenter: CGPoint(x: c.x + lx * r * 0.45, y: c.y + ly * r * 0.45),
                                   startRadius: 0, endCenter: c, endRadius: r * 1.18, options: [])
        }

        // Radial machining marks, only really visible on a large head.
        let n = 132
        ctx.setLineWidth(max(0.6, r * 0.028))
        let lightAngle = atan2(ly, lx)
        for i in 0 ..< n {
            let a = CGFloat(i) / CGFloat(n) * .pi * 2
            let facing = cos(a - lightAngle)
            let jitter = sin(CGFloat(i) * 12.9898) * 0.5 + 0.5
            let v = 0.040 * facing + 0.032 * jitter - 0.010
            ctx.setStrokeColor(v <= 0 ? black(min(0.09, -v * 1.6)) : white(v))
            ctx.move(to: CGPoint(x: c.x + cos(a) * r * 0.20, y: c.y + sin(a) * r * 0.20))
            ctx.addLine(to: CGPoint(x: c.x + cos(a) * r, y: c.y + sin(a) * r))
            ctx.strokePath()
        }
        ctx.restoreGState()

        // Chamfered rim as an annulus filled along the light direction. Two
        // stroked arcs leave gaps and read as separate lumps.
        ctx.saveGState()
        let rim = CGMutablePath()
        rim.addEllipse(in: head)
        rim.addEllipse(in: head.insetBy(dx: r * 0.15, dy: r * 0.15))
        ctx.addPath(rim)
        ctx.clip(using: .evenOdd)
        if let g = grad([(0.0, white(0.50)), (0.42, white(0.06)),
                         (0.58, black(0.10)), (1.0, black(0.62))]) {
            ctx.drawLinearGradient(g, start: lit, end: dark, options: [])
        }
        ctx.restoreGState()

        // Broad soft specular on the crown.
        ctx.saveGState()
        ctx.addEllipse(in: head.insetBy(dx: r * 0.12, dy: r * 0.12))
        ctx.clip()
        if let g = grad([(0.0, white(0.26)), (0.6, white(0.06)), (1.0, white(0.0))]) {
            let sc = CGPoint(x: c.x + lx * r * 0.40, y: c.y + ly * r * 0.40)
            ctx.drawRadialGradient(g, startCenter: sc, startRadius: 0,
                                   endCenter: sc, endRadius: r * 0.66, options: [])
        }
        ctx.restoreGState()

        // Hex socket.
        let hr = r * 0.44
        func hexPath(_ rad: CGFloat) -> CGPath {
            let p = CGMutablePath()
            for k in 0 ..< 6 {
                let a = CGFloat(k) / 6 * .pi * 2 + .pi / 6
                let pt = CGPoint(x: c.x + cos(a) * rad, y: c.y + sin(a) * rad)
                if k == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
            }
            p.closeSubpath()
            return p
        }
        // The chamfer around the hole: bright where the light falls in.
        ctx.saveGState()
        let hexRim = CGMutablePath()
        hexRim.addPath(hexPath(hr * 1.19))
        hexRim.addPath(hexPath(hr))
        ctx.addPath(hexRim)
        ctx.clip(using: .evenOdd)
        if let g = grad([(0.0, white(0.42)), (0.5, black(0.10)), (1.0, black(0.55))]) {
            ctx.drawLinearGradient(g, start: lit, end: dark, options: [])
        }
        ctx.restoreGState()

        // The hole. Not flat black — the far wall catches a little bounce.
        ctx.saveGState()
        ctx.addPath(hexPath(hr))
        ctx.clip()
        if let g = grad([(0.0, black(1.0)), (0.72, steel(0.055)), (1.0, steel(0.13))]) {
            ctx.drawLinearGradient(g, start: lit, end: dark, options: [])
        }
        ctx.restoreGState()

        return ctx.makeImage()
    }

    // MARK: Toggle switch

    /// Cached like the screws: static hardware, too much detail to redraw each
    /// frame.
    private static var toggleCache: [Int: CGImage] = [:]

    /// Image proportions: a little taller than wide, the nut low and the lever
    /// rising out of it.
    static let toggleAspect: CGFloat = 1.18

    /// A bat-handle toggle as it appears on the prop: a chrome hex nut set into
    /// the panel with a ball-tipped lever thrown up out of it. No ON/OFF
    /// escutcheon — on the show the caption is printed on the panel alongside,
    /// and the stamped plate is what forced the fitting to be large.
    static func drawToggle(_ ctx: CGContext, at c: CGPoint, scale s: CGFloat,
                           thrownUp: Bool = true) {
        let px = max(20, Int((s * 3.0).rounded()))
        let img: CGImage
        if let cached = toggleCache[px] {
            img = cached
        } else {
            guard let made = renderToggle(px: px) else { return }
            toggleCache[px] = made
            img = made
        }
        let w = s
        let h = s * toggleAspect
        ctx.draw(img, in: CGRect(x: c.x - w / 2, y: c.y - h / 2, width: w, height: h))
    }

    private static func renderToggle(px: Int) -> CGImage? {
        let W = CGFloat(px)
        let H = (W * toggleAspect).rounded()
        guard let ctx = CGContext(data: nil, width: px, height: Int(H),
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue)
        else { return nil }

        let nutC = CGPoint(x: W / 2, y: H * 0.36)
        let nutR = W * 0.46

        // The panel opening the bushing passes through.
        ctx.saveGState()
        if let g = grad([(0.0, black(0.55)), (1.0, black(0.0))]) {
            ctx.drawRadialGradient(g, startCenter: nutC, startRadius: nutR * 0.9,
                                   endCenter: nutC, endRadius: nutR * 1.45, options: [])
        }
        ctx.restoreGState()

        // Hex nut, flats catching the light differently around the turn.
        let hex = CGMutablePath()
        for k in 0 ..< 6 {
            let a = CGFloat(k) / 6 * .pi * 2 + .pi / 6
            let p = CGPoint(x: nutC.x + cos(a) * nutR, y: nutC.y + sin(a) * nutR * 0.94)
            if k == 0 { hex.move(to: p) } else { hex.addLine(to: p) }
        }
        hex.closeSubpath()

        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: W * 0.03, height: -W * 0.05),
                      blur: W * 0.09, color: black(0.8))
        ctx.addPath(hex)
        ctx.setFillColor(steel(0.5))
        ctx.fillPath()
        ctx.restoreGState()

        ctx.saveGState()
        ctx.addPath(hex)
        ctx.clip()
        if let g = grad([(0.00, steel(0.88)), (0.24, steel(0.62)), (0.46, steel(0.78)),
                         (0.66, steel(0.44)), (0.86, steel(0.58)), (1.00, steel(0.28))]) {
            ctx.drawLinearGradient(g, start: CGPoint(x: nutC.x - nutR, y: nutC.y + nutR),
                                   end: CGPoint(x: nutC.x + nutR, y: nutC.y - nutR), options: [])
        }
        ctx.restoreGState()

        // Bushing collar inside the nut.
        ctx.saveGState()
        let br = W * 0.29
        ctx.addEllipse(in: CGRect(x: nutC.x - br, y: nutC.y - br * 0.94,
                                  width: br * 2, height: br * 1.88))
        ctx.clip()
        if let g = grad([(0.0, steel(0.74)), (0.5, steel(0.40)), (1.0, steel(0.16))]) {
            ctx.drawRadialGradient(g, startCenter: CGPoint(x: nutC.x - br * 0.4, y: nutC.y + br * 0.4),
                                   startRadius: 0, endCenter: nutC, endRadius: br, options: [])
        }
        ctx.restoreGState()

        // The dark recess the lever emerges from.
        ctx.saveGState()
        let rr = W * 0.185
        ctx.addEllipse(in: CGRect(x: nutC.x - rr, y: nutC.y - rr * 0.9,
                                  width: rr * 2, height: rr * 1.8))
        ctx.clip()
        if let g = grad([(0.0, black(0.95)), (1.0, steel(0.22))]) {
            ctx.drawLinearGradient(g, start: CGPoint(x: nutC.x, y: nutC.y + rr),
                                   end: CGPoint(x: nutC.x, y: nutC.y - rr), options: [])
        }
        ctx.restoreGState()

        // Lever thrown up, foreshortened, with a ball tip.
        let ballC = CGPoint(x: nutC.x + W * 0.02, y: nutC.y + W * 0.40)
        ctx.saveGState()
        ctx.setLineCap(.round)
        ctx.setStrokeColor(steel(0.44))
        ctx.setLineWidth(W * 0.215)
        ctx.move(to: nutC)
        ctx.addLine(to: ballC)
        ctx.strokePath()
        ctx.setStrokeColor(white(0.34))
        ctx.setLineWidth(W * 0.055)
        ctx.move(to: CGPoint(x: nutC.x - W * 0.045, y: nutC.y))
        ctx.addLine(to: CGPoint(x: ballC.x - W * 0.045, y: ballC.y - W * 0.04))
        ctx.strokePath()
        ctx.restoreGState()

        let ballR = W * 0.235
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: W * 0.035, height: -W * 0.05),
                      blur: W * 0.08, color: black(0.75))
        ctx.setFillColor(steel(0.5))
        ctx.fillEllipse(in: CGRect(x: ballC.x - ballR, y: ballC.y - ballR,
                                   width: ballR * 2, height: ballR * 2))
        ctx.restoreGState()
        ctx.saveGState()
        ctx.addEllipse(in: CGRect(x: ballC.x - ballR, y: ballC.y - ballR,
                                  width: ballR * 2, height: ballR * 2))
        ctx.clip()
        if let g = grad([(0.0, steel(0.97)), (0.40, steel(0.66)),
                         (0.78, steel(0.28)), (1.0, steel(0.44))]) {
            ctx.drawRadialGradient(g,
                                   startCenter: CGPoint(x: ballC.x - ballR * 0.36,
                                                        y: ballC.y + ballR * 0.38),
                                   startRadius: 0, endCenter: ballC, endRadius: ballR * 1.12,
                                   options: [])
        }
        if let g = grad([(0, white(0.9)), (1, white(0.0))]) {
            let sc = CGPoint(x: ballC.x - ballR * 0.38, y: ballC.y + ballR * 0.42)
            ctx.drawRadialGradient(g, startCenter: sc, startRadius: 0,
                                   endCenter: sc, endRadius: ballR * 0.40, options: [])
        }
        ctx.restoreGState()

        return ctx.makeImage()
    }

    // MARK: Cover glass

    /// The panel reads like a phone: a sheet of glass with the emissive display
    /// sitting a little below it. The depth comes from the gap being visible —
    /// a dark inset border, then reflections that live on the glass plane
    /// rather than on the pixels.
    static func drawCoverGlass(_ ctx: CGContext, over r: CGRect) {
        ctx.saveGState()
        ctx.clip(to: r)

        // The display sits below the glass, so the glass edge shades it.
        let inset = min(r.width, r.height) * 0.018
        if let g = grad([(0, black(0.85)), (1, black(0.0))]) {
            ctx.drawLinearGradient(g, start: CGPoint(x: r.minX, y: r.maxY),
                                   end: CGPoint(x: r.minX, y: r.maxY - inset), options: [])
            ctx.drawLinearGradient(g, start: CGPoint(x: r.minX, y: r.minY),
                                   end: CGPoint(x: r.minX, y: r.minY + inset), options: [])
            ctx.drawLinearGradient(g, start: CGPoint(x: r.minX, y: r.minY),
                                   end: CGPoint(x: r.minX + inset, y: r.minY), options: [])
            ctx.drawLinearGradient(g, start: CGPoint(x: r.maxX, y: r.minY),
                                   end: CGPoint(x: r.maxX - inset, y: r.minY), options: [])
        }

        // A broad, soft reflection sweeping the upper glass.
        ctx.setBlendMode(.plusLighter)
        if let g = grad([(0.0, white(0.050)), (0.40, white(0.016)), (1.0, white(0.0))]) {
            ctx.drawRadialGradient(g,
                                   startCenter: CGPoint(x: r.minX + r.width * 0.26,
                                                        y: r.maxY + r.height * 0.16),
                                   startRadius: 0,
                                   endCenter: CGPoint(x: r.minX + r.width * 0.30, y: r.maxY),
                                   endRadius: r.width * 0.75, options: [])
        }
        // A second, tighter one low right keeps it from looking like a vignette.
        if let g = grad([(0.0, white(0.022)), (1.0, white(0.0))]) {
            ctx.drawRadialGradient(g,
                                   startCenter: CGPoint(x: r.maxX - r.width * 0.14,
                                                        y: r.minY + r.height * 0.10),
                                   startRadius: 0,
                                   endCenter: CGPoint(x: r.maxX - r.width * 0.14,
                                                      y: r.minY + r.height * 0.10),
                                   endRadius: r.width * 0.34, options: [])
        }
        ctx.setBlendMode(.normal)

        // The polished edge of the glass itself.
        ctx.setStrokeColor(white(0.10))
        ctx.setLineWidth(max(1, inset * 0.16))
        ctx.stroke(r.insetBy(dx: inset * 0.10, dy: inset * 0.10))
        ctx.restoreGState()
    }
}
