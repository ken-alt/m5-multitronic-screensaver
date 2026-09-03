//
//  HelmChronometerView.swift
//  TOS Helm Chronometer screensaver
//
//  The clock on the helm console, as the prop actually reads rather than as the
//  stardate panel does: no stardate at all. Hours and minutes share one drum window, the
//  seconds have their own, HRS . MIN and . SEC are lamped and etched above
//  them, and the bottom row carries the two TIME RESET dials under the first
//  window, the light switch between the two, and the clock switch outboard of
//  the seconds.
//
//  Same mechanism as the other chronometers — `CounterWindow` drums, chrome
//  cached in panel-local coordinates and blitted at the drifted origin. Only
//  the panel furniture is new.
//
//  Proportions are taken off the reference frame, expressed as fractions of
//  the plate so they hold at any screen size. Anything that must clear
//  something else is derived from it rather than written twice.
//

import ScreenSaver
import Cocoa

@objc(HelmChronometerView)
public class HelmChronometerView: ScreenSaverView {

    private let hoursMins = CounterWindow()
    private let seconds = CounterWindow()
    private var lastTime: TimeInterval = 0
    private var drift: Double = 0

    /// The original prop, so the original mechanism: dark ink on pale wheels
    /// behind a white mask. There is no remastered counterpart — this layout
    /// is what the physical panel looked like.
    private let readoutFinish: CounterFinish = .retro

    // MARK: Proportions
    //
    // Fractions of the plate, measured off the reference frame. The plate
    // itself is the one absolute: everything else follows from it.

    /// Panel width over height on the reference frame.
    private static let plateAspect: CGFloat = 2.31

    /// Aperture height and shape, and the gap between the two windows.
    private static let winHeightFraction: CGFloat = 0.20
    private static let windowAspect: CGFloat = 4.0
    private static let windowGapFraction: CGFloat = 0.95   // of aperture height

    /// Rows, from the top of the plate down.
    private static let labelRowFromTop: CGFloat = 0.214
    private static let windowMidFromTop: CGFloat = 0.514
    /// The switch and dial row, from the bottom. The toggles are the tallest
    /// things on it, so this is set by what clears the window frames above.
    private static let bottomRowFromBottom: CGFloat = 0.235

    private static let lampRadiusFraction: CGFloat = 0.045
    private static let labelSizeFraction: CGFloat = 0.088

    /// Reset dials, sized and placed against the first aperture: they sit
    /// under the hours and the minutes, not at arbitrary points on the plate.
    private static let dialRadiusFraction: CGFloat = 0.059
    private static let dialUnderHours: CGFloat = 0.11      // of aperture width
    private static let dialUnderMinutes: CGFloat = 0.44

    /// The dial markings, innermost outwards: arrow, then legend. The legend
    /// radius is what sets how close two dials can stand, so the dial spacing
    /// above was chosen against it.
    private static let arrowRadiusFraction: CGFloat = 0.082
    private static let arrowThicknessFraction: CGFloat = 0.013
    private static let arrowSweep: CGFloat = 172 * .pi / 180
    private static let legendRadiusFraction: CGFloat = 0.125
    private static let legendSizeFraction: CGFloat = 0.032
    private static let legendMaxSweep: CGFloat = 180 * .pi / 180

    private static let toggleWidthFraction: CGFloat = 0.095
    private static let switchCapSizeFraction: CGFloat = 0.036

    /// Screws: how far the corner columns come in from the edge, and how far
    /// the pair flanking the light switch stands off the centreline. Fractions
    /// of plate width, so the rows stay square on a wide plate.
    private static let screwInsetFraction: CGFloat = 0.035
    private static let screwFlankFraction: CGFloat = 0.082

    private static let driftAmp: CGFloat = 0.016

    /// The dial legends. Set here rather than inline so the pair can be read,
    /// and measured, together — `arcLabelSize` sizes both to whichever is
    /// longer so they cannot end up at different sizes.
    private static let dialLegends = ["TIME RESET HOUR", "TIME RESET MIN.-10 MIN."]

    // MARK: Setup

    public override init?(frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview)
        animationTimeInterval = 1.0 / 60.0
        wantsLayer = true
        let face = DigitFacePreference.best()
        for w in [hoursMins, seconds] {
            w.face = face
            w.finish = readoutFinish
        }
        let now = Date()
        hoursMins.set(ShipboardClock.hoursMinutes24(now), animated: false)
        seconds.set(ShipboardClock.seconds(now), animated: false)
    }

    required init?(coder: NSCoder) { super.init(coder: coder) }

    public override var isOpaque: Bool { return true }
    public override var hasConfigureSheet: Bool { return false }
    public override var configureSheet: NSWindow? { return nil }

    // MARK: Lifecycle guard

    /// The framework does not reliably tear a saver's view down when the screen
    /// saver is dismissed: the instance survives and `animateOneFrame` keeps
    /// being called. Track it and become inert once stopped or detached.
    private var stopped = false

    public override func startAnimation() {
        stopped = false
        super.startAnimation()
    }

    public override func stopAnimation() {
        stopped = true
        super.stopAnimation()
    }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { stopped = true }
    }

    var isRunning: Bool { return !stopped }

    // MARK: Animation

    public override func animateOneFrame() {
        guard isRunning else { return }
        let now = Date.timeIntervalSinceReferenceDate
        var dt = lastTime > 0 ? now - lastTime : 1.0 / 60.0
        lastTime = now
        if dt > 0.25 { dt = 0.25 }

        drift += dt
        let stamp = Date()
        hoursMins.set(ShipboardClock.hoursMinutes24(stamp))
        seconds.set(ShipboardClock.seconds(stamp))
        hoursMins.advance(dt)
        seconds.advance(dt)

        setNeedsDisplay(bounds)
    }

    // MARK: Layout

    private struct Layout {
        var plate: CGRect
        var windows: [CGRect]
        var winH: CGFloat
        var lampR: CGFloat
        var lampY: CGFloat
        var labelSize: CGFloat
        var rowY: CGFloat
        var dials: [CGPoint]
        var dialR: CGFloat
        var arrowR: CGFloat
        var arrowT: CGFloat
        var legendR: CGFloat
        var legendSize: CGFloat
        var togS: CGFloat
        var lightX: CGFloat
        var clockX: CGFloat
        var capSize: CGFloat
        var capClear: CGFloat
    }

    /// Panel geometry with the wander left out, so it stays stable for a given
    /// size and the chrome it describes can be cached.
    ///
    /// Whole points throughout for anything that sizes a cached image: a blit
    /// whose destination differs from its source by a fraction of a point
    /// resamples the whole image instead of copying it.
    private func layout(for size: CGSize) -> Layout {
        let plateW = min(size.width * 0.80, size.height * 2.05)
        let plateH = plateW / HelmChronometerView.plateAspect
        let p = CGRect(x: 0, y: 0, width: plateW.rounded(), height: plateH.rounded())

        let winH = (p.height * HelmChronometerView.winHeightFraction).rounded()
        let eachW = (winH * HelmChronometerView.windowAspect).rounded()
        let gap = (winH * HelmChronometerView.windowGapFraction).rounded()
        let winY = (p.maxY - p.height * HelmChronometerView.windowMidFromTop
                    - winH / 2).rounded()

        var wins: [CGRect] = []
        var x = (p.midX - (eachW * 2 + gap) / 2).rounded()
        for _ in 0 ..< 2 {
            wins.append(CGRect(x: x, y: winY, width: eachW, height: winH))
            x += eachW + gap
        }

        let rowY = p.minY + p.height * HelmChronometerView.bottomRowFromBottom

        // The dials belong to the first aperture, so they are placed across it
        // rather than across the plate.
        let dialY = rowY
        let dials = [HelmChronometerView.dialUnderHours,
                     HelmChronometerView.dialUnderMinutes].map {
            CGPoint(x: wins[0].minX + wins[0].width * $0, y: dialY)
        }

        // The switch legends set as two lines, as on the prop, so the widest
        // word is what the clock switch has to be inset by to stay on the plate.
        let capSize = p.height * HelmChronometerView.switchCapSizeFraction
        let capW = max(CounterChrome.labelWidth("CLOCK", size: capSize),
                       CounterChrome.labelWidth("SWITCH", size: capSize))
        let togS = p.height * HelmChronometerView.toggleWidthFraction
        let capClear = togS * 0.42
        let screwInset = p.width * HelmChronometerView.screwInsetFraction

        return Layout(
            plate: p, windows: wins, winH: winH,
            lampR: p.height * HelmChronometerView.lampRadiusFraction,
            lampY: p.maxY - p.height * HelmChronometerView.labelRowFromTop,
            labelSize: p.height * HelmChronometerView.labelSizeFraction,
            rowY: rowY,
            dials: dials,
            dialR: p.height * HelmChronometerView.dialRadiusFraction,
            arrowR: p.height * HelmChronometerView.arrowRadiusFraction,
            arrowT: p.height * HelmChronometerView.arrowThicknessFraction,
            legendR: p.height * HelmChronometerView.legendRadiusFraction,
            legendSize: p.height * HelmChronometerView.legendSizeFraction,
            togS: togS,
            lightX: p.midX,
            // Right-aligned as a group: the toggle plus its legend ends level
            // with the screw column, so the legend cannot run off the plate.
            clockX: p.maxX - screwInset - capW - capClear - togS / 2,
            capSize: capSize, capClear: capClear)
    }

    /// One pitch and one glyph height across both readouts, so they read as one
    /// instrument. The seconds carry two characters against the hours' five, so
    /// its reading simply centres in an aperture the same size — which is what
    /// the prop does.
    private func applyMetrics(_ l: Layout) {
        let now = Date()
        let texts = [ShipboardClock.hoursMinutes24(now), ShipboardClock.seconds(now)]
        let widestUnits = texts.reduce(CGFloat(0)) { max($0, CounterWindow.units(for: $1)) }
        let pitch = max(1, (l.windows[0].width
                            - 2 * l.winH * CounterWindow.padFraction) / widestUnits)
        var widestRatio: CGFloat = 0
        for w in [hoursMins, seconds] {
            w.fixedPitch = pitch
            widestRatio = max(widestRatio, w.widestGlyphRatio())
        }
        let digitH = widestRatio > 0
            ? min(l.winH * 0.60, pitch * CounterWindow.glyphFit / widestRatio)
            : l.winH * 0.60
        for w in [hoursMins, seconds] { w.fixedDigitHeight = digitH }
    }

    // MARK: Cached chrome
    //
    // Plate, lamps, captions, aperture frames, dials and switches never change
    // for a given screen size — and the burn-in wander is a translation of the
    // whole panel, not a redraw. So the chrome is rendered once in panel-local
    // coordinates and blitted at the drifted origin.

    private var chromeKey = ""
    private var chromePad: CGFloat = 0
    private var chromeSize: CGSize = .zero
    private var panelImage: CGImage?
    private var aboveImages: [CGImage?] = []

    private func buildChrome(_ l: Layout, scale: CGFloat) {
        let pad = (l.plate.height * 0.12).rounded()
        chromePad = pad
        let size = CGSize(width: (l.plate.width + pad * 2).rounded(),
                          height: (l.plate.height + pad * 2).rounded())
        chromeSize = size
        let windows = [hoursMins, seconds]
        let screwInset = l.plate.width * HelmChronometerView.screwInsetFraction
        let flank = l.plate.width * HelmChronometerView.screwFlankFraction

        panelImage = CounterChrome.renderScaled(size, scale: scale) { c in
            c.translateBy(x: pad, y: pad)

            // No centre screws: the light switch owns that column. The prop
            // instead carries a pair either side of it, drawn here rather than
            // by the plate — but at the plate's own radius and row, so they
            // cannot drift out of step with the corners.
            CounterChrome.drawUnitPlate(c, l.plate, screwInset: screwInset,
                                        centreScrews: false)
            let rad = CounterChrome.screwRadius(in: l.plate)
            let row = CounterChrome.screwRowInset(screwInset)
            for (n, x) in [l.plate.midX - flank, l.plate.midX + flank].enumerated() {
                for (m, y) in [l.plate.minY + row, l.plate.maxY - row].enumerated() {
                    Hardware.drawScrew(c, at: CGPoint(x: x, y: y), radius: rad,
                                       angle: CGFloat(n * 2 + m) * 0.7 + 0.9)
                }
            }

            for (i, win) in l.windows.enumerated() {
                windows[i].drawBelow(c, in: win)
            }

            self.drawCaptions(c, l)
            self.drawResetDials(c, l)
            self.drawSwitches(c, l)
        }

        // drawAbove reads the drum extent a reading establishes, so let one
        // digit pass run — discarded into a scratch context — before the front
        // tier is cached.
        _ = CounterChrome.renderScaled(CGSize(width: 1, height: 1), scale: 1) { c in
            for (i, win) in l.windows.enumerated() { windows[i].drawDigits(c, in: win) }
        }

        // The front tier is confined to the aperture, so it caches at aperture
        // size rather than over the whole panel.
        aboveImages = l.windows.enumerated().map { i, win in
            CounterChrome.renderScaled(win.size, scale: scale) { c in
                c.translateBy(x: -win.minX, y: -win.minY)
                windows[i].drawAbove(c, in: win)
            }
        }
    }

    /// HRS . MIN over the first window and . SEC over the second, as the prop
    /// sets them: the lamps are inline with the captions rather than one over
    /// each window. Spaced against the measured text — a multiple of the lamp
    /// radius has nothing to do with how wide a word actually is.
    private func drawCaptions(_ c: CGContext, _ l: Layout) {
        let clear = l.lampR * 1.15
        let lampRed = (r: CGFloat(0.94), g: CGFloat(0.16), b: CGFloat(0.07))

        let hrsW = CounterChrome.labelWidth("HRS", size: l.labelSize)
        let minW = CounterChrome.labelWidth("MIN", size: l.labelSize)
        let mid0 = l.windows[0].midX
        CounterChrome.drawLED(c, at: CGPoint(x: mid0, y: l.lampY), radius: l.lampR,
                              red: lampRed.r, green: lampRed.g, blue: lampRed.b)
        CounterChrome.drawEtchedLabel(c, "HRS",
            centeredAt: CGPoint(x: mid0 - l.lampR - clear - hrsW / 2, y: l.lampY),
            size: l.labelSize)
        CounterChrome.drawEtchedLabel(c, "MIN",
            centeredAt: CGPoint(x: mid0 + l.lampR + clear + minW / 2, y: l.lampY),
            size: l.labelSize)

        let secW = CounterChrome.labelWidth("SEC", size: l.labelSize)
        let group = l.lampR * 2 + clear + secW
        let lampX = l.windows[1].midX - group / 2 + l.lampR
        CounterChrome.drawLED(c, at: CGPoint(x: lampX, y: l.lampY), radius: l.lampR,
                              red: lampRed.r, green: lampRed.g, blue: lampRed.b)
        CounterChrome.drawEtchedLabel(c, "SEC",
            centeredAt: CGPoint(x: lampX + l.lampR + clear + secW / 2, y: l.lampY),
            size: l.labelSize)
    }

    /// The two TIME RESET dials: knob, the two-headed arc that says it turns
    /// both ways, and the legend curving under both.
    private func drawResetDials(_ c: CGContext, _ l: Layout) {
        // Both legends set at whichever size fits the longer of the two, so a
        // one-word difference in length cannot leave them mismatched.
        let size = CounterChrome.arcLabelSize(
            fitting: HelmChronometerView.dialLegends, radius: l.legendR,
            size: l.legendSize, maxSweep: HelmChronometerView.legendMaxSweep)

        for (i, centre) in l.dials.enumerated() {
            CounterChrome.drawArcArrow(c, centeredOn: centre, radius: l.arrowR,
                                       sweep: HelmChronometerView.arrowSweep,
                                       thickness: l.arrowT)
            CounterChrome.drawArcLabel(c, HelmChronometerView.dialLegends[i],
                                       centeredOn: centre, radius: l.legendR, size: size)
            // Turned differently, so a pair of dials does not read as one dial
            // stamped twice.
            Hardware.drawDial(c, at: centre, radius: l.dialR,
                              angle: i == 0 ? 0.42 : -0.63)
        }
    }

    /// Light switch centred between the two windows and clock switch outboard
    /// of the seconds, each with its legend set to the right in two lines.
    private func drawSwitches(_ c: CGContext, _ l: Layout) {
        for (x, lines) in [(l.lightX, ["LIGHT", "SWITCH"]),
                           (l.clockX, ["CLOCK", "SWITCH"])] {
            Hardware.drawToggle(c, at: CGPoint(x: x, y: l.rowY), scale: l.togS)
            CounterChrome.drawLegend(c, lines,
                                     leftAt: CGPoint(x: x + l.togS / 2 + l.capClear,
                                                     y: l.rowY),
                                     size: l.capSize, etched: true)
        }
    }

    // MARK: Drawing

    public override func draw(_ rect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        Hardware.drawCachedScreen(ctx, in: bounds)

        let l = layout(for: bounds.size)
        applyMetrics(l)

        let scale = CounterChrome.pixelScale(ctx)
        let key = "\(Int(bounds.width))x\(Int(bounds.height))@\(scale)"
        if key != chromeKey || panelImage == nil {
            buildChrome(l, scale: scale)
            chromeKey = key
        }

        // Slow wander, so a panel left up for hours is not a burn-in risk. Two
        // incommensurate periods, so it never repeats exactly. Rounded to whole
        // points: the panel is a cached image, and blitting it on a fraction
        // resamples every pixel of it every frame.
        let amp = min(bounds.width, bounds.height) * HelmChronometerView.driftAmp
        let dx = (CGFloat(sin(drift / 97.0 * 2 * .pi)) * amp).rounded()
        let dy = (CGFloat(sin(drift / 131.0 * 2 * .pi)) * amp * 0.6).rounded()
        let ox = (bounds.midX - l.plate.width / 2).rounded() + dx
        let oy = (bounds.midY - l.plate.height / 2).rounded() + dy

        if let img = panelImage {
            ctx.draw(img, in: CGRect(x: ox - chromePad, y: oy - chromePad,
                                     width: chromeSize.width, height: chromeSize.height))
        }

        ctx.saveGState()
        ctx.translateBy(x: ox, y: oy)
        let windows = [hoursMins, seconds]
        for (i, win) in l.windows.enumerated() { windows[i].drawDigits(ctx, in: win) }
        for (i, win) in l.windows.enumerated() {
            if i < aboveImages.count, let a = aboveImages[i] { ctx.draw(a, in: win) }
        }
        ctx.restoreGState()
    }
}
