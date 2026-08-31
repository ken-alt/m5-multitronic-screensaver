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
    /// The drum is a physical surface, so it is a dark warm grey rather than
    /// black. Against black the numerals just float.
    static let windowFill = CGColor(red: 0.118, green: 0.101, blue: 0.076, alpha: 1)
    static let amber      = (r: CGFloat(0.965), g: CGFloat(0.820), b: CGFloat(0.290))
    static let label      = CGColor(red: 0.87, green: 0.87, blue: 0.855, alpha: 1)

    /// The original prop reads the other way round: dark numerals printed on
    /// pale drums behind a white mask, rather than lit numerals on a dark one.
    static let retroDrum = CGColor(red: 0.880, green: 0.834, blue: 0.716, alpha: 1)
    static let retroInk  = CGColor(red: 0.086, green: 0.082, blue: 0.074, alpha: 1)
    static let retroMask = CGColor(red: 0.905, green: 0.901, blue: 0.889, alpha: 1)

    /// The digits are printed on a drum and lit from outside, not emissive, so
    /// this is a faint edge spill rather than a glow. The prop's numerals are
    /// crisp; a big bloom is the tell that something is faked.
    static let bloom: [(w: CGFloat, a: CGFloat)] = [(1.5, 0.05), (1.0, 1.0)]
}

/// Which construction the window is built as.
enum CounterFinish {
    /// Lit amber numerals on a dark drum, as the remastered episode shows.
    case modern
    /// Dark numerals on pale drums behind a white mask, as the original prop.
    case retro
}

/// Where the numerals come from.
enum DigitFace: Equatable {
    /// Hand-built drum-counter numerals: stroked skeletons, rounded and wide.
    case drum
    /// Outlines lifted from an installed typeface, by PostScript name.
    case font(String)
    /// The San Francisco system face, reached through the system API rather
    /// than by name — asking CoreText for ".SFNS-Bold" by name silently hands
    /// back Times New Roman. `width` is the descriptor width trait: 0 is
    /// standard, -0.2 condensed, -0.4 extra compressed.
    case system(weight: CGFloat, width: CGFloat)

    /// nil when the named font isn't installed, so the caller can fall back.
    func resolved() -> CTFont? {
        switch self {
        case .drum:
            return nil
        case .font(let name):
            let f = CTFontCreateWithName(name as CFString, 100, nil)
            // CoreText substitutes silently, so confirm we got what we asked for.
            guard (CTFontCopyPostScriptName(f) as String) == name else { return nil }
            return f
        case .system(let weight, let width):
            let base = NSFont.systemFont(ofSize: 100, weight: NSFont.Weight(weight))
            guard width != 0 else { return base as CTFont }
            // SF carries a real wdth axis on modern macOS; on older releases
            // this resolves back to the standard width rather than failing.
            let d = base.fontDescriptor.addingAttributes([
                .traits: [NSFontDescriptor.TraitKey.width: width]
            ])
            return (NSFont(descriptor: d, size: 100) ?? base) as CTFont
        }
    }
}

/// Picks the numerals. Everything here ships with macOS, so friends need
/// install nothing and the repo bundles no font — which also keeps licensed
/// faces (Univers, Adobe's DIN) out of it entirely.
enum DigitFacePreference {
    static func best() -> DigitFace {
        let candidates: [DigitFace] = [
            .font("DINCondensed-Bold"),             // /System/Library/Fonts/Supplemental
            .system(weight: 0.4, width: -0.2),      // SF Condensed Bold
        ]
        for c in candidates where c.resolved() != nil { return c }
        return .drum
    }
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

    /// When set, the reading uses this cell pitch instead of scaling to fill
    /// its own aperture, so several windows can share one digit size. Without
    /// it, an equal-width window holding two characters draws them far larger
    /// than one holding five.
    var finish: CounterFinish = .modern

    var fixedPitch: CGFloat?

    /// When set, overrides the glyph height. The fit cap below is computed per
    /// window from its own widest character, so a window holding "M" would
    /// otherwise draw smaller than one holding only digits.
    var fixedDigitHeight: CGFloat?

    /// How much of a cell the widest character may occupy. Fitting it exactly
    /// leaves it touching the drum bounds while narrower glyphs sit clear.
    static let glyphFit: CGFloat = 0.86

    /// False when the whole reading rides one wheel — the meridiem is a single
    /// drum showing a word, so it gets no break through the middle.
    var splitsBetweenCharacters = true

    var face: DigitFace = .drum {
        didSet { unitPaths.removeAll() }
    }

    private var slots: [Slot] = []
    /// Glyph outlines normalised to a unit box, built once per face. Kept per
    /// instance rather than in a static so there is no shared mutable state.
    private var unitPaths: [Character: CGPath] = [:]
    /// Horizontal extent of the drums from the last draw, so the mask cutout
    /// can be sized to expose exactly that and no more.
    private var drumExtent: (CGFloat, CGFloat)?

    /// Glyph height from the last draw. The mask opening is derived from it —
    /// a fixed fraction of aperture height cannot know how tall the numerals
    /// ended up and will crop them once the proportions change.
    private var lastDigitHeight: CGFloat = 0

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

    /// The window as a physical assembly: a cut-out in the panel, an aluminium
    /// bezel sitting proud of it, glass, and a lit drum on its own plane
    /// behind. Lamps sit just inside the top and bottom of the opening and
    /// wash across the drum, the way a speedometer is lit.
    func draw(_ ctx: CGContext, in win: CGRect) {
        let bezelW = CounterChrome.bezelWidth(forAperture: win)
        let outer = win.insetBy(dx: -CounterChrome.bezelSideWidth(forAperture: win), dy: -bezelW)

        CounterChrome.drawBezel(ctx, around: win, finish: finish)
        CounterChrome.drawDrumFace(ctx, in: win, finish: finish)

        let lit = drawReading(ctx, in: win)

        if finish == .modern {
            CounterChrome.drawLampFalloff(ctx, in: win)
            CounterChrome.drawDigitSheen(ctx, in: win, glyphs: lit)
            CounterChrome.drawLamps(ctx, in: win)
        } else {
            CounterChrome.drawRetroShading(ctx, in: win)
        }

        // No seam across the middle. A split-flap has one; a rotating barrel
        // shows a continuous digit face, and the hard line read as the wrong
        // mechanism entirely.
        ctx.setBlendMode(.normal)

        CounterChrome.drawLetterbox(ctx, in: win, finish: finish,
                                    cutout: drumExtent, digitHeight: lastDigitHeight)
        CounterChrome.drawGloss(ctx, in: win)
        CounterChrome.drawInnerShadow(ctx, in: win)
    }

    /// One cell per character, all the same width. Every character rides its
    /// own drum on a real counter, and the drums are identical — so narrowing
    /// the punctuation would be wrong as well as uneven.
    static func advanceWidth(_ c: Character) -> CGFloat { return 1.0 }
    private func advanceWidth(_ c: Character) -> CGFloat { return CounterWindow.advanceWidth(c) }

    /// Space between cells, in cell widths.
    static let cellGap: CGFloat = 0.16
    /// Padding inside each end of the aperture, as a fraction of its height.
    static let padFraction: CGFloat = 0.176

    /// Cell-widths `text` occupies, gaps included.
    static func units(for text: String) -> CGFloat {
        let chars = Array(text)
        guard !chars.isEmpty else { return 0 }
        let w = chars.reduce(CGFloat(0)) { $0 + advanceWidth($1) }
        return w + cellGap * CGFloat(chars.count - 1)
    }

    /// Aperture width needed to show `text` at a given digit pitch. Lets
    /// several windows share one pitch so they read as one instrument rather
    /// than three separately-scaled boxes.
    static func apertureWidth(for text: String, pitch: CGFloat, height: CGFloat) -> CGFloat {
        return pitch * units(for: text) + 2 * height * padFraction
    }

    /// Draws the reading and returns the outline of every glyph it drew, so
    /// the caller can light the numerals rather than the whole aperture.
    @discardableResult
    private func drawReading(_ ctx: CGContext, in win: CGRect) -> CGPath {
        let lit = CGMutablePath()
        guard !slots.isEmpty else { return lit }

        // Proportional to height, not width: a narrow window scaled by its own
        // width ends up with a fraction of the padding the wide one gets, and
        // the reading sits jammed against the frame.
        let padX = win.height * CounterWindow.padFraction
        let inner = win.insetBy(dx: padX, dy: 0)
        let units = slots.reduce(CGFloat(0)) { $0 + advanceWidth($1.current) }
        let gap = CounterWindow.cellGap
        let pitch = fixedPitch ?? (inner.width / (units + gap * CGFloat(slots.count - 1)))
        // Cap the glyph height so the widest character still fits its cell.
        var digitH = win.height * 0.60
        if let forced = fixedDigitHeight {
            digitH = forced
        } else {
            let ratio = widestGlyphRatio()
            if ratio > 0 { digitH = min(digitH, pitch * CounterWindow.glyphFit / ratio) }
        }
        lastDigitHeight = digitH
        let digitY = win.midY - digitH / 2

        // Centre the reading in the aperture: with every window the same size,
        // a two-character reading would otherwise sit hard against the left.
        let readingW = pitch * units + pitch * gap * CGFloat(max(0, slots.count - 1))
        var boundaries: [CGFloat] = []
        var extentLo: CGFloat = 0
        var extentHi: CGFloat = 0
        var x = inner.minX + max(0, inner.width - readingW) / 2
        for (slotIndex, slot) in slots.enumerated() {
            let cellW = pitch * advanceWidth(slot.current)
            let cell = CGRect(x: x, y: digitY, width: cellW, height: digitH)

            ctx.saveGState()
            // Clip to the window so a rolling digit is cut off by the frame.
            // Widened by half the inter-cell gap: clipping tight to the cell
            // cuts the bloom off square and the edge shows.
            let bleed = pitch * gap * 0.5
            ctx.addPath(CounterChrome.aperture(win))
            ctx.clip()
            ctx.clip(to: CGRect(x: cell.minX - bleed, y: win.minY,
                                width: cell.width + bleed * 2, height: win.height))

            if slot.roll >= 1 {
                drawGlyph(ctx, slot.current, in: cell, collecting: lit)
            } else {
                // The wheel turns upward: the old digit rises out of view while
                // the new one comes up from below. Travel is just over one
                // digit height, not the window height — on a real drum the
                // next number sits right behind the last.
                let p = CGFloat(easeInOutCubic(slot.roll))
                // Far enough that the outgoing digit has cleared the aperture
                // before the incoming one is fully in. Keying this to digit
                // height alone breaks once the glyphs are small relative to the
                // window: both readings end up visible, stacked.
                let travel = max(digitH * 1.30, (win.height + digitH) * 0.5)
                drawGlyph(ctx, slot.previous, in: cell.offsetBy(dx: 0, dy: travel * p),
                          collecting: lit)
                drawGlyph(ctx, slot.current,  in: cell.offsetBy(dx: 0, dy: -travel * (1 - p)),
                          collecting: lit)
            }
            ctx.restoreGState()

            // Bound every drum on both sides, so the outer wheels are the
            // same width as the inner ones rather than running to the edge.
            let edge = pitch * gap * (splitsBetweenCharacters ? 0.5 : 1.1)
            let boundsOuter = finish != .retro
            if slotIndex == 0 {
                if boundsOuter { boundaries.append(x - edge) }
                extentLo = x - edge
            }
            if slotIndex == slots.count - 1 {
                if boundsOuter { boundaries.append(x + cellW + edge) }
                extentHi = x + cellW + edge
            } else if splitsBetweenCharacters {
                boundaries.append(x + cellW + pitch * gap * 0.5)
            }
            x += cellW + pitch * gap
        }

        // Each character rides its own wheel, so there is a physical break
        // between them. A thin dark line reads as the gap between drums.
        ctx.saveGState()
        CounterChrome.clipApertureFor(ctx, win)
        ctx.setBlendMode(.normal)
        ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0,
                                 alpha: finish == .retro ? 0.88 : 0.72))
        let sepW = max(1, win.height * (finish == .retro ? 0.020 : 0.014))
        drumExtent = (extentLo, extentHi)
        for bx in boundaries {
            ctx.fill(CGRect(x: bx - sepW / 2, y: win.minY, width: sepW, height: win.height))
        }
        ctx.restoreGState()

        return lit
    }

    /// Printed numerals: a flat dark shape on the drum, no glow at all.
    private func drawInkGlyph(_ ctx: CGContext, _ ch: Character, in cell: CGRect,
                              collecting lit: CGMutablePath?) {
        ctx.saveGState()
        ctx.setBlendMode(.normal)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.setFillColor(CounterStyle.retroInk)
        ctx.setStrokeColor(CounterStyle.retroInk)

        if ch == "." || ch == ":" {
            ctx.addPath(ch == ":" ? DrumDigits.colonPath(in: cell) : DrumDigits.dotPath(in: cell))
            ctx.fillPath()
            ctx.restoreGState()
            return
        }
        switch face {
        case .drum:
            if let d = ch.wholeNumberValue, (0 ... 9).contains(d) {
                let path = DrumDigits.path(d, in: cell)
                ctx.setLineWidth(cell.height * DrumDigits.strokeFraction)
                ctx.addPath(path)
                ctx.strokePath()
                lit?.addPath(path.copy(strokingWithWidth: cell.height * DrumDigits.strokeFraction,
                                       lineCap: .round, lineJoin: .round, miterLimit: 10))
            }
        case .font, .system:
            if let unit = unitPath(ch) {
                var t = CGAffineTransform(scaleX: cell.height, y: cell.height)
                    .concatenating(CGAffineTransform(translationX: cell.midX, y: cell.midY))
                if let path = unit.copy(using: &t) {
                    ctx.addPath(path)
                    ctx.fillPath()
                    lit?.addPath(path)
                }
            }
        }
        ctx.restoreGState()
    }

    /// Width of the widest glyph currently shown, as a multiple of digit
    /// height. Glyph size follows the aperture height while cell width follows
    /// the pitch, so without this the two can disagree and the reading spills
    /// out of its cells.
    func widestGlyphRatio() -> CGFloat {
        var widest: CGFloat = 0
        for slot in slots {
            guard let p = unitPath(slot.current) else { continue }
            widest = max(widest, p.boundingBox.width)
        }
        return widest
    }

    /// Glyph outline for `ch` normalised into a unit box, cached per face.
    private func unitPath(_ ch: Character) -> CGPath? {
        if let p = unitPaths[ch] { return p }
        guard let font = face.resolved() else { return nil }

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

    private func drawGlyph(_ ctx: CGContext, _ ch: Character, in cell: CGRect,
                           collecting lit: CGMutablePath? = nil) {
        if finish == .retro { drawInkGlyph(ctx, ch, in: cell, collecting: lit); return }
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
                path = DrumDigits.dotPath(in: cell)
            }
            for (_, alpha) in CounterStyle.bloom {
                ctx.setFillColor(CGColor(red: a.r, green: a.g, blue: a.b, alpha: alpha))
                ctx.addPath(path)
                ctx.fillPath()
            }
            lit?.addPath(path)
            ctx.restoreGState()
            return
        }

        switch face {
        case .drum:
            guard let d = ch.wholeNumberValue, (0...9).contains(d) else {
                ctx.restoreGState(); return
            }
            let path = DrumDigits.path(d, in: cell)
            let base = cell.height * DrumDigits.strokeFraction
            for (mult, alpha) in CounterStyle.bloom {
                ctx.setStrokeColor(CGColor(red: a.r, green: a.g, blue: a.b, alpha: alpha))
                ctx.setLineWidth(base * mult)
                ctx.addPath(path)
                ctx.strokePath()
            }
            // The skeleton is a stroke, so turn it into an outline to light.
            lit?.addPath(path.copy(strokingWithWidth: base, lineCap: .round,
                                   lineJoin: .round, miterLimit: 10))

        case .font, .system:
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
            lit?.addPath(path)
        }
        ctx.restoreGState()
    }
}

// MARK: - Shared chrome

enum CounterChrome {

    private static func grad(_ stops: [(CGFloat, CGColor)]) -> CGGradient? {
        return CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                          colors: stops.map { $0.1 } as CFArray,
                          locations: stops.map { $0.0 })
    }
    private static func white(_ a: CGFloat) -> CGColor {
        return CGColor(red: 1, green: 1, blue: 1, alpha: a)
    }
    private static func black(_ a: CGFloat) -> CGColor {
        return CGColor(red: 0, green: 0, blue: 0, alpha: a)
    }
    private static func grey(_ v: CGFloat) -> CGColor {
        // Aluminium is very slightly warm, never neutral.
        return CGColor(red: v, green: v * 0.995, blue: v * 0.975, alpha: 1)
    }

    /// How far the bezel stands out past the aperture on every side. Layout
    /// code must use this rather than repeating the constant, or windows end
    /// up with overlapping frames.
    static func bezelWidth(forAperture win: CGRect) -> CGFloat {
        return win.height * 0.135
    }

    /// The frame is wider at the sides than top and bottom, which is what makes
    /// the dark inner edge legible instead of a hairline.
    static let bezelSideFactor: CGFloat = 1.75

    /// The outer edge is squarer than the aperture — a stamped frame rather
    /// than a moulded one — so it is not simply the inner radius plus the
    /// frame width. The frame thickens a little at the corners as a result,
    /// which is what a pressed bezel actually does.
    static let outerRadiusFactor: CGFloat = 0.42

    static func bezelSideWidth(forAperture win: CGRect) -> CGFloat {
        return bezelWidth(forAperture: win) * bezelSideFactor
    }

    /// The opening is rounded, following the bezel rather than cutting a hard
    /// rectangle out of it.
    static let apertureRadiusFraction: CGFloat = 0.10

    static func apertureRadius(_ win: CGRect) -> CGFloat {
        return win.height * apertureRadiusFraction
    }

    static func aperture(_ win: CGRect) -> CGPath {
        let r = apertureRadius(win)
        return CGPath(roundedRect: win, cornerWidth: r, cornerHeight: r, transform: nil)
    }
    static func clipApertureFor(_ ctx: CGContext, _ win: CGRect) {
        clipAperture(ctx, win)
    }
    private static func clipAperture(_ ctx: CGContext, _ win: CGRect) {
        ctx.addPath(aperture(win))
        ctx.clip()
    }

    /// The screen itself: gloss black, the way an OLED panel reads when it is
    /// off. Never flat — it picks up the room.
    static func drawScreen(_ ctx: CGContext, in r: CGRect) {
        ctx.setFillColor(CGColor(red: 0.014, green: 0.013, blue: 0.015, alpha: 1))
        ctx.fill(r)
        ctx.saveGState()
        ctx.clip(to: r)
        ctx.setBlendMode(.plusLighter)
        if let g = grad([(0.0, white(0.028)), (0.55, white(0.007)), (1.0, white(0.0))]) {
            ctx.drawRadialGradient(g,
                                   startCenter: CGPoint(x: r.minX + r.width * 0.30, y: r.maxY),
                                   startRadius: 0,
                                   endCenter: CGPoint(x: r.minX + r.width * 0.34, y: r.maxY),
                                   endRadius: r.width * 0.85, options: [])
        }
        ctx.restoreGState()
    }

    /// The chronometer is a separate unit sunk into the screen. This is the
    /// hole it sits in and the faceplate that fills it — the screen surface
    /// overhangs the top edge and catches light along the bottom.
    static func drawUnitPlate(_ ctx: CGContext, _ plate: CGRect, screwInset: CGFloat) {
        let r = plate.height * 0.028
        let path = CGPath(roundedRect: plate, cornerWidth: r, cornerHeight: r, transform: nil)

        // The cut-out edge: a dark line all round, so the unit reads as sunk.
        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: plate.height * 0.045, color: black(0.95))
        ctx.setFillColor(black(1))
        ctx.addPath(path)
        ctx.fillPath()
        ctx.restoreGState()

        ctx.saveGState()
        ctx.addPath(path)
        ctx.clip()
        // Faceplate: dark charcoal, very slightly lit from above.
        // Black anodised aluminium: a cool, nearly neutral dark with a satin
        // sheen, not the warm charcoal of painted steel.
        if let g = grad([(0.0, CGColor(red: 0.083, green: 0.085, blue: 0.092, alpha: 1)),
                         (0.5, CGColor(red: 0.055, green: 0.057, blue: 0.063, alpha: 1)),
                         (1.0, CGColor(red: 0.036, green: 0.037, blue: 0.042, alpha: 1))]) {
            ctx.drawLinearGradient(g, start: CGPoint(x: plate.minX, y: plate.maxY),
                                   end: CGPoint(x: plate.minX, y: plate.minY), options: [])
        }
        // Satin sheen across the anodised face.
        ctx.setBlendMode(.plusLighter)
        if let g = grad([(0.0, white(0.030)), (0.45, white(0.008)), (1.0, white(0.0))]) {
            ctx.drawRadialGradient(g,
                                   startCenter: CGPoint(x: plate.minX + plate.width * 0.24,
                                                        y: plate.maxY + plate.height * 0.5),
                                   startRadius: 0,
                                   endCenter: CGPoint(x: plate.minX + plate.width * 0.30,
                                                      y: plate.maxY),
                                   endRadius: plate.width * 0.62, options: [])
        }
        ctx.setBlendMode(.normal)

        // The screen overhangs the top of the recess and shades it.
        if let g = grad([(0, black(0.75)), (1, black(0))]) {
            ctx.drawLinearGradient(g, start: CGPoint(x: plate.minX, y: plate.maxY),
                                   end: CGPoint(x: plate.minX, y: plate.maxY - plate.height * 0.10),
                                   options: [])
            ctx.drawLinearGradient(g, start: CGPoint(x: plate.minX, y: plate.minY),
                                   end: CGPoint(x: plate.minX + plate.width * 0.012, y: plate.minY),
                                   options: [])
        }
        if let g = grad([(0, white(0.10)), (1, white(0))]) {
            ctx.drawLinearGradient(g, start: CGPoint(x: plate.minX, y: plate.minY),
                                   end: CGPoint(x: plate.minX, y: plate.minY + plate.height * 0.035),
                                   options: [])
        }
        ctx.restoreGState()

        drawScrews(ctx, in: plate, inset: screwInset)
    }

    /// Panel screws, as on the prop: corners plus midpoints along the long edges.
    static func drawScrews(_ ctx: CGContext, in plate: CGRect, inset: CGFloat) {
        let rad = plate.height * 0.020
        var i = 0
        for x in [plate.minX + inset, plate.midX, plate.maxX - inset] {
            for y in [plate.minY + inset * 0.75, plate.maxY - inset * 0.75] {
                // Vary the driver angle; identical screws read as wallpaper.
                Hardware.drawScrew(ctx, at: CGPoint(x: x, y: y), radius: rad,
                                   angle: CGFloat(i) * 0.7 + 0.35)
                i += 1
            }
        }
    }

    /// A rounded aluminium bezel standing a couple of millimetres proud of the
    /// panel. The cross-section is a roll, not a flat ramp: the outer edge
    /// turns away from the light, the crown just inside it takes the specular,
    /// the lower slope falls into shade, then lifts again where the panel
    /// bounces light back up into the underside.
    static func drawBezel(_ ctx: CGContext, around win: CGRect,
                          finish: CounterFinish = .modern) {
        let bezelW = bezelWidth(forAperture: win)
        let sideW = bezelSideWidth(forAperture: win)
        let outer = win.insetBy(dx: -sideW, dy: -bezelW)
        // Concentric with the aperture: each corner radius is the inner radius
        // plus that axis' frame width, so the frame keeps its thickness round
        // the corners rather than fattening. Height comes from the shading.
        let path = CGPath(roundedRect: outer,
                          cornerWidth: (apertureRadius(win) + sideW) * outerRadiusFactor,
                          cornerHeight: (apertureRadius(win) + bezelW) * outerRadiusFactor,
                          transform: nil)

        // It stands off the panel, so it casts a real shadow downwards.
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: bezelW * 0.10, height: -bezelW * 0.62),
                      blur: bezelW * 1.05, color: black(0.82))
        ctx.setFillColor(grey(0.5))
        ctx.addPath(path)
        ctx.fillPath()
        ctx.restoreGState()

        ctx.saveGState()
        ctx.addPath(path)
        ctx.clip()
        // The original's frame is brighter and flatter — polished trim rather
        // than a heavy machined roll.
        let stops: [(CGFloat, CGFloat)] = finish == .retro ? [
            (0.00, 0.74), (0.10, 0.97), (0.26, 0.90), (0.50, 0.78),
            (0.72, 0.84), (0.90, 0.92), (1.00, 0.62),
        ] : [
            (0.00, 0.60),   // outer edge rolling away from the light
            (0.09, 0.96),   // crown
            (0.22, 0.87),
            (0.44, 0.68),
            (0.64, 0.57),   // lower slope in shade
            (0.82, 0.74),   // bounce off the panel
            (0.94, 0.82),
            (1.00, 0.44),   // underside
        ]
        if let g = grad(stops.map { ($0.0, grey($0.1)) }) {
            ctx.drawLinearGradient(g, start: CGPoint(x: outer.minX, y: outer.maxY),
                                   end: CGPoint(x: outer.minX, y: outer.minY), options: [])
        }
        ctx.restoreGState()

        // Silhouette: a bright hairline where the top edge catches, a dark one
        // under the bottom. Without these the roll has no crisp boundary.
        ctx.saveGState()
        ctx.addPath(path)
        ctx.clip()
        if let g = grad([(0, white(0.55)), (1, white(0.0))]) {
            ctx.drawLinearGradient(g, start: CGPoint(x: outer.minX, y: outer.maxY),
                                   end: CGPoint(x: outer.minX, y: outer.maxY - bezelW * 0.20),
                                   options: [])
        }
        if let g = grad([(0, black(0.55)), (1, black(0.0))]) {
            ctx.drawLinearGradient(g, start: CGPoint(x: outer.minX, y: outer.minY),
                                   end: CGPoint(x: outer.minX, y: outer.minY + bezelW * 0.22),
                                   options: [])
        }
        ctx.restoreGState()

        if finish == .retro {
            // The prop has a fine dark line just inside the trim, where the
            // glass is held.
            ctx.setStrokeColor(black(0.92))
            ctx.setLineWidth(max(1, bezelW * 0.30))
            ctx.addPath(aperture(win.insetBy(dx: -bezelW * 0.15, dy: -bezelW * 0.15)))
            ctx.strokePath()
        }

        // Where the roll turns down into the aperture.
        ctx.saveGState()
        let innerR = apertureRadius(win)
        let lip = CGMutablePath()
        lip.addPath(CGPath(roundedRect: win.insetBy(dx: -bezelW * 0.42, dy: -bezelW * 0.42),
                           cornerWidth: innerR + bezelW * 0.42,
                           cornerHeight: innerR + bezelW * 0.42, transform: nil))
        lip.addPath(aperture(win))
        ctx.addPath(lip)
        ctx.clip(using: .evenOdd)
        if let g = grad([(0, black(0.50)), (0.45, black(0.0)), (1.0, white(0.30))]) {
            ctx.drawLinearGradient(g, start: CGPoint(x: outer.minX, y: win.maxY + bezelW * 0.42),
                                   end: CGPoint(x: outer.minX, y: win.minY - bezelW * 0.42),
                                   options: [])
        }
        ctx.restoreGState()
    }

    /// The drum face behind the glass: near-black, but curved, so it is never
    /// flat — slightly open at the top where the lamp reaches it.
    static func drawDrumFace(_ ctx: CGContext, in win: CGRect,
                             finish: CounterFinish = .modern) {
        ctx.saveGState()
        clipAperture(ctx, win)
        if finish == .retro {
            ctx.setFillColor(CounterStyle.retroDrum)
            ctx.fill(win)
            ctx.restoreGState()
            return
        }
        ctx.setFillColor(CounterStyle.windowFill)
        ctx.fill(win)
        let a = CounterStyle.amber
        let warmLift = { (v: CGFloat) in
            CGColor(red: a.r, green: a.g * 0.95, blue: a.b * 1.6, alpha: v)
        }
        if let g = grad([(0.0, warmLift(0.070)), (0.28, warmLift(0.020)),
                         (0.62, warmLift(0.004)), (1.0, warmLift(0.0))]) {
            ctx.drawLinearGradient(g, start: CGPoint(x: win.minX, y: win.maxY),
                                   end: CGPoint(x: win.minX, y: win.minY), options: [])
        }
        ctx.restoreGState()
    }

    /// Lamps sit inside the top and bottom of the opening, so the drum is
    /// brightest at its edges and falls away through the middle. Multiplied,
    /// so it dims the digits and the drum together — they share a plane.
    static func drawLampFalloff(_ ctx: CGContext, in win: CGRect) {
        ctx.saveGState()
        clipAperture(ctx, win)
        ctx.setBlendMode(.multiply)
        if let g = grad([(0.0, black(0.0)), (0.28, black(0.20)),
                         (0.50, black(0.34)), (0.72, black(0.20)), (1.0, black(0.0))]) {
            ctx.drawLinearGradient(g, start: CGPoint(x: win.minX, y: win.maxY),
                                   end: CGPoint(x: win.minX, y: win.minY), options: [])
        }
        ctx.restoreGState()
    }

    /// Light falling on the numeral faces. Clipped to the glyphs themselves,
    /// so the digits are brightest where the lamps are — at the top and bottom
    /// of the aperture — and fall away through the middle. Dimming the whole
    /// aperture instead just makes everything muddy; this is what actually
    /// reads as a lit drum.
    static func drawDigitSheen(_ ctx: CGContext, in win: CGRect, glyphs: CGPath) {
        guard !glyphs.isEmpty else { return }
        let a = CounterStyle.amber
        let warm = { (v: CGFloat) in
            CGColor(red: min(1, a.r * 1.05), green: a.g, blue: a.b * 0.75, alpha: v)
        }
        ctx.saveGState()
        clipAperture(ctx, win)
        ctx.addPath(glyphs)
        ctx.clip()
        ctx.setBlendMode(.plusLighter)
        if let g = grad([(0.0, warm(0.62)), (0.22, warm(0.20)), (0.46, warm(0.0)),
                         (0.58, warm(0.0)), (0.80, warm(0.16)), (1.0, warm(0.48))]) {
            ctx.drawLinearGradient(g, start: CGPoint(x: win.minX, y: win.maxY),
                                   end: CGPoint(x: win.minX, y: win.minY), options: [])
        }
        ctx.restoreGState()
    }

    /// The light itself, spilling off the lamps onto the drum.
    static func drawLamps(_ ctx: CGContext, in win: CGRect) {
        let a = CounterStyle.amber
        let warm = { (v: CGFloat) in CGColor(red: a.r, green: a.g * 0.86, blue: a.b * 0.55, alpha: v) }
        let reach = win.height * 0.22
        ctx.saveGState()
        clipAperture(ctx, win)
        ctx.setBlendMode(.plusLighter)
        if let g = grad([(0, warm(0.065)), (1, warm(0.0))]) {
            ctx.drawLinearGradient(g, start: CGPoint(x: win.minX, y: win.maxY),
                                   end: CGPoint(x: win.minX, y: win.maxY - reach), options: [])
            ctx.drawLinearGradient(g, start: CGPoint(x: win.minX, y: win.minY),
                                   end: CGPoint(x: win.minX, y: win.minY + reach), options: [])
        }
        ctx.restoreGState()
    }

    /// The aperture is a slot onto a cylinder, not a flat panel: above and
    /// below the lit slice the drum curves away out of sight. Without these
    /// bands the surface reads as a rectangle of grey behind a frame.
    static func drawLetterbox(_ ctx: CGContext, in win: CGRect,
                              finish: CounterFinish = .modern,
                              cutout: (CGFloat, CGFloat)? = nil,
                              digitHeight: CGFloat = 0) {
        // Sized from the numerals, not from the aperture: the opening has to
        // clear the digits with margin whatever the proportions are.
        let want = win.height * (finish == .retro ? 0.235 : 0.17)
        let clearance = digitHeight * (finish == .retro ? 1.34 : 1.22)
        let band = digitHeight > 0
            ? max(0, min(want, (win.height - clearance) / 2))
            : want
        ctx.saveGState()
        clipAperture(ctx, win)
        if finish == .retro {
            // One piece of mask with a single cutout, rather than four fills
            // meeting at seams — those joins were showing as lines across the
            // white. The cutout stops where the drums stop.
            let lo = cutout.map { max(win.minX, $0.0) } ?? win.minX
            let hi = cutout.map { min(win.maxX, $0.1) } ?? win.maxX
            let slot = CGRect(x: lo, y: win.minY + band,
                              width: max(0, hi - lo), height: win.height - band * 2)

            let mask = CGMutablePath()
            mask.addRect(win)
            mask.addRect(slot)
            ctx.addPath(mask)
            ctx.setFillColor(CounterStyle.retroMask)
            ctx.fillPath(using: .evenOdd)

            // The cut edge sits above the drums, so it shades them just inside
            // the opening — all four sides, and only within the opening.
            ctx.saveGState()
            ctx.clip(to: slot)
            if let g = grad([(0.0, black(0.36)), (1.0, black(0.0))]) {
                let d = win.height * 0.05
                ctx.drawLinearGradient(g, start: CGPoint(x: slot.minX, y: slot.maxY),
                                       end: CGPoint(x: slot.minX, y: slot.maxY - d), options: [])
                ctx.drawLinearGradient(g, start: CGPoint(x: slot.minX, y: slot.minY),
                                       end: CGPoint(x: slot.minX, y: slot.minY + d), options: [])
                ctx.drawLinearGradient(g, start: CGPoint(x: slot.minX, y: slot.minY),
                                       end: CGPoint(x: slot.minX + d * 0.7, y: slot.minY), options: [])
                ctx.drawLinearGradient(g, start: CGPoint(x: slot.maxX, y: slot.minY),
                                       end: CGPoint(x: slot.maxX - d * 0.7, y: slot.minY), options: [])
            }
            ctx.restoreGState()
            ctx.restoreGState()
            return
        }

        // Not quite black — a cylinder turning away still catches a little.
        let deep = CGColor(red: 0.030, green: 0.026, blue: 0.020, alpha: 1.0)
        let fade = CGColor(red: 0.030, green: 0.026, blue: 0.020, alpha: 0.0)
        if let g = grad([(0.0, deep), (0.62, deep), (1.0, fade)]) {
            ctx.drawLinearGradient(g, start: CGPoint(x: win.minX, y: win.maxY),
                                   end: CGPoint(x: win.minX, y: win.maxY - band), options: [])
            ctx.drawLinearGradient(g, start: CGPoint(x: win.minX, y: win.minY),
                                   end: CGPoint(x: win.minX, y: win.minY + band), options: [])
        }
        ctx.restoreGState()
    }

    /// Form shading for a pale drum. The cylinder is nearest the viewer through
    /// the middle and turns away above and below, so it darkens towards the
    /// slot edges — the opposite of the lit-from-the-edges dark drum. Applied
    /// over the numerals too, since they are printed on the surface.
    static func drawRetroShading(_ ctx: CGContext, in win: CGRect) {
        ctx.saveGState()
        clipAperture(ctx, win)

        // The lamps sit behind the mask and spill onto the drums at the slot
        // edges — strongly along the top, a little along the bottom — so the
        // surface is dimmest through the middle. Multiplied, because the
        // numerals are printed on that surface and share its light.
        ctx.setBlendMode(.multiply)
        if let g = grad([(0.0, black(0.0)), (0.20, black(0.05)), (0.50, black(0.24)),
                         (0.80, black(0.11)), (1.0, black(0.03))]) {
            ctx.drawLinearGradient(g, start: CGPoint(x: win.minX, y: win.maxY),
                                   end: CGPoint(x: win.minX, y: win.minY), options: [])
        }

        // Warm spill where the light actually enters.
        ctx.setBlendMode(.plusLighter)
        let warm = { (v: CGFloat) in CGColor(red: 0.60, green: 0.44, blue: 0.16, alpha: v) }
        if let g = grad([(0.0, warm(0.13)), (1.0, warm(0.0))]) {
            ctx.drawLinearGradient(g, start: CGPoint(x: win.minX, y: win.maxY),
                                   end: CGPoint(x: win.minX, y: win.maxY - win.height * 0.42),
                                   options: [])
            ctx.drawLinearGradient(g, start: CGPoint(x: win.minX, y: win.minY),
                                   end: CGPoint(x: win.minX, y: win.minY + win.height * 0.22),
                                   options: [])
        }
        ctx.restoreGState()
    }

    /// Glass over the opening. A soft sheen across the upper half, brightest
    /// towards one corner so it reads as a reflection and not a gradient.
    static func drawGloss(_ ctx: CGContext, in win: CGRect) {
        ctx.saveGState()
        clipAperture(ctx, win)
        ctx.setBlendMode(.plusLighter)
        if let g = grad([(0.0, white(0.085)), (0.45, white(0.020)), (1.0, white(0.0))]) {
            ctx.drawRadialGradient(g,
                                   startCenter: CGPoint(x: win.minX + win.width * 0.22,
                                                        y: win.maxY + win.height * 0.30),
                                   startRadius: 0,
                                   endCenter: CGPoint(x: win.minX + win.width * 0.30,
                                                      y: win.maxY),
                                   endRadius: win.width * 0.62, options: [])
        }
        ctx.restoreGState()
    }

    /// The opening is cut through the bezel, so its edges cast inward.
    static func drawInnerShadow(_ ctx: CGContext, in win: CGRect) {
        let d = win.height * 0.075
        ctx.saveGState()
        clipAperture(ctx, win)
        if let g = grad([(0, black(0.62)), (1, black(0.0))]) {
            ctx.drawLinearGradient(g, start: CGPoint(x: win.minX, y: win.maxY),
                                   end: CGPoint(x: win.minX, y: win.maxY - d), options: [])
            ctx.drawLinearGradient(g, start: CGPoint(x: win.minX, y: win.minY),
                                   end: CGPoint(x: win.minX, y: win.minY + d * 0.6), options: [])
            ctx.drawLinearGradient(g, start: CGPoint(x: win.minX, y: win.minY),
                                   end: CGPoint(x: win.minX + d * 0.55, y: win.minY), options: [])
            ctx.drawLinearGradient(g, start: CGPoint(x: win.maxX, y: win.minY),
                                   end: CGPoint(x: win.maxX - d * 0.55, y: win.minY), options: [])
        }
        ctx.restoreGState()
    }

    /// A lit LED standing proud of the panel: contact shadow, a dark collar,
    /// a lens with a hot off-centre core, and a specular off the dome.
    static func drawLED(_ ctx: CGContext, at c: CGPoint, radius r: CGFloat,
                        red: CGFloat, green: CGFloat, blue: CGFloat) {
        // Sits above the surface, so it casts down onto the panel.
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -r * 0.34),
                      blur: r * 0.7, color: black(0.85))
        ctx.setFillColor(grey(0.09))
        ctx.fillEllipse(in: CGRect(x: c.x - r * 1.22, y: c.y - r * 1.22,
                                   width: r * 2.44, height: r * 2.44))
        ctx.restoreGState()

        // Spill onto the surrounding panel.
        ctx.saveGState()
        ctx.setBlendMode(.plusLighter)
        if let halo = grad([(0.0, CGColor(red: red, green: green, blue: blue, alpha: 0.26)),
                            (0.40, CGColor(red: red, green: green, blue: blue, alpha: 0.07)),
                            (1.0, CGColor(red: red, green: green, blue: blue, alpha: 0.0))]) {
            ctx.drawRadialGradient(halo, startCenter: c, startRadius: r * 0.9,
                                   endCenter: c, endRadius: r * 3.0, options: [])
        }
        ctx.restoreGState()

        // Chromed collar around the lens.
        ctx.setStrokeColor(grey(0.46))
        ctx.setLineWidth(max(0.7, r * 0.10))
        ctx.strokeEllipse(in: CGRect(x: c.x - r * 1.12, y: c.y - r * 1.12,
                                     width: r * 2.24, height: r * 2.24))

        // The lens: hot near the centre, deepening towards the rim.
        ctx.saveGState()
        ctx.addEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
        ctx.clip()
        if let body = grad([(0.0, CGColor(red: min(1, red * 1.5 + 0.42),
                                          green: min(1, green * 1.3 + 0.40),
                                          blue: min(1, blue * 1.3 + 0.36), alpha: 1)),
                            (0.45, CGColor(red: min(1, red * 1.12), green: green, blue: blue, alpha: 1)),
                            (1.0, CGColor(red: red * 0.50, green: green * 0.26,
                                          blue: blue * 0.26, alpha: 1))]) {
            ctx.drawRadialGradient(body,
                                   startCenter: CGPoint(x: c.x - r * 0.18, y: c.y + r * 0.22),
                                   startRadius: 0, endCenter: c, endRadius: r, options: [])
        }
        if let spec = grad([(0, white(0.85)), (1, white(0.0))]) {
            let sc = CGPoint(x: c.x - r * 0.32, y: c.y + r * 0.40)
            ctx.drawRadialGradient(spec, startCenter: sc, startRadius: 0,
                                   endCenter: sc, endRadius: r * 0.44, options: [])
        }
        ctx.restoreGState()
    }

    /// Cut into the metal rather than printed on it: the groove reads dark,
    /// with its far wall catching the light from above-left.
    static func drawEtchedLabel(_ ctx: CGContext, _ text: String,
                                centeredAt c: CGPoint, size: CGFloat) {
        let font = NSFont(name: "Helvetica", size: size) ?? .systemFont(ofSize: size)
        let kern = size * 0.20
        // Engraved and ink-filled, which is how a legend on black anodising is
        // actually made. A bare groove is darker than the surface and vanishes
        // against it; the ink is what carries the reading, with a shadow above
        // and a lit lower wall giving it the recess.
        let passes: [(CGSize, NSColor)] = [
            (CGSize(width: -size * 0.045, height: size * 0.045),
             NSColor(white: 0.0, alpha: 0.75)),            // shadowed near wall
            (CGSize(width: size * 0.05, height: -size * 0.05),
             NSColor(white: 0.72, alpha: 0.35)),           // lit far wall
            (.zero, NSColor(white: 0.80, alpha: 0.96)),    // the ink fill
        ]
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        for (off, col) in passes {
            let a = NSAttributedString(string: text, attributes: [
                .font: font, .foregroundColor: col, .kern: kern,
            ])
            let sz = a.size()
            a.draw(at: NSPoint(x: c.x - (sz.width - kern) / 2 + off.width,
                               y: c.y - sz.height / 2 + off.height))
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    /// Left-justified caption, one line per element, as panel legends are set.
    static func drawLegend(_ ctx: CGContext, _ lines: [String],
                           leftAt p: CGPoint, size: CGFloat, etched: Bool = false) {
        let font = NSFont(name: "Helvetica", size: size) ?? .systemFont(ofSize: size)
        let kern = size * 0.16
        let lead = size * 1.32
        let top = p.y + lead * CGFloat(lines.count - 1) / 2
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        for (i, line) in lines.enumerated() {
            if etched {
                for (dx, dy, w, a) in [(-size * 0.045, size * 0.045, CGFloat(0.0), CGFloat(0.75)),
                                       (size * 0.05, -size * 0.05, CGFloat(0.72), CGFloat(0.35))] {
                    let cut = NSAttributedString(string: line, attributes: [
                        .font: font,
                        .foregroundColor: NSColor(white: w, alpha: a),
                        .kern: kern,
                    ])
                    cut.draw(at: NSPoint(x: p.x + dx,
                                         y: top - lead * CGFloat(i) - cut.size().height / 2 + dy))
                }
            }
            let a = NSAttributedString(string: line, attributes: [
                .font: font,
                .foregroundColor: etched ? NSColor(white: 0.80, alpha: 0.96)
                                         : (NSColor(cgColor: CounterStyle.label) ?? .white),
                .kern: kern,
            ])
            a.draw(at: NSPoint(x: p.x, y: top - lead * CGFloat(i) - a.size().height / 2))
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    /// Rendered width of a label, so callers can space things against the real
    /// text rather than guessing from an unrelated dimension.
    static func labelWidth(_ text: String, size: CGFloat) -> CGFloat {
        let font = NSFont(name: "Helvetica", size: size) ?? .systemFont(ofSize: size)
        let kern = size * 0.20
        let s = NSAttributedString(string: text, attributes: [.font: font, .kern: kern])
        return s.size().width - kern      // drop the trailing kern
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
        s.draw(at: NSPoint(x: c.x - (sz.width - kern) / 2, y: c.y - sz.height / 2))
        NSGraphicsContext.restoreGraphicsState()
    }
}

func easeInOutCubic(_ p: Double) -> Double {
    return p < 0.5 ? 4 * p * p * p : 1 - pow(-2 * p + 2, 3) / 2
}
