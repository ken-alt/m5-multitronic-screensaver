//
//  M5ClockView.swift
//  M-5 Panel with Clock screensaver
//
//  The M-5 readout field on a glass-covered display, with a compact shipboard
//  clock module sunk into the top centre. Subclasses the panel rather than
//  duplicating it, and reserves the module's footprint so bars leave room.
//

import ScreenSaver
import Cocoa

@objc(M5ClockView)
public class M5ClockView: M5PanelView {

    // Three drums, as on the countdown panel: hours and minutes together,
    // seconds on their own, then the meridiem.
    private let hoursMins = CounterWindow()
    private let seconds = CounterWindow()
    private let meridiem = CounterWindow()
    private var clockTime: TimeInterval = 0
    private var clockDrift: Double = 0

    /// Which prop era the readouts are built as. Overridden rather than
    /// configured, so both eras ship as separate screensavers.
    var readoutFinish: CounterFinish { return .modern }

    /// The light switch is part of the mechanical panel. An emissive readout
    /// has no lamp to switch, so the Remaster does without it and the clock
    /// recentres over the plate on its own — the switch slot falls to zero.
    var showsLightSwitch: Bool { return readoutFinish == .retro }

    /// Aperture proportion: wide rather than square, as on the prop.
    private static let windowAspect: CGFloat = 2.9

    /// How far the module wanders, as a fraction of the smaller screen
    /// dimension. Small, because it is already close to an edge.
    private static let driftAmp: CGFloat = 0.010

    public override init?(frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview)
        let face = DigitFacePreference.best()
        for w in [hoursMins, seconds, meridiem] {
            w.face = face
            w.finish = readoutFinish
        }
        let now = Date()
        hoursMins.set(ShipboardClock.hoursMinutes(now), animated: false)
        seconds.set(ShipboardClock.seconds(now), animated: false)
        meridiem.set(ShipboardClock.meridiem(now), animated: false)
    }

    required init?(coder: NSCoder) { super.init(coder: coder) }

    // MARK: Layout

    /// The module plate for a given drift offset. Derived from `bounds` only,
    /// so it is safe to call before the subclass is fully set up.
    private func plate(offsetBy d: CGSize) -> CGRect {
        let w = min(bounds.width * 0.380, bounds.height * 0.76)
        let h = w * 0.185
        return CGRect(x: bounds.midX - w / 2 + d.width,
                      y: bounds.maxY - h - bounds.height * 0.055 + d.height,
                      width: w, height: h)
    }

    /// The whole footprint the module can occupy, so bars keep clear of it
    /// wherever the drift puts it.
    override var reservedRegion: CGRect {
        let p = plate(offsetBy: .zero)
        let amp = min(bounds.width, bounds.height) * M5ClockView.driftAmp
        return p.insetBy(dx: -(amp + p.height * 0.22), dy: -(amp + p.height * 0.22))
    }

    // MARK: Animation

    public override func animateOneFrame() {
        guard isRunning else { return }
        super.animateOneFrame()          // advances the bar field

        let now = Date.timeIntervalSinceReferenceDate
        var dt = clockTime > 0 ? now - clockTime : 1.0 / 60.0
        clockTime = now
        if dt > 0.25 { dt = 0.25 }

        clockDrift += dt
        let stamp = Date()
        hoursMins.set(ShipboardClock.hoursMinutes(stamp))
        seconds.set(ShipboardClock.seconds(stamp))
        meridiem.set(ShipboardClock.meridiem(stamp))
        for w in [hoursMins, seconds, meridiem] { w.advance(dt) }
    }

    // MARK: Drawing

    /// The field sits on gloss glass, like a phone screen.
    public override func drawBackground(_ ctx: CGContext) {
        Hardware.drawCachedScreen(ctx, in: bounds)
    }
    // MARK: Cached chrome
    //
    // The module is fixed for a given screen size: plate, lamps, aperture
    // frames, captions and switch never change. Only the readings do, and the
    // wander is a translation rather than a redraw. So the chrome is rendered
    // once in plate-local coordinates and blitted at the drifted origin, over
    // the live bar field.

    private var chromeKey = ""
    private var chromePad: CGFloat = 0
    private var chromeSize: CGSize = .zero
    private var panelImage: CGImage?
    private var aboveImages: [CGImage?] = []

    private struct Layout {
        var plate: CGRect
        var windows: [CGRect]
        var winH: CGFloat
        var lampR: CGFloat
        var lampY: CGFloat
        var labelSize: CGFloat
        var togS: CGFloat
        var togX: CGFloat
        var rowMidY: CGFloat
        var capSize: CGFloat
        var capClear: CGFloat
        var count: Int
    }

    private func currentTexts() -> [String] {
        let stamp = Date()
        return [ShipboardClock.hoursMinutes(stamp),
                ShipboardClock.seconds(stamp),
                ShipboardClock.meridiem(stamp)].filter { !$0.isEmpty }
    }

    /// Module geometry with the wander left out, so it stays stable for a
    /// given size and the chrome it describes can be cached.
    private func layout(for size: CGSize) -> Layout {
        let pw = min(size.width * 0.380, size.height * 0.76)
        let p = CGRect(x: 0, y: 0, width: pw.rounded(), height: (pw * 0.185).rounded())

        // Vertical stack, as fractions of plate height from the top:
        // labels and lamps 0.10-0.22, apertures 0.30-0.70.
        let winH = p.height * 0.40
        let winY = p.maxY - p.height * 0.70
        let bezelW = CounterChrome.bezelSideWidth(
            forAperture: CGRect(x: 0, y: 0, width: 1, height: winH))
        let gap = bezelW * 2 + winH * 0.16
        let texts = currentTexts()

        // The switch shares the readout row rather than taking a second one,
        // and stands the same height as the readout frames.
        let frameH = winH + 2 * CounterChrome.bezelWidth(
            forAperture: CGRect(x: 0, y: 0, width: 1, height: winH))
        let togS = frameH / Hardware.toggleAspect
        let capSize = winH * 0.185
        let capW = max(CounterChrome.labelWidth("LIGHT", size: capSize),
                       CounterChrome.labelWidth("SWITCH", size: capSize))
        let capClear = togS * 0.42
        let togSlot = showsLightSwitch ? (togS + capClear + capW + gap) : 0

        // Every window the same size and a chosen proportion. Dividing up
        // whatever space is left over gives the apertures an arbitrary shape —
        // that is how they ended up nearly square.
        let eachW = winH * M5ClockView.windowAspect
        let groupW = eachW * CGFloat(texts.count)
                   + gap * CGFloat(texts.count - 1) + togSlot

        // Whole points throughout: these rects size the cached images, and a
        // blit whose destination differs from its source by a fraction of a
        // pixel resamples the image instead of copying it.
        var wins: [CGRect] = []
        var x = p.midX - groupW / 2
        for _ in texts.indices {
            wins.append(CGRect(x: x.rounded(), y: winY.rounded(),
                               width: eachW.rounded(), height: winH.rounded()))
            x += eachW + gap
        }
        return Layout(plate: p, windows: wins, winH: winH,
                      lampR: p.height * 0.036,
                      lampY: p.maxY - p.height * 0.155,
                      labelSize: p.height * 0.068,
                      togS: togS,
                      togX: p.midX + groupW / 2 - togSlot + gap + togS / 2,
                      rowMidY: winY + winH / 2,
                      capSize: capSize, capClear: capClear, count: texts.count)
    }

    /// One digit pitch across all three, so the widths follow real content
    /// rather than character count and the drums look like one instrument.
    private func applyMetrics(_ l: Layout) {
        let texts = currentTexts()
        let windows = [hoursMins, seconds, meridiem]
        let widestUnits = texts.reduce(CGFloat(0)) { max($0, CounterWindow.units(for: $1)) }
        let pitch = max(1, (l.windows[0].width
                            - 2 * l.winH * CounterWindow.padFraction) / max(1, widestUnits))
        // One glyph height for all three: take the widest character anywhere in
        // the reading, so the sections cannot disagree on size.
        var widestRatio: CGFloat = 0
        for i in texts.indices {
            windows[i].fixedPitch = pitch
            widestRatio = max(widestRatio, windows[i].widestGlyphRatio())
        }
        let digitH = widestRatio > 0
            ? min(l.winH * 0.60, pitch * CounterWindow.glyphFit / widestRatio)
            : l.winH * 0.60
        for w in windows { w.fixedDigitHeight = digitH }
        meridiem.splitsBetweenCharacters = false
    }

    private func buildChrome(_ l: Layout, scale: CGFloat) {
        let pad = (l.plate.height * 0.22).rounded()
        chromePad = pad
        let size = CGSize(width: (l.plate.width + pad * 2).rounded(),
                          height: (l.plate.height + pad * 2).rounded())
        chromeSize = size
        let windows = [hoursMins, seconds, meridiem]

        panelImage = CounterChrome.renderScaled(size, scale: scale) { c in
            c.translateBy(x: pad, y: pad)
            CounterChrome.drawUnitPlate(c, l.plate, screwInset: l.plate.width * 0.045)

            for (i, r) in l.windows.enumerated() {
                windows[i].drawBelow(c, in: r)

                // The prop puts the lamps inline with the captions rather than
                // one over each window: HRS . MIN either side of the first, and
                // a lamp ahead of SEC. The meridiem has no equivalent, so it
                // gets none. Space labels against the measured text; multiples
                // of the lamp radius have nothing to do with how wide a word
                // actually is.
                let clear = l.lampR * 1.15
                switch i {
                case 0:
                    let hrsW = CounterChrome.labelWidth("HRS", size: l.labelSize)
                    let minW = CounterChrome.labelWidth("MIN", size: l.labelSize)
                    CounterChrome.drawLED(c, at: CGPoint(x: r.midX, y: l.lampY),
                                          radius: l.lampR,
                                          red: 0.95, green: 0.13, blue: 0.08)
                    CounterChrome.drawEtchedLabel(c, "HRS",
                        centeredAt: CGPoint(x: r.midX - l.lampR - clear - hrsW / 2, y: l.lampY),
                        size: l.labelSize)
                    CounterChrome.drawEtchedLabel(c, "MIN",
                        centeredAt: CGPoint(x: r.midX + l.lampR + clear + minW / 2, y: l.lampY),
                        size: l.labelSize)
                case 1:
                    let secW = CounterChrome.labelWidth("SEC", size: l.labelSize)
                    let g = l.lampR * 2 + clear + secW
                    let lampX = r.midX - g / 2 + l.lampR
                    CounterChrome.drawLED(c, at: CGPoint(x: lampX, y: l.lampY),
                                          radius: l.lampR,
                                          red: 0.95, green: 0.13, blue: 0.08)
                    CounterChrome.drawEtchedLabel(c, "SEC",
                        centeredAt: CGPoint(x: lampX + l.lampR + clear + secW / 2, y: l.lampY),
                        size: l.labelSize)
                default:
                    break
                }
            }

            // Light switch alongside the readouts, legend set to its right in
            // two lines as on the prop. A static fitting, like the screws.
            if self.showsLightSwitch {
                Hardware.drawToggle(c, at: CGPoint(x: l.togX, y: l.rowMidY), scale: l.togS)
                CounterChrome.drawLegend(c, ["LIGHT", "SWITCH"],
                    leftAt: CGPoint(x: l.togX + l.togS / 2 + l.capClear, y: l.rowMidY),
                    size: l.capSize, etched: true)
            }
        }

        // drawAbove reads the drum extent a reading establishes, so let one
        // digit pass run — discarded into a scratch context — before the front
        // tier is cached.
        _ = CounterChrome.renderScaled(CGSize(width: 1, height: 1), scale: 1) { c in
            for (i, r) in l.windows.enumerated() { windows[i].drawDigits(c, in: r) }
        }

        // The front tier is confined to the aperture, so it caches at aperture
        // size rather than over the whole module.
        aboveImages = l.windows.enumerated().map { i, r in
            CounterChrome.renderScaled(r.size, scale: scale) { c in
                c.translateBy(x: -r.minX, y: -r.minY)
                windows[i].drawAbove(c, in: r)
            }
        }
    }

    // MARK: Drawing

    public override func draw(_ rect: NSRect) {
        super.draw(rect)                 // screen and bars

        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        // Cover glass over the display. No cut-out needed: the module is drawn
        // after it and covers its own area, and the even-odd clip forced the
        // glass to be rebuilt live rather than blitted from cache.
        Hardware.drawCachedGlass(ctx, over: bounds)

        let l = layout(for: bounds.size)
        applyMetrics(l)

        let scale = CounterChrome.pixelScale(ctx)
        let key = "\(Int(bounds.width))x\(Int(bounds.height))@\(scale)"
            + "-\(showsLightSwitch)-\(l.count)"
        if key != chromeKey || panelImage == nil {
            buildChrome(l, scale: scale)
            chromeKey = key
        }

        let amp = min(bounds.width, bounds.height) * M5ClockView.driftAmp
        let dx = (CGFloat(sin(clockDrift / 89.0 * 2 * .pi)) * amp).rounded()
        let dy = (CGFloat(sin(clockDrift / 113.0 * 2 * .pi)) * amp * 0.7).rounded()
        let base = plate(offsetBy: .zero)
        let ox = base.minX.rounded() + dx
        let oy = base.minY.rounded() + dy

        if let img = panelImage {
            ctx.draw(img, in: CGRect(x: ox - chromePad, y: oy - chromePad,
                                     width: chromeSize.width, height: chromeSize.height))
        }

        ctx.saveGState()
        ctx.translateBy(x: ox, y: oy)
        let windows = [hoursMins, seconds, meridiem]
        for (i, r) in l.windows.enumerated() {
            windows[i].drawDigits(ctx, in: r)
            if i < aboveImages.count, let a = aboveImages[i] { ctx.draw(a, in: r) }
        }
        ctx.restoreGState()
    }
}
