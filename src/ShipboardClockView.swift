//
//  ShipboardClockView.swift
//  TOS Shipboard Clock screensaver
//
//  The clock module from the M-5 panel, taken out of the panel and stood on
//  its own: the same black anodised insert, the same three drum windows —
//  HRS . MIN, . SEC and the meridiem — scaled up to fill the screen instead of
//  sitting in the top corner of a bar field.
//
//  Classic finish only, as the module reads on the original prop: dark ink on
//  pale wheels behind a white mask, lit by a warm lamp above each opening.
//
//  What is new here is the mode indicator. On the sunk module a 24-hour reading
//  simply removes the meridiem window and narrows the plate, which works when
//  the module is a small fitting on a larger panel. Standing alone the plate is
//  the whole object, so the window stays: the drum parks on a dash, and a pair
//  of lamps in the band below — 12 HR and 24 HR, exactly one of them lit — says
//  which format the clock is in. The instrument does not change shape; it tells
//  you the meridiem drum is out of use, which is what a real panel would do.
//
//  A single lamp could not do that job. Under a two-state legend it would have
//  to make dark mean both "24-hour" and "burnt out". A dark lamp beside a lit
//  one means neither, which is why the pair exists and why the legend lives on
//  its own row rather than in the caption line.
//

import ScreenSaver
import Cocoa

@objc(ShipboardClockView)
public class ShipboardClockView: ScreenSaverView, ClockOptionsHost {

    // Three drums, as on the panel module: hours and minutes together, seconds
    // on their own, then the meridiem.
    private let hoursMins = CounterWindow()
    private let seconds = CounterWindow()
    private let meridiem = CounterWindow()
    private var lastTime: TimeInterval = 0
    private var drift: Double = 0

    /// The original prop, so the original mechanism. There is no remastered
    /// counterpart to this saver: the module is already shipped both ways as
    /// part of the M-5 panel.
    private let readoutFinish: CounterFinish = .retro

    // MARK: Proportions
    //
    // Every one of these is the sunk module's own fraction, unchanged. The
    // plate is the only thing that grows — this is the same object, larger,
    // not a redrawn one.

    /// Plate height over width.
    private static let plateAspect: CGFloat = 0.185

    /// How much of the screen the plate takes. The second term guards a wide,
    /// short display, where a plate sized off the width alone would run out of
    /// vertical room for its own frame shadow.
    private static let plateWidthFraction: CGFloat = 0.72
    private static let plateHeightLimit: CGFloat = 2.6

    /// Aperture proportion: wide rather than square, as on the prop.
    private static let windowAspect: CGFloat = 2.9

    /// Rows, as fractions of plate height: labels and lamps at 0.155 from the
    /// top, apertures spanning 0.30 to 0.70.
    private static let winHeightFraction: CGFloat = 0.40
    private static let winBottomFromTop: CGFloat = 0.70
    private static let lampRowFromTop: CGFloat = 0.155
    private static let lampRadiusFraction: CGFloat = 0.036
    private static let labelSizeFraction: CGFloat = 0.068

    private static let driftAmp: CGFloat = 0.016

    /// The caption lamps, which are simply on: they belong to the windows, not
    /// to the setting. Only the annunciator below answers to the time format.
    private static let lampRed = (r: CGFloat(0.95), g: CGFloat(0.13), b: CGFloat(0.08))

    /// The meridiem caption. Named for the unit, as `HRS`, `MIN` and `SEC` are
    /// — `AM/PM` would have been the one caption on the panel repeating what
    /// its own window already says in inch-high letters.
    ///
    /// It is also the one caption with no lamp of its own: its column states
    /// that underneath instead, and a lamp here as well would say it twice.
    private static let meridiemCaption = "MERIDIEM"

    /// The annunciator: its legends, its row, and how big the legends are set.
    /// Smaller than the captions, being subordinate to them.
    private static let modeLegends = ["12 HR", "24 HR"]
    private static let modeRowFromBottom: CGFloat = 0.125
    private static let modeSizeFraction: CGFloat = 0.055

    // MARK: Options

    public override var hasConfigureSheet: Bool { return true }

    public override var configureSheet: NSWindow? {
        return ClockOptions.shared.sheet(for: self)
    }

    /// What the sheet says the choice does here. This panel keeps the window
    /// either way, which is worth saying because the other clock savers do not.
    var optionsNote: String { return "24-hour parks the meridiem drum on a dash." }

    @objc private func preferencesChanged(_ n: Notification) {
        ShipboardClock.reloadPreferences()
        optionsChanged()
    }

    deinit {
        DistributedNotificationCenter.default().removeObserver(self)
    }

    /// Drops the cached chrome so the next frame rebuilds it: the meridiem lamp
    /// is part of the chrome, and whether it is lit follows the setting.
    func optionsChanged() {
        chromeKey = ""
        setReadings(animated: false)
        setNeedsDisplay(bounds)
    }

    // MARK: Setup

    public override init?(frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview)
        animationTimeInterval = 1.0 / 60.0
        wantsLayer = true
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(preferencesChanged(_:)),
            name: ShipboardClock.changedNotification, object: nil)
        let face = DigitFacePreference.best()
        for w in [hoursMins, seconds, meridiem] {
            w.face = face
            w.finish = readoutFinish
        }
        // AM and PM are one reading, not two characters that roll separately.
        meridiem.splitsBetweenCharacters = false
        setReadings(animated: false)
    }

    required init?(coder: NSCoder) { super.init(coder: coder) }

    public override var isOpaque: Bool { return true }

    private func setReadings(animated: Bool = true) {
        let stamp = Date()
        hoursMins.set(ShipboardClock.hoursMinutes(stamp), animated: animated)
        seconds.set(ShipboardClock.seconds(stamp), animated: animated)
        meridiem.set(ShipboardClock.meridiemMark(stamp), animated: animated)
    }

    // MARK: Lifecycle guard

    /// The framework does not reliably tear a saver's view down when the screen
    /// saver is dismissed: the instance survives and `animateOneFrame` keeps
    /// being called. Track it and become inert once stopped or detached.
    private var stopped = false

    public override func startAnimation() {
        stopped = false
        // Re-read rather than trust what this process cached: the setting may
        // have been changed from the configure sheet in another process since
        // this view was built.
        ShipboardClock.reloadPreferences()
        optionsChanged()
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
        setReadings()
        for w in [hoursMins, seconds, meridiem] { w.advance(dt) }

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
        var modeY: CGFloat
        var modeSize: CGFloat
    }

    /// Module geometry with the wander left out, so it stays stable for a given
    /// size and the chrome it describes can be cached.
    ///
    /// Whole points throughout for anything that sizes a cached image: a blit
    /// whose destination differs from its source by a fraction of a point
    /// resamples the whole image instead of copying it.
    private func layout(for size: CGSize) -> Layout {
        let pw = min(size.width * ShipboardClockView.plateWidthFraction,
                     size.height * ShipboardClockView.plateHeightLimit)
        let p = CGRect(x: 0, y: 0, width: pw.rounded(),
                       height: (pw * ShipboardClockView.plateAspect).rounded())

        let winH = p.height * ShipboardClockView.winHeightFraction
        let winY = p.maxY - p.height * ShipboardClockView.winBottomFromTop
        let bezelW = CounterChrome.bezelSideWidth(
            forAperture: CGRect(x: 0, y: 0, width: 1, height: winH))
        let gap = bezelW * 2 + winH * 0.16

        // Three windows, always. Every one the same size and a chosen
        // proportion — dividing up whatever space is left over instead gives
        // the apertures an arbitrary shape.
        let eachW = winH * ShipboardClockView.windowAspect
        let groupW = eachW * 3 + gap * 2

        var wins: [CGRect] = []
        var x = p.midX - groupW / 2
        for _ in 0 ..< 3 {
            wins.append(CGRect(x: x.rounded(), y: winY.rounded(),
                               width: eachW.rounded(), height: winH.rounded()))
            x += eachW + gap
        }

        return Layout(plate: p, windows: wins, winH: winH,
                      lampR: p.height * ShipboardClockView.lampRadiusFraction,
                      lampY: p.maxY - p.height * ShipboardClockView.lampRowFromTop,
                      labelSize: p.height * ShipboardClockView.labelSizeFraction,
                      modeY: p.minY + p.height * ShipboardClockView.modeRowFromBottom,
                      modeSize: p.height * ShipboardClockView.modeSizeFraction)
    }

    /// One digit pitch and one glyph height across all three, so the widths
    /// follow real content rather than character count and the drums look like
    /// one instrument.
    ///
    /// Measured against every reading the module can carry, not the one on
    /// screen: M is the widest character here, so sizing off the current
    /// reading would grow the digits the moment the meridiem drum went to a
    /// dash — the wheels changing size because the clock changed format.
    private func applyMetrics(_ l: Layout) {
        let stamp = Date()
        let texts = [ShipboardClock.hoursMinutes(stamp), ShipboardClock.seconds(stamp),
                     ShipboardClock.meridiemMark(stamp)]
        let windows = [hoursMins, seconds, meridiem]
        let widestUnits = texts.reduce(CGFloat(0)) { max($0, CounterWindow.units(for: $1)) }
        let pitch = max(1, (l.windows[0].width
                            - 2 * l.winH * CounterWindow.padFraction) / max(1, widestUnits))

        // Every character the drums can show: the digits, the separator, and
        // both meridiem readings whichever one is up.
        var widestRatio: CGFloat = 0
        for w in windows {
            w.fixedPitch = pitch
            widestRatio = max(widestRatio, w.widestGlyphRatio(in: "0123456789:AMP"))
        }
        let digitH = widestRatio > 0
            ? min(l.winH * 0.60, pitch * CounterWindow.glyphFit / widestRatio)
            : l.winH * 0.60
        for w in windows { w.fixedDigitHeight = digitH }
    }

    // MARK: Cached chrome
    //
    // Plate, lamps, captions and aperture frames never change for a given
    // screen size — and the burn-in wander is a translation of the whole
    // module, not a redraw. So the chrome is rendered once in plate-local
    // coordinates and blitted at the drifted origin.

    private var chromeKey = ""
    private var chromePad: CGFloat = 0
    private var chromeSize: CGSize = .zero
    private var panelImage: CGImage?
    private var aboveImages: [CGImage?] = []

    private func buildChrome(_ l: Layout, scale: CGFloat) {
        let pad = (l.plate.height * 0.22).rounded()
        chromePad = pad
        let size = CGSize(width: (l.plate.width + pad * 2).rounded(),
                          height: (l.plate.height + pad * 2).rounded())
        chromeSize = size
        let windows = [hoursMins, seconds, meridiem]

        panelImage = CounterChrome.renderScaled(size, scale: scale) { c in
            c.translateBy(x: pad, y: pad)
            // No centre screws: on a module this shallow they land on the SEC
            // lamp above and the aperture frames below.
            CounterChrome.drawUnitPlate(c, l.plate, screwInset: l.plate.width * 0.045,
                                        centreScrews: false)
            for (i, win) in l.windows.enumerated() { windows[i].drawBelow(c, in: win) }
            self.drawCaptions(c, l)
        }

        // drawAbove reads the drum extent a reading establishes, so let one
        // digit pass run — discarded into a scratch context — before the front
        // tier is cached.
        _ = CounterChrome.renderScaled(CGSize(width: 1, height: 1), scale: 1) { c in
            for (i, win) in l.windows.enumerated() { windows[i].drawDigits(c, in: win) }
        }

        // The front tier is confined to the aperture, so it caches at aperture
        // size rather than over the whole module.
        aboveImages = l.windows.enumerated().map { i, win in
            CounterChrome.renderScaled(win.size, scale: scale) { c in
                c.translateBy(x: -win.minX, y: -win.minY)
                windows[i].drawAbove(c, in: win)
            }
        }
    }

    /// The lamp row. The prop puts the lamps inline with the captions rather
    /// than one over each window: HRS . MIN either side of the first, and a
    /// lamp ahead of SEC. The meridiem gets the same treatment as SEC — a lamp
    /// and its caption, centred over the window as a pair.
    ///
    /// Labels are spaced against the measured text; a multiple of the lamp
    /// radius has nothing to do with how wide a word actually is.
    private func drawCaptions(_ c: CGContext, _ l: Layout) {
        let clear = l.lampR * 1.15
        let red = ShipboardClockView.lampRed

        func lampAndLabel(_ text: String, over win: CGRect, lit: Bool) {
            let w = CounterChrome.labelWidth(text, size: l.labelSize)
            let group = l.lampR * 2 + clear + w
            let lampX = win.midX - group / 2 + l.lampR
            CounterChrome.drawLED(c, at: CGPoint(x: lampX, y: l.lampY), radius: l.lampR,
                                  red: red.r, green: red.g, blue: red.b, lit: lit)
            CounterChrome.drawEtchedLabel(c, text,
                centeredAt: CGPoint(x: lampX + l.lampR + clear + w / 2, y: l.lampY),
                size: l.labelSize)
        }

        let hrsW = CounterChrome.labelWidth("HRS", size: l.labelSize)
        let minW = CounterChrome.labelWidth("MIN", size: l.labelSize)
        let mid = l.windows[0].midX
        CounterChrome.drawLED(c, at: CGPoint(x: mid, y: l.lampY), radius: l.lampR,
                              red: red.r, green: red.g, blue: red.b)
        CounterChrome.drawEtchedLabel(c, "HRS",
            centeredAt: CGPoint(x: mid - l.lampR - clear - hrsW / 2, y: l.lampY),
            size: l.labelSize)
        CounterChrome.drawEtchedLabel(c, "MIN",
            centeredAt: CGPoint(x: mid + l.lampR + clear + minW / 2, y: l.lampY),
            size: l.labelSize)

        lampAndLabel("SEC", over: l.windows[1], lit: true)

        // The meridiem caption stands on its own, centred over its window: the
        // annunciator below is what says whether that drum is in use, and a
        // lamp up here as well would state it twice.
        CounterChrome.drawEtchedLabel(c, ShipboardClockView.meridiemCaption,
            centeredAt: CGPoint(x: l.windows[2].midX, y: l.lampY),
            size: l.labelSize)

        drawAnnunciator(c, l)
    }

    /// The 12 HR / 24 HR annunciator, in the band under the readouts. Exactly
    /// one lamp is lit, always — which is the whole point of a pair. A dark
    /// lamp next to a lit one reads as *not this one*; a dark lamp on its own
    /// reads as a fault.
    ///
    /// Spaced against the measured legends, and the two pairs stand a lamp
    /// diameter and a half apart so they group as one fitting rather than two.
    private func drawAnnunciator(_ c: CGContext, _ l: Layout) {
        let red = ShipboardClockView.lampRed
        let clear = l.lampR * 1.15
        let legends = ShipboardClockView.modeLegends
        let widths = legends.map { CounterChrome.labelWidth($0, size: l.modeSize) }
        let pairs = widths.map { l.lampR * 2 + clear + $0 }
        let between = l.lampR * 6
        let total = pairs.reduce(0, +) + between

        // Centred in the meridiem column rather than on the plate. On the
        // centreline it read as belonging to the SEC window above it, which is
        // the one readout it has nothing to do with; here the caption, the drum
        // and the lamps stack into one fitting.
        var x = l.windows[2].midX - total / 2
        for (i, legend) in legends.enumerated() {
            let lit = (i == 1) == ShipboardClock.use24Hour
            CounterChrome.drawLED(c, at: CGPoint(x: x + l.lampR, y: l.modeY),
                                  radius: l.lampR,
                                  red: red.r, green: red.g, blue: red.b, lit: lit)
            CounterChrome.drawEtchedLabel(c, legend,
                centeredAt: CGPoint(x: x + l.lampR * 2 + clear + widths[i] / 2, y: l.modeY),
                size: l.modeSize)
            x += pairs[i] + between
        }
    }

    // MARK: Drawing

    public override func draw(_ rect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        Hardware.drawCachedScreen(ctx, in: bounds)

        let l = layout(for: bounds.size)
        applyMetrics(l)

        let scale = CounterChrome.pixelScale(ctx)
        // The meridiem lamp is chrome, and whether it is lit follows the time
        // format, so the format belongs in the key.
        let key = "\(Int(bounds.width))x\(Int(bounds.height))@\(scale)"
            + "-\(ShipboardClock.use24Hour)"
        if key != chromeKey || panelImage == nil {
            buildChrome(l, scale: scale)
            chromeKey = key
        }

        // Slow wander, so a panel left up for hours is not a burn-in risk. Two
        // incommensurate periods, so it never repeats exactly. Rounded to whole
        // points: the module is a cached image, and blitting it on a fraction
        // resamples every pixel of it every frame.
        let amp = min(bounds.width, bounds.height) * ShipboardClockView.driftAmp
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
        let windows = [hoursMins, seconds, meridiem]
        for (i, win) in l.windows.enumerated() { windows[i].drawDigits(ctx, in: win) }
        for (i, win) in l.windows.enumerated() {
            if i < aboveImages.count, let a = aboveImages[i] { ctx.draw(a, in: win) }
        }
        ctx.restoreGState()
    }
}
