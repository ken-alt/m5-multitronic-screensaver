//
//  CounterWindow.swift
//  Shared by the TOS Chronometer and the M-5 panel with clock.
//
//  One bezelled window of amber drum-counter digits: the reading, the roll
//  animation when a digit changes, and the drawing.
//

import Cocoa
import CoreText

// Type-scoped rather than file-scope globals on purpose — see the README note
// about file-scope `let` crashing once the bundle is dlopen'd.
enum CounterStyle {
    static let windowFill = CGColor(red: 0.020, green: 0.017, blue: 0.014, alpha: 1)
    static let amber      = (r: CGFloat(0.906), g: CGFloat(0.729), b: CGFloat(0.216))
    static let label      = CGColor(red: 0.87, green: 0.87, blue: 0.855, alpha: 1)

    /// Digit bloom: additive passes of (width multiple, alpha). The total stays
    /// under the point where amber clips to yellow-white.
    static let bloom: [(w: CGFloat, a: CGFloat)] = [(2.1, 0.07), (1.45, 0.13), (1.0, 0.88)]
}

/// Where the numerals come from.
enum DigitFace {
    /// Hand-built drum-counter numerals: stroked skeletons, rounded and wide.
    case drum
    /// Outlines lifted from an installed typeface, filled.
    case font(String)
}

/// One character position on a counter drum.
private struct Slot {
    var current: Character = " "
    var previous: Character = " "
    var roll: Double = 1.0      // 1 = settled, 0 = just changed
}

final class CounterWindow {

    /// Seconds for a digit to roll over. At 60fps this is ~12 frames, enough
    /// to read as a wheel turning rather than a snap.
    var rollDuration: Double = 0.20

    var face: DigitFace = .drum {
        didSet { unitPaths.removeAll() }
    }

    private var slots: [Slot] = []
    /// Glyph outlines normalised to a unit box, built once per face. Kept per
    /// instance rather than in a static so there is no shared mutable state.
    private var unitPaths: [Character: CGPath] = [:]

    func set(_ text: String, animated: Bool = true) {
        let chars = Array(text)
        if slots.count != chars.count {
            slots = chars.map { Slot(current: $0, previous: $0, roll: 1) }
            return
        }
        for i in chars.indices where slots[i].current != chars[i] {
            slots[i].previous = slots[i].current
            slots[i].current = chars[i]
            slots[i].roll = animated ? 0.0 : 1.0
        }
    }

    func advance(_ dt: Double) {
        for i in slots.indices where slots[i].roll < 1 {
            slots[i].roll = min(1, slots[i].roll + dt / rollDuration)
        }
    }

    // MARK: Drawing

    /// Draws the bezel, the window interior, the reading and the drum seam.
    ///
    /// The bezel and inner shadow are redrawn every frame. Caching them into a
    /// CGLayer was tried and measured no faster through CoreGraphics' software
    /// rasteriser, so the simpler code stands.
    func draw(_ ctx: CGContext, in win: CGRect) {
        CounterChrome.drawBezel(ctx, around: win)

        ctx.setFillColor(CounterStyle.windowFill)
        ctx.fill(win)

        drawReading(ctx, in: win)

        // The drum seam: the join between the two halves of each wheel.
        ctx.setBlendMode(.normal)
        ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0.72))
        ctx.fill(CGRect(x: win.minX, y: win.midY - win.height * 0.016,
                        width: win.width, height: win.height * 0.032))
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.07))
        ctx.fill(CGRect(x: win.minX, y: win.midY + win.height * 0.016,
                        width: win.width, height: win.height * 0.010))

        CounterChrome.drawInnerShadow(ctx, in: win)
    }

    /// Fixed pitch, as a counter is — but the punctuation gets a narrow cell.
    private func advanceWidth(_ c: Character) -> CGFloat {
        return (c == "." || c == ":") ? 0.45 : 1.0
    }

    private func drawReading(_ ctx: CGContext, in win: CGRect) {
        guard !slots.isEmpty else { return }

        let padX = win.width * 0.045
        let inner = win.insetBy(dx: padX, dy: 0)
        let units = slots.reduce(CGFloat(0)) { $0 + advanceWidth($1.current) }
        let gap: CGFloat = 0.16                        // between cells, in units
        let pitch = inner.width / (units + gap * CGFloat(slots.count - 1))
        let digitH = win.height * 0.60
        let digitY = win.midY - digitH / 2

        var x = inner.minX
        for slot in slots {
            let cellW = pitch * advanceWidth(slot.current)
            let cell = CGRect(x: x, y: digitY, width: cellW, height: digitH)

            ctx.saveGState()
            // Clip to the window so a rolling digit is cut off by the frame.
            // Widened by half the inter-cell gap: clipping tight to the cell
            // cuts the bloom off square and the edge shows.
            let bleed = pitch * gap * 0.5
            ctx.clip(to: CGRect(x: cell.minX - bleed, y: win.minY,
                                width: cell.width + bleed * 2, height: win.height))

            if slot.roll >= 1 {
                drawGlyph(ctx, slot.current, in: cell)
            } else {
                // The wheel turns upward: the old digit rises out of view while
                // the new one comes up from below. Travel is just over one
                // digit height, not the window height — on a real drum the
                // next number sits right behind the last.
                let p = CGFloat(easeInOutCubic(slot.roll))
                let travel = digitH * 1.30
                drawGlyph(ctx, slot.previous, in: cell.offsetBy(dx: 0, dy: travel * p))
                drawGlyph(ctx, slot.current,  in: cell.offsetBy(dx: 0, dy: -travel * (1 - p)))
            }
            ctx.restoreGState()

            x += cellW + pitch * gap
        }
    }

    /// Glyph outline for `ch` normalised into a unit box, cached per face.
    private func unitPath(_ ch: Character) -> CGPath? {
        if let p = unitPaths[ch] { return p }
        guard case .font(let name) = face else { return nil }
        let font = CTFontCreateWithName(name as CFString, 100, nil)

        func outline(_ c: Character) -> CGPath? {
            var utf16 = Array(String(c).utf16)
            var glyphs = [CGGlyph](repeating: 0, count: utf16.count)
            guard CTFontGetGlyphsForCharacters(font, &utf16, &glyphs, utf16.count),
                  glyphs[0] != 0 else { return nil }
            return CTFontCreatePathForGlyph(font, glyphs[0], nil)
        }
        // Scale every digit against "0" so the reading stays tabular and the
        // baseline doesn't jump between glyphs.
        guard let ref = outline("0")?.boundingBox, ref.height > 0,
              let raw = outline(ch) else { return nil }
        let box = raw.boundingBox
        guard box.height > 0, box.width > 0 else { return nil }

        // Normalise: divide through by the reference height, centre this
        // glyph horizontally on its own bounds and vertically on "0"'s.
        var t = CGAffineTransform(scaleX: 1 / ref.height, y: 1 / ref.height)
            .concatenating(CGAffineTransform(translationX: -box.midX / ref.height,
                                             y: -ref.midY / ref.height))
        guard let p = raw.copy(using: &t) else { return nil }
        unitPaths[ch] = p
        return p
    }

    private func drawGlyph(_ ctx: CGContext, _ ch: Character, in cell: CGRect) {
        let a = CounterStyle.amber
        ctx.saveGState()
        ctx.setBlendMode(.plusLighter)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)

        if ch == "." || ch == ":" {
            let path: CGPath
            if ch == ":" {
                path = DrumDigits.colonPath(in: cell)
            } else {
                let s = cell.width * 0.46
                let r = s * 0.3
                path = CGPath(roundedRect: CGRect(x: cell.midX - s / 2, y: cell.minY,
                                                  width: s, height: s),
                              cornerWidth: r, cornerHeight: r, transform: nil)
            }
            for (_, alpha) in CounterStyle.bloom {
                ctx.setFillColor(CGColor(red: a.r, green: a.g, blue: a.b, alpha: alpha))
                ctx.addPath(path)
                ctx.fillPath()
            }
            ctx.restoreGState()
            return
        }

        guard let d = ch.wholeNumberValue, (0...9).contains(d) else {
            ctx.restoreGState(); return
        }

        switch face {
        case .drum:
            let path = DrumDigits.path(d, in: cell)
            let base = cell.height * DrumDigits.strokeFraction
            for (mult, alpha) in CounterStyle.bloom {
                ctx.setStrokeColor(CGColor(red: a.r, green: a.g, blue: a.b, alpha: alpha))
                ctx.setLineWidth(base * mult)
                ctx.addPath(path)
                ctx.strokePath()
            }

        case .font:
            guard let unit = unitPath(ch) else { break }
            var t = CGAffineTransform(scaleX: cell.height, y: cell.height)
                .concatenating(CGAffineTransform(translationX: cell.midX, y: cell.midY))
            guard let path = unit.copy(using: &t) else { break }
            // The outline is filled; the glow comes from stroking it outward.
            let base = cell.height * 0.055
            for (mult, alpha) in CounterStyle.bloom {
                ctx.setFillColor(CGColor(red: a.r, green: a.g, blue: a.b, alpha: alpha))
                ctx.setStrokeColor(CGColor(red: a.r, green: a.g, blue: a.b, alpha: alpha))
                ctx.setLineWidth(base * (mult - 1.0) * 2.0)
                ctx.addPath(path)
                ctx.drawPath(using: mult > 1.0 ? .fillStroke : .fill)
            }
        }
        ctx.restoreGState()
    }
}

// MARK: - Shared chrome

enum CounterChrome {

    /// Polished aluminium. A single light-to-dark ramp reads as grey plastic;
    /// what makes metal look like metal is the banding — a hot specular line
    /// near the top, a dark mid, then a lighter band lower down where the
    /// surroundings reflect back into the curve.
    static func drawBezel(_ ctx: CGContext, around win: CGRect) {
        let bezelW = win.height * 0.16
        let outer = win.insetBy(dx: -bezelW, dy: -bezelW)
        let radius = outer.height * 0.22

        let stops: [(CGFloat, CGFloat)] = [
            (0.00, 0.62), (0.05, 0.90), (0.13, 0.99), (0.24, 0.74),
            (0.40, 0.44), (0.52, 0.38), (0.63, 0.55), (0.78, 0.86),
            (0.90, 0.66), (1.00, 0.34),
        ]
        let colors = stops.map { CGColor(red: $0.1, green: $0.1 * 0.995, blue: $0.1 * 0.975, alpha: 1) }
        let locs = stops.map { $0.0 }

        ctx.saveGState()
        ctx.addPath(CGPath(roundedRect: outer, cornerWidth: radius, cornerHeight: radius, transform: nil))
        ctx.clip()
        if let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                 colors: colors as CFArray, locations: locs) {
            ctx.drawLinearGradient(grad,
                                   start: CGPoint(x: outer.minX, y: outer.maxY),
                                   end: CGPoint(x: outer.minX, y: outer.minY),
                                   options: [])
        }
        // A machined edge catches the light along the very top and bottom.
        ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 0.99, alpha: 0.55))
        ctx.setLineWidth(max(1, bezelW * 0.07))
        ctx.move(to: CGPoint(x: outer.minX + radius, y: outer.maxY - bezelW * 0.03))
        ctx.addLine(to: CGPoint(x: outer.maxX - radius, y: outer.maxY - bezelW * 0.03))
        ctx.strokePath()
        ctx.restoreGState()
    }

    /// The window opening is cut into the bezel, so its edges cast inward.
    static func drawInnerShadow(_ ctx: CGContext, in win: CGRect) {
        let d = win.height * 0.09
        ctx.saveGState()
        ctx.clip(to: win)
        if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                              colors: [CGColor(red: 0, green: 0, blue: 0, alpha: 0.75),
                                       CGColor(red: 0, green: 0, blue: 0, alpha: 0.0)] as CFArray,
                              locations: [0, 1]) {
            ctx.drawLinearGradient(g, start: CGPoint(x: win.minX, y: win.maxY),
                                   end: CGPoint(x: win.minX, y: win.maxY - d), options: [])
            ctx.drawLinearGradient(g, start: CGPoint(x: win.minX, y: win.minY),
                                   end: CGPoint(x: win.minX, y: win.minY + d * 0.7), options: [])
            ctx.drawLinearGradient(g, start: CGPoint(x: win.minX, y: win.minY),
                                   end: CGPoint(x: win.minX + d * 0.6, y: win.minY), options: [])
            ctx.drawLinearGradient(g, start: CGPoint(x: win.maxX, y: win.minY),
                                   end: CGPoint(x: win.maxX - d * 0.6, y: win.minY), options: [])
        }
        ctx.restoreGState()
    }

    /// A lit LED: dark housing, an emissive lens with a hot core, a specular
    /// highlight off the dome, and light spilling onto the panel around it.
    static func drawLED(_ ctx: CGContext, at c: CGPoint, radius r: CGFloat,
                        red: CGFloat, green: CGFloat, blue: CGFloat) {
        let cs = CGColorSpaceCreateDeviceRGB()

        // Spill onto the surrounding panel.
        ctx.saveGState()
        ctx.setBlendMode(.plusLighter)
        if let halo = CGGradient(colorsSpace: cs,
                                 colors: [CGColor(red: red, green: green, blue: blue, alpha: 0.30),
                                          CGColor(red: red, green: green, blue: blue, alpha: 0.09),
                                          CGColor(red: red, green: green, blue: blue, alpha: 0.0)] as CFArray,
                                 locations: [0.0, 0.40, 1.0]) {
            ctx.drawRadialGradient(halo, startCenter: c, startRadius: r * 0.8,
                                   endCenter: c, endRadius: r * 3.0, options: [])
        }
        ctx.restoreGState()

        // Housing: a dark collar the lens sits in.
        ctx.setFillColor(CGColor(red: 0.10, green: 0.09, blue: 0.09, alpha: 1))
        ctx.fillEllipse(in: CGRect(x: c.x - r * 1.22, y: c.y - r * 1.22,
                                   width: r * 2.44, height: r * 2.44))
        ctx.setStrokeColor(CGColor(red: 0.42, green: 0.41, blue: 0.40, alpha: 0.7))
        ctx.setLineWidth(max(0.6, r * 0.07))
        ctx.strokeEllipse(in: CGRect(x: c.x - r * 1.18, y: c.y - r * 1.18,
                                     width: r * 2.36, height: r * 2.36))

        // The lens: hot near the centre, deepening towards the rim.
        let lens = CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)
        ctx.saveGState()
        ctx.addEllipse(in: lens)
        ctx.clip()
        if let body = CGGradient(colorsSpace: cs,
                                 colors: [CGColor(red: min(1, red * 1.6 + 0.45),
                                                  green: min(1, green * 1.4 + 0.42),
                                                  blue: min(1, blue * 1.4 + 0.38), alpha: 1),
                                          CGColor(red: min(1, red * 1.15), green: green, blue: blue, alpha: 1),
                                          CGColor(red: red * 0.62, green: green * 0.32, blue: blue * 0.32, alpha: 1)] as CFArray,
                                 locations: [0.0, 0.45, 1.0]) {
            ctx.drawRadialGradient(body,
                                   startCenter: CGPoint(x: c.x - r * 0.18, y: c.y + r * 0.22),
                                   startRadius: 0,
                                   endCenter: c, endRadius: r, options: [])
        }
        // Specular: the sharp reflection off the top of the dome.
        if let spec = CGGradient(colorsSpace: cs,
                                 colors: [CGColor(red: 1, green: 1, blue: 1, alpha: 0.80),
                                          CGColor(red: 1, green: 1, blue: 1, alpha: 0.0)] as CFArray,
                                 locations: [0, 1]) {
            let sc = CGPoint(x: c.x - r * 0.30, y: c.y + r * 0.40)
            ctx.drawRadialGradient(spec, startCenter: sc, startRadius: 0,
                                   endCenter: sc, endRadius: r * 0.46, options: [])
        }
        ctx.restoreGState()
    }

    /// Letterspaced caps, as on the prop. Helvetica ships with macOS, so
    /// nothing has to be bundled.
    static func drawLabel(_ ctx: CGContext, _ text: String,
                          centeredAt c: CGPoint, size: CGFloat) {
        let font = NSFont(name: "Helvetica", size: size) ?? .systemFont(ofSize: size)
        let kern = size * 0.20
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor(cgColor: CounterStyle.label) ?? .white,
            .kern: kern,
        ]
        let s = NSAttributedString(string: text, attributes: attrs)
        let sz = s.size()
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        // The kern adds trailing space after the last glyph; pull back by it so
        // the text is optically centred.
        s.draw(at: NSPoint(x: c.x - (sz.width - kern) / 2, y: c.y - sz.height / 2))
        NSGraphicsContext.restoreGraphicsState()
    }
}

func easeInOutCubic(_ p: Double) -> Double {
    return p < 0.5 ? 4 * p * p * p : 1 - pow(-2 * p + 2, 3) / 2
}
