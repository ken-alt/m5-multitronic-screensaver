//
//  CounterWindow.swift
//  Shared by the TOS Chronometer and the M-5 panel with clock.
//
//  One chrome-bezelled window of amber drum-counter digits: the reading, the
//  roll animation when a digit changes, and the drawing.
//

import Cocoa

// Type-scoped rather than file-scope globals on purpose — see the README note
// about file-scope `let` crashing once the bundle is dlopen'd.
enum CounterStyle {
    static let windowFill = CGColor(red: 0.020, green: 0.017, blue: 0.014, alpha: 1)
    static let amber      = (r: CGFloat(0.906), g: CGFloat(0.729), b: CGFloat(0.216))
    static let lamp       = (r: CGFloat(0.925), g: CGFloat(0.353), b: CGFloat(0.078))
    static let label      = CGColor(red: 0.87, green: 0.87, blue: 0.855, alpha: 1)
    static let bezelHi    = CGColor(red: 0.94, green: 0.94, blue: 0.93, alpha: 1)
    static let bezelLo    = CGColor(red: 0.42, green: 0.41, blue: 0.39, alpha: 1)

    /// Digit bloom: additive passes of (width multiple, alpha). The total stays
    /// under the point where amber clips to yellow-white.
    static let bloom: [(w: CGFloat, a: CGFloat)] = [(2.1, 0.07), (1.45, 0.13), (1.0, 0.88)]
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

    private var slots: [Slot] = []

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
    func draw(_ ctx: CGContext, in win: CGRect) {
        let bezelW = win.height * 0.16
        let outer = win.insetBy(dx: -bezelW, dy: -bezelW)
        let radius = outer.height * 0.22

        // Chrome bezel: bright along the top, falling off towards the bottom.
        ctx.saveGState()
        ctx.addPath(CGPath(roundedRect: outer, cornerWidth: radius, cornerHeight: radius, transform: nil))
        ctx.clip()
        if let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                 colors: [CounterStyle.bezelHi, CounterStyle.bezelLo] as CFArray,
                                 locations: [0, 1]) {
            ctx.drawLinearGradient(grad,
                                   start: CGPoint(x: outer.minX, y: outer.maxY),
                                   end: CGPoint(x: outer.minX, y: outer.minY),
                                   options: [])
        }
        ctx.restoreGState()

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
                // next number sits right behind the last, so a full-window
                // travel leaves a visible gap with neither digit in frame.
                let p = CGFloat(easeInOutCubic(slot.roll))
                let travel = digitH * 1.30
                drawGlyph(ctx, slot.previous, in: cell.offsetBy(dx: 0, dy: travel * p))
                drawGlyph(ctx, slot.current,  in: cell.offsetBy(dx: 0, dy: -travel * (1 - p)))
            }
            ctx.restoreGState()

            x += cellW + pitch * gap
        }
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
        } else if let d = ch.wholeNumberValue, (0...9).contains(d) {
            let path = DrumDigits.path(d, in: cell)
            let base = cell.height * DrumDigits.strokeFraction
            for (mult, alpha) in CounterStyle.bloom {
                ctx.setStrokeColor(CGColor(red: a.r, green: a.g, blue: a.b, alpha: alpha))
                ctx.setLineWidth(base * mult)
                ctx.addPath(path)
                ctx.strokePath()
            }
        }
        ctx.restoreGState()
    }
}

// MARK: - Shared chrome

enum CounterChrome {

    /// The glowing indicator dome that sits above a window on the prop.
    static func drawLamp(_ ctx: CGContext, at c: CGPoint, radius: CGFloat) {
        ctx.saveGState()
        ctx.setBlendMode(.plusLighter)
        let l = CounterStyle.lamp

        // Smooth halo. Stacked discs read as visible concentric rings.
        if let halo = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                 colors: [CGColor(red: l.r, green: l.g, blue: l.b, alpha: 0.34),
                                          CGColor(red: l.r, green: l.g, blue: l.b, alpha: 0.10),
                                          CGColor(red: l.r, green: l.g, blue: l.b, alpha: 0.0)] as CFArray,
                                 locations: [0.0, 0.42, 1.0]) {
            ctx.drawRadialGradient(halo, startCenter: c, startRadius: radius * 0.7,
                                   endCenter: c, endRadius: radius * 2.4, options: [])
        }
        ctx.setFillColor(CGColor(red: l.r, green: l.g, blue: l.b, alpha: 0.95))
        ctx.fillEllipse(in: CGRect(x: c.x - radius, y: c.y - radius, width: radius * 2, height: radius * 2))

        // Specular pip.
        ctx.setFillColor(CGColor(red: 1, green: 0.85, blue: 0.6, alpha: 0.5))
        let pr = radius * 0.30
        ctx.fillEllipse(in: CGRect(x: c.x - pr - radius * 0.18, y: c.y + radius * 0.18 - pr,
                                   width: pr * 2, height: pr * 2))
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
