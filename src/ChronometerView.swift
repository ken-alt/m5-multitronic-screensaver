//
//  ChronometerView.swift
//  TOS Chronometer screensaver
//
//  Modelled on the stardate chronometer prop from Star Trek TOS: a dark panel
//  carrying two chrome-bezelled windows of amber drum-counter digits, an
//  indicator lamp over each, and letterspaced labels beneath.
//

import ScreenSaver
import Cocoa

// Type-scoped rather than file-scope globals on purpose — see the README note
// about file-scope `let` crashing once the bundle is dlopen'd.
private enum Style {
    static let panelFill      = CGColor(red: 0.055, green: 0.047, blue: 0.043, alpha: 1)
    static let windowFill     = CGColor(red: 0.020, green: 0.017, blue: 0.014, alpha: 1)
    static let amber          = (r: CGFloat(0.906), g: CGFloat(0.729), b: CGFloat(0.216))
    static let lamp           = (r: CGFloat(0.925), g: CGFloat(0.353), b: CGFloat(0.078))
    static let label          = CGColor(red: 0.87, green: 0.87, blue: 0.855, alpha: 1)
    static let bezelHi        = CGColor(red: 0.94, green: 0.94, blue: 0.93, alpha: 1)
    static let bezelLo        = CGColor(red: 0.42, green: 0.41, blue: 0.39, alpha: 1)

    /// Digit bloom: additive passes of (width multiple, alpha).
    static let bloom: [(w: CGFloat, a: CGFloat)] = [(2.1, 0.07), (1.45, 0.13), (1.0, 0.88)]
}

/// Stardate is not canon, so this is an explicit convention: it starts at
/// `epochValue` on `epochDate` and advances `perDay` per day, which puts the
/// present in the 3000s — the range TOS actually used. Change these two
/// constants to re-base it.
private enum Stardate {
    static let epochValue: Double = 1000.0
    static let perDay: Double = 1.0
    static let epochDate: Date = {
        var c = DateComponents()
        c.year = 2020; c.month = 1; c.day = 1
        c.timeZone = TimeZone(secondsFromGMT: 0)
        return Calendar(identifier: .gregorian).date(from: c) ?? Date(timeIntervalSince1970: 1577836800)
    }()

    static func now(_ date: Date) -> Double {
        let days = date.timeIntervalSince(epochDate) / 86400.0
        return epochValue + days * perDay
    }

    /// Four significant digits and one decimal, as the prop shows.
    static func string(_ date: Date) -> String {
        return String(format: "%.1f", now(date))
    }
}

/// One character position on a counter drum.
private struct Slot {
    var current: Character = " "
    var previous: Character = " "
    var roll: Double = 1.0      // 1 = settled, 0 = just changed
}

@objc(ChronometerView)
public class ChronometerView: ScreenSaverView {

    private var stardateSlots: [Slot] = []
    private var shipboardSlots: [Slot] = []
    private var lastTime: TimeInterval = 0
    private var drift: Double = 0
    private var labelFont: NSFont = .systemFont(ofSize: 12)

    /// Seconds for a digit to roll over. At 60fps this is ~12 frames, enough
    /// to read as a wheel turning rather than a snap.
    private let rollDuration: Double = 0.20

    public override init?(frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview)
        animationTimeInterval = 1.0 / 60.0
        wantsLayer = true
        // Helvetica is period-appropriate for the labels and ships with macOS,
        // so nothing has to be bundled.
        labelFont = NSFont(name: "Helvetica", size: 12) ?? .systemFont(ofSize: 12)
        syncSlots(force: true)
    }

    required init?(coder: NSCoder) { super.init(coder: coder) }

    public override var isOpaque: Bool { return true }
    public override var hasConfigureSheet: Bool { return false }
    public override var configureSheet: NSWindow? { return nil }

    // MARK: Slots

    private func sync(_ slots: inout [Slot], to text: String, force: Bool) {
        let chars = Array(text)
        if slots.count != chars.count {
            slots = chars.map { Slot(current: $0, previous: $0, roll: 1) }
            return
        }
        for i in chars.indices where slots[i].current != chars[i] {
            slots[i].previous = slots[i].current
            slots[i].current = chars[i]
            slots[i].roll = force ? 1.0 : 0.0
        }
    }

    private func syncSlots(force: Bool) {
        let now = Date()
        sync(&stardateSlots, to: Stardate.string(now), force: force)

        let c = Calendar.current.dateComponents([.hour, .minute, .second], from: now)
        let clock = String(format: "%02d:%02d:%02d", c.hour ?? 0, c.minute ?? 0, c.second ?? 0)
        sync(&shipboardSlots, to: clock, force: force)
    }

    // MARK: Animation

    public override func animateOneFrame() {
        let now = Date.timeIntervalSinceReferenceDate
        var dt = lastTime > 0 ? now - lastTime : 1.0 / 60.0
        lastTime = now
        if dt > 0.25 { dt = 0.25 }

        drift += dt
        syncSlots(force: false)

        for i in stardateSlots.indices where stardateSlots[i].roll < 1 {
            stardateSlots[i].roll = min(1, stardateSlots[i].roll + dt / rollDuration)
        }
        for i in shipboardSlots.indices where shipboardSlots[i].roll < 1 {
            shipboardSlots[i].roll = min(1, shipboardSlots[i].roll + dt / rollDuration)
        }

        setNeedsDisplay(bounds)
    }

    // MARK: Drawing

    public override func draw(_ rect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        ctx.setFillColor(CGColor(red: 0.012, green: 0.010, blue: 0.009, alpha: 1))
        ctx.fill(bounds)

        // Slow wander, so a clock parked on screen for hours isn't a burn-in
        // risk. Two incommensurate periods, so it never repeats exactly.
        let amp = min(bounds.width, bounds.height) * 0.035
        let dx = CGFloat(sin(drift / 97.0 * 2 * .pi)) * amp
        let dy = CGFloat(sin(drift / 131.0 * 2 * .pi)) * amp * 0.6

        let panelW = min(bounds.width * 0.72, bounds.height * 1.55)
        let panelH = panelW * 0.41
        let panel = CGRect(x: bounds.midX - panelW / 2 + dx,
                           y: bounds.midY - panelH / 2 + dy,
                           width: panelW, height: panelH)

        drawPanel(ctx, panel)

        // Proportions measured off the prop, as fractions of the panel.
        let winW = panelW * 0.355
        let winY0 = panel.maxY - panelH * 0.63
        let winY1 = panel.maxY - panelH * 0.37
        let left  = CGRect(x: panel.minX + panelW * 0.090, y: winY0, width: winW, height: winY1 - winY0)
        let right = CGRect(x: panel.minX + panelW * 0.555, y: winY0, width: winW, height: winY1 - winY0)

        let lampY = panel.maxY - panelH * 0.25
        let lampR = panelW * 0.025
        drawLamp(ctx, at: CGPoint(x: left.midX,  y: lampY), radius: lampR)
        drawLamp(ctx, at: CGPoint(x: right.midX, y: lampY), radius: lampR)

        drawWindow(ctx, left,  slots: stardateSlots)
        drawWindow(ctx, right, slots: shipboardSlots)

        let labelY = panel.maxY - panelH * 0.80
        let labelSize = panelH * 0.105
        drawLabel(ctx, "STARDATE",  centeredAt: CGPoint(x: left.midX,  y: labelY), size: labelSize)
        drawLabel(ctx, "SHIPBOARD", centeredAt: CGPoint(x: right.midX, y: labelY), size: labelSize)
    }

    private func drawPanel(_ ctx: CGContext, _ panel: CGRect) {
        ctx.setFillColor(Style.panelFill)
        ctx.fill(panel)

        // Screw heads at the corners, as on the prop.
        let inset = panel.width * 0.022
        let r = panel.width * 0.007
        ctx.setFillColor(CGColor(red: 0.34, green: 0.33, blue: 0.31, alpha: 1))
        for x in [panel.minX + inset, panel.maxX - inset] {
            for y in [panel.minY + inset, panel.maxY - inset] {
                ctx.fillEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
            }
        }
    }

    private func drawLamp(_ ctx: CGContext, at c: CGPoint, radius: CGFloat) {
        ctx.saveGState()
        ctx.setBlendMode(.plusLighter)
        let l = Style.lamp

        // Smooth halo. Stacked discs read as visible concentric rings.
        if let halo = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                 colors: [CGColor(red: l.r, green: l.g, blue: l.b, alpha: 0.34),
                                          CGColor(red: l.r, green: l.g, blue: l.b, alpha: 0.10),
                                          CGColor(red: l.r, green: l.g, blue: l.b, alpha: 0.0)] as CFArray,
                                 locations: [0.0, 0.42, 1.0]) {
            ctx.drawRadialGradient(halo, startCenter: c, startRadius: radius * 0.7,
                                   endCenter: c, endRadius: radius * 2.4, options: [])
        }
        // The dome itself.
        ctx.setFillColor(CGColor(red: l.r, green: l.g, blue: l.b, alpha: 0.95))
        ctx.fillEllipse(in: CGRect(x: c.x - radius, y: c.y - radius, width: radius * 2, height: radius * 2))
        // Specular pip.
        ctx.setFillColor(CGColor(red: 1, green: 0.85, blue: 0.6, alpha: 0.5))
        let pr = radius * 0.30
        ctx.fillEllipse(in: CGRect(x: c.x - pr - radius * 0.18, y: c.y + radius * 0.18 - pr,
                                   width: pr * 2, height: pr * 2))
        ctx.restoreGState()
    }

    private func drawWindow(_ ctx: CGContext, _ win: CGRect, slots: [Slot]) {
        let bezelW = win.height * 0.16
        let outer = win.insetBy(dx: -bezelW, dy: -bezelW)
        let radius = outer.height * 0.22

        // Chrome bezel: bright along the top, falling off towards the bottom.
        ctx.saveGState()
        let path = CGPath(roundedRect: outer, cornerWidth: radius, cornerHeight: radius, transform: nil)
        ctx.addPath(path)
        ctx.clip()
        if let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                 colors: [Style.bezelHi, Style.bezelLo] as CFArray,
                                 locations: [0, 1]) {
            ctx.drawLinearGradient(grad,
                                   start: CGPoint(x: outer.minX, y: outer.maxY),
                                   end: CGPoint(x: outer.minX, y: outer.minY),
                                   options: [])
        }
        ctx.restoreGState()

        // Window interior.
        ctx.setFillColor(Style.windowFill)
        ctx.fill(win)

        drawReading(ctx, in: win, slots: slots)

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
    private func advance(_ c: Character) -> CGFloat {
        return (c == "." || c == ":") ? 0.45 : 1.0
    }

    private func drawReading(_ ctx: CGContext, in win: CGRect, slots: [Slot]) {
        guard !slots.isEmpty else { return }

        let padX = win.width * 0.045
        let inner = win.insetBy(dx: padX, dy: 0)
        let units = slots.reduce(CGFloat(0)) { $0 + advance($1.current) }
        let gap: CGFloat = 0.16                        // between cells, in units
        let pitch = inner.width / (units + gap * CGFloat(slots.count - 1))
        let digitH = win.height * 0.60
        let digitY = win.midY - digitH / 2

        var x = inner.minX
        for slot in slots {
            let cellW = pitch * advance(slot.current)
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
                // the new one comes up from below.
                let p = CGFloat(easeInOutCubic(slot.roll))
                let travel = win.height
                drawGlyph(ctx, slot.previous, in: cell.offsetBy(dx: 0, dy: travel * p))
                drawGlyph(ctx, slot.current,  in: cell.offsetBy(dx: 0, dy: -travel * (1 - p)))
            }
            ctx.restoreGState()

            x += cellW + pitch * gap
        }
    }

    private func drawGlyph(_ ctx: CGContext, _ ch: Character, in cell: CGRect) {
        let a = Style.amber
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
            for (_, alpha) in Style.bloom {
                ctx.setFillColor(CGColor(red: a.r, green: a.g, blue: a.b, alpha: alpha))
                ctx.addPath(path)
                ctx.fillPath()
            }
        } else if let d = ch.wholeNumberValue, (0...9).contains(d) {
            let path = DrumDigits.path(d, in: cell)
            let base = cell.height * DrumDigits.strokeFraction
            for (mult, alpha) in Style.bloom {
                ctx.setStrokeColor(CGColor(red: a.r, green: a.g, blue: a.b, alpha: alpha))
                ctx.setLineWidth(base * mult)
                ctx.addPath(path)
                ctx.strokePath()
            }
        }
        ctx.restoreGState()
    }

    private func drawLabel(_ ctx: CGContext, _ text: String, centeredAt c: CGPoint, size: CGFloat) {
        let font = NSFont(name: labelFont.fontName, size: size) ?? .systemFont(ofSize: size)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor(cgColor: Style.label) ?? .white,
            .kern: size * 0.20,                 // the prop's labels are letterspaced
        ]
        let s = NSAttributedString(string: text, attributes: attrs)
        let sz = s.size()
        ctx.saveGState()
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        // The kern adds trailing space after the last glyph; pull back by half
        // of it so the text is optically centred.
        s.draw(at: NSPoint(x: c.x - (sz.width - size * 0.20) / 2, y: c.y - sz.height / 2))
        NSGraphicsContext.restoreGraphicsState()
        ctx.restoreGState()
    }
}

private func easeInOutCubic(_ p: Double) -> Double {
    return p < 0.5 ? 4 * p * p * p : 1 - pow(-2 * p + 2, 3) / 2
}
