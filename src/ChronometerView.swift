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

/// Stardate is not canon, so this is an explicit convention: it starts at
/// `epochValue` on `epochDate` and advances `perDay` per day, which puts the
/// present in the 3000s — the range TOS actually used. Change these three
/// constants to re-base it.
enum Stardate {
    static let epochValue: Double = 1000.0

    /// A thousand units to the year, the rate the later series settled on.
    /// Expressed as the division rather than the quotient so the convention is
    /// legible: 2.7379 on its own says nothing.
    ///
    /// This moves the displayed tenth every ~53 minutes. It is a readout, not
    /// a second hand — a rate fast enough to watch would mean inventing one,
    /// and there is no scheme to invent it from. TOS stardates were arbitrary
    /// by design.
    static let perDay: Double = 1000.0 / 365.25
    static let epochDate: Date = {
        var c = DateComponents()
        c.year = 2020; c.month = 1; c.day = 1
        c.timeZone = TimeZone(secondsFromGMT: 0)
        return Calendar(identifier: .gregorian).date(from: c) ?? Date(timeIntervalSince1970: 1577836800)
    }()

    /// Four significant digits and one decimal, as the prop shows.
    static func string(_ date: Date) -> String {
        let days = date.timeIntervalSince(epochDate) / 86400.0
        return String(format: "%.1f", epochValue + days * perDay)
    }
}

/// The shipboard clock. The prop runs 24-hour; set `use24Hour` to false for a
/// 12-hour reading, which then needs the AM/PM window beside it.
enum ShipboardClock {
    /// Persisted per saver. `ScreenSaverDefaults` is keyed by bundle
    /// identifier, and each variant ships as its own bundle, so the setting
    /// belongs to whichever saver you actually run.
    static var defaults: ScreenSaverDefaults? {
        let id = Bundle(for: ChronometerView.self).bundleIdentifier ?? "com.kencosci.m5"
        return ScreenSaverDefaults(forModuleWithName: id)
    }

    private static var cached24: Bool?

    /// Posted when the setting changes. The configure sheet and the running
    /// saver are different processes, so a preview that has already read the
    /// value would otherwise keep showing the old one until it was restarted.
    static let changedNotification = Notification.Name("local.ken.screensaver.clockOptionsChanged")

    /// Drops the cached value so the next read comes from disk.
    static func reloadPreferences() {
        cached24 = nil
        defaults?.synchronize()
    }

    static var use24Hour: Bool {
        get {
            if let c = cached24 { return c }
            let v = defaults?.bool(forKey: "use24Hour") ?? false
            cached24 = v
            return v
        }
        set {
            cached24 = newValue
            defaults?.set(newValue, forKey: "use24Hour")
            defaults?.synchronize()
            DistributedNotificationCenter.default().postNotificationName(
                changedNotification, object: nil, userInfo: nil, deliverImmediately: true)
        }
    }

    static func string(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.hour, .minute, .second], from: date)
        let h = c.hour ?? 0
        if use24Hour {
            return String(format: "%02d:%02d:%02d", h, c.minute ?? 0, c.second ?? 0)
        }
        let h12 = h % 12 == 0 ? 12 : h % 12
        return String(format: "%02d:%02d:%02d", h12, c.minute ?? 0, c.second ?? 0)
    }

    /// Hours and minutes, which share a drum on the split layout.
    static func hoursMinutes(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        let h = c.hour ?? 0
        let shown = use24Hour ? h : (h % 12 == 0 ? 12 : h % 12)
        return String(format: "%02d:%02d", shown, c.minute ?? 0)
    }

    /// Hours and minutes, always 24-hour. The chronometer panels read ship's
    /// time the way the prop does, with no meridiem window to fall back on, so
    /// they must not go through the 12-hour preference.
    static func hoursMinutes24(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }

    /// Seconds, on their own drum.
    static func seconds(_ date: Date) -> String {
        return String(format: "%02d", Calendar.current.component(.second, from: date))
    }

    /// Always 24-hour, regardless of `use24Hour`. The chronometer panel shows
    /// ship's time the way the prop does, with no meridiem window.
    static func string24(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.hour, .minute, .second], from: date)
        return String(format: "%02d:%02d:%02d", c.hour ?? 0, c.minute ?? 0, c.second ?? 0)
    }

    /// Empty on a 24-hour reading, so the caller can skip the extra window.
    static func meridiem(_ date: Date) -> String {
        guard !use24Hour else { return "" }
        return (Calendar.current.component(.hour, from: date) < 12) ? "AM" : "PM"
    }

    /// The same reading for a panel that keeps its meridiem window on a
    /// 24-hour clock. The drum has nowhere to go, so it parks on a dash — the
    /// position a real counter wheel would carry for "not in use" — instead of
    /// the window being taken out of the plate.
    static let meridiemDash = "\u{2013}"

    static func meridiemMark(_ date: Date) -> String {
        let m = meridiem(date)
        return m.isEmpty ? meridiemDash : m
    }
}

@objc(ChronometerView)
public class ChronometerView: ScreenSaverView {

    private let stardate = CounterWindow()
    private let shipboard = CounterWindow()
    private var lastTime: TimeInterval = 0
    private var drift: Double = 0

    /// Which prop era the readouts are built as. Overridden rather than
    /// configured, so both eras ship as separate screensavers.
    var readoutFinish: CounterFinish { return .modern }

    /// The light switch is part of the mechanical panel. An emissive readout
    /// has no lamp to switch, so only the Classic carries the fitting.
    var showsLightSwitch: Bool { return readoutFinish == .retro }

    /// Aperture proportion. Wider than the clock module's, because these
    /// windows carry eight characters and the panel is far bigger on screen.
    /// Wide enough that an eight-character reading stops well clear of the
    /// frame. At 4.0 the outermost wheels ran right up to the bezel.
    private static let windowAspect: CGFloat = 4.5
    private static let driftAmp: CGFloat = 0.016

    public override init?(frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview)
        animationTimeInterval = 1.0 / 60.0
        wantsLayer = true
        let face = DigitFacePreference.best()
        for w in [stardate, shipboard] {
            w.face = face
            w.finish = readoutFinish
        }
        let now = Date()
        stardate.set(Stardate.string(now), animated: false)
        shipboard.set(ShipboardClock.string24(now), animated: false)
    }

    required init?(coder: NSCoder) { super.init(coder: coder) }

    public override var isOpaque: Bool { return true }
    public override var hasConfigureSheet: Bool { return false }
    public override var configureSheet: NSWindow? { return nil }

    // MARK: Lifecycle guard

    /// Apple's framework does not reliably tear a saver's view down when the
    /// screen saver is dismissed: the instance survives and `animateOneFrame`
    /// keeps being called, burning CPU indefinitely. Track it ourselves and
    /// become inert once stopped or detached.
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
        stardate.set(Stardate.string(stamp))
        shipboard.set(ShipboardClock.string24(stamp))
        stardate.advance(dt)
        shipboard.advance(dt)

        setNeedsDisplay(bounds)
    }

    // MARK: Cached chrome
    //
    // The panel is fixed for a given screen size: plate, lamps, aperture
    // frames, captions and switch never change. Only the readings do — and
    // the burn-in wander is a translation of the whole panel, not a redraw.
    // So the chrome is rendered once in panel-local coordinates and blitted
    // at the drifted origin.

    // Which tier costs what. Guessing has been wrong every time it mattered
    // here, so the decomposition is measurable rather than assumed.
    private static let profiling = ProcessInfo.processInfo.environment["M5_PROFILE"] != nil
    private var phase = [Double](repeating: 0, count: 4)
    private var phaseFrames = 0

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
    }

    /// Panel geometry with the wander left out, so it stays stable for a given
    /// size and the chrome it describes can be cached.
    private func layout(for size: CGSize) -> Layout {
        // Size the apertures from the space actually available, then let the
        // plate follow. Deriving the windows from the plate instead made the
        // pair plus its gap 1.125x the plate width, so they hung off both ends.
        let plateW = min(size.width * 0.76, size.height * 2.3)
        let unit = CGRect(x: 0, y: 0, width: 1, height: 1)
        let gapPerHeight = CounterChrome.bezelSideWidth(forAperture: unit) * 2 + 0.30
        let winH = (plateW * 0.88) / (2 * ChronometerView.windowAspect + gapPerHeight)
        let plateH = winH / 0.27
        let p = CGRect(x: 0, y: 0, width: plateW.rounded(), height: plateH.rounded())

        let winY = p.maxY - p.height * 0.60
        let eachW = winH * ChronometerView.windowAspect
        let sideW = CounterChrome.bezelSideWidth(
            forAperture: CGRect(x: 0, y: 0, width: 1, height: winH))
        let gap = sideW * 2 + winH * 0.30

        // Whole points throughout. These rects size the cached chrome images,
        // and a blit whose destination differs from the source by a fraction
        // of a pixel resamples the whole image instead of copying it — which
        // cost 19 ms a frame on the panel alone.
        var wins: [CGRect] = []
        var x = p.midX - (eachW * 2 + gap) / 2
        for _ in 0 ..< 2 {
            wins.append(CGRect(x: x.rounded(), y: winY.rounded(),
                               width: eachW.rounded(), height: winH.rounded()))
            x += eachW + gap
        }
        return Layout(plate: p, windows: wins, winH: winH,
                      lampR: p.height * 0.036,
                      lampY: p.maxY - p.height * 0.155,
                      labelSize: p.height * 0.072)
    }

    /// One pitch and one glyph height across both readouts, so they read as
    /// one instrument rather than two separately-scaled boxes.
    private func applyMetrics(_ l: Layout) {
        let texts = [Stardate.string(Date()), ShipboardClock.string24(Date())]
        let widestUnits = texts.reduce(CGFloat(0)) { max($0, CounterWindow.units(for: $1)) }
        let pitch = max(1, (l.windows[0].width
                            - 2 * l.winH * CounterWindow.padFraction) / widestUnits)
        var widestRatio: CGFloat = 0
        for w in [stardate, shipboard] {
            w.fixedPitch = pitch
            widestRatio = max(widestRatio, w.widestGlyphRatio())
        }
        let digitH = widestRatio > 0
            ? min(l.winH * 0.60, pitch * CounterWindow.glyphFit / widestRatio)
            : l.winH * 0.60
        for w in [stardate, shipboard] { w.fixedDigitHeight = digitH }
    }

    /// Everything behind the readings, in panel-local coordinates.
    private func buildChrome(_ l: Layout, scale: CGFloat) {
        let pad = (l.plate.height * 0.12).rounded()
        chromePad = pad
        let size = CGSize(width: (l.plate.width + pad * 2).rounded(),
                          height: (l.plate.height + pad * 2).rounded())
        chromeSize = size
        let windows = [stardate, shipboard]
        let captions = ["STARDATE", "SHIPBOARD"]

        panelImage = CounterChrome.renderScaled(size, scale: scale) { c in
            c.translateBy(x: pad, y: pad)

            // No centre screws: the switch and its legend occupy that column.
            CounterChrome.drawUnitPlate(c, l.plate, screwInset: l.plate.width * 0.035,
                                        centreScrews: false)

            for (i, win) in l.windows.enumerated() {
                // The prop's indicator lamps read orange-red; the clock-only
                // saver uses a true red.
                CounterChrome.drawLED(c, at: CGPoint(x: win.midX, y: l.lampY),
                                      radius: l.lampR,
                                      red: 0.94, green: 0.28, blue: 0.06)
                windows[i].drawBelow(c, in: win)
                // Clear of the bezel's lower edge, not just of the aperture —
                // the frame stands proud below the opening.
                let capY = win.minY - CounterChrome.bezelWidth(
                    forAperture: CGRect(x: 0, y: 0, width: 1, height: l.winH))
                    - l.labelSize * 0.85
                CounterChrome.drawEtchedLabel(c, captions[i],
                                              centeredAt: CGPoint(x: win.midX, y: capY),
                                              size: l.labelSize)
            }

            // Light switch on the bottom row, as on the prop, centred between
            // the two captions. A static fitting, like the screws.
            if self.showsLightSwitch {
                let togS = l.plate.height * 0.112
                let capSize = l.plate.height * 0.038
                let capClear = togS * 0.45
                let togX = l.plate.midX
                // Clear of the lit bottom edge of the recess, which reaches
                // about 0.033 of the plate height up from the base.
                let rowY = l.plate.minY + l.plate.height * 0.185
                Hardware.drawToggle(c, at: CGPoint(x: togX, y: rowY), scale: togS)
                CounterChrome.drawLegend(c, ["LIGHT", "SWITCH"],
                                         leftAt: CGPoint(x: togX + togS / 2 + capClear,
                                                         y: rowY),
                                         size: capSize, etched: true)
            }
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

    // MARK: Drawing

    public override func draw(_ rect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        let tStart = CFAbsoluteTimeGetCurrent()
        Hardware.drawCachedScreen(ctx, in: bounds)

        let l = layout(for: bounds.size)
        applyMetrics(l)

        let scale = CounterChrome.pixelScale(ctx)
        let key = "\(Int(bounds.width))x\(Int(bounds.height))@\(scale)-\(showsLightSwitch)"
        if key != chromeKey || panelImage == nil {
            buildChrome(l, scale: scale)
            chromeKey = key
        }

        // Slow wander, so a panel left up for hours is not a burn-in risk.
        // Two incommensurate periods, so it never repeats exactly. Rounded to
        // whole points: the panel is a cached image, and blitting it on a
        // fraction resamples every pixel of it every frame.
        let amp = min(bounds.width, bounds.height) * ChronometerView.driftAmp
        let dx = (CGFloat(sin(drift / 97.0 * 2 * .pi)) * amp).rounded()
        let dy = (CGFloat(sin(drift / 131.0 * 2 * .pi)) * amp * 0.6).rounded()
        let ox = (bounds.midX - l.plate.width / 2).rounded() + dx
        let oy = (bounds.midY - l.plate.height / 2).rounded() + dy

        let tPanel = CFAbsoluteTimeGetCurrent()
        if let img = panelImage {
            ctx.draw(img, in: CGRect(x: ox - chromePad, y: oy - chromePad,
                                     width: chromeSize.width, height: chromeSize.height))
        }

        let tDigits = CFAbsoluteTimeGetCurrent()
        ctx.saveGState()
        ctx.translateBy(x: ox, y: oy)
        let windows = [stardate, shipboard]
        for (i, win) in l.windows.enumerated() { windows[i].drawDigits(ctx, in: win) }
        let tAbove = CFAbsoluteTimeGetCurrent()
        for (i, win) in l.windows.enumerated() {
            if i < aboveImages.count, let a = aboveImages[i] { ctx.draw(a, in: win) }
        }
        ctx.restoreGState()

        if ChronometerView.profiling {
            let end = CFAbsoluteTimeGetCurrent()
            phase[0] += tPanel - tStart
            phase[1] += tDigits - tPanel
            phase[2] += tAbove - tDigits
            phase[3] += end - tAbove
            phaseFrames += 1
            if phaseFrames == 100 {
                let n = Double(phaseFrames)
                FileHandle.standardError.write(String(
                    format: "backdrop %.2f  panel %.2f  digits %.2f  above %.2f  (ms/frame)\n",
                    phase[0] / n * 1000, phase[1] / n * 1000,
                    phase[2] / n * 1000, phase[3] / n * 1000).data(using: .utf8)!)
                phase = [0, 0, 0, 0]; phaseFrames = 0
            }
        }
    }
}
