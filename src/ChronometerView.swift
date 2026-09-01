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
    static let perDay: Double = 1.0
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
    static let use24Hour = false

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

    // MARK: Drawing

    public override func draw(_ rect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        Hardware.drawCachedScreen(ctx, in: bounds)

        // Slow wander, so a panel left up for hours is not a burn-in risk.
        // Two incommensurate periods, so it never repeats exactly.
        let amp = min(bounds.width, bounds.height) * ChronometerView.driftAmp
        let dx = CGFloat(sin(drift / 97.0 * 2 * .pi)) * amp
        let dy = CGFloat(sin(drift / 131.0 * 2 * .pi)) * amp * 0.6

        // Size the apertures from the space actually available, then let the
        // plate follow. Deriving the windows from the plate instead made the
        // pair plus its gap 1.125x the plate width, so they hung off both ends.
        let plateW = min(bounds.width * 0.76, bounds.height * 2.3)
        let unit = CGRect(x: 0, y: 0, width: 1, height: 1)
        let gapPerHeight = CounterChrome.bezelSideWidth(forAperture: unit) * 2 + 0.30
        let winHeight = (plateW * 0.88) / (2 * ChronometerView.windowAspect + gapPerHeight)
        let plateH = winHeight / 0.27
        let p = CGRect(x: bounds.midX - plateW / 2 + dx,
                       y: bounds.midY - plateH / 2 + dy,
                       width: plateW, height: plateH)

        CounterChrome.drawUnitPlate(ctx, p, screwInset: p.width * 0.035)

        let winH = winHeight
        let winY = p.maxY - p.height * 0.60
        let eachW = winH * ChronometerView.windowAspect
        let sideW = CounterChrome.bezelSideWidth(
            forAperture: CGRect(x: 0, y: 0, width: 1, height: winH))
        let gap = sideW * 2 + winH * 0.30

        let texts = [Stardate.string(Date()), ShipboardClock.string24(Date())]
        let windows = [stardate, shipboard]
        let captions = ["STARDATE", "SHIPBOARD"]

        // One pitch and one glyph height across both, so the readouts match.
        let widestUnits = texts.reduce(CGFloat(0)) { max($0, CounterWindow.units(for: $1)) }
        let pitch = max(1, (eachW - 2 * winH * CounterWindow.padFraction) / widestUnits)
        var widestRatio: CGFloat = 0
        for w in windows {
            w.fixedPitch = pitch
            widestRatio = max(widestRatio, w.widestGlyphRatio())
        }
        let digitH = widestRatio > 0
            ? min(winH * 0.60, pitch * CounterWindow.glyphFit / widestRatio)
            : winH * 0.60
        for w in windows { w.fixedDigitHeight = digitH }

        let lampR = p.height * 0.036
        let lampY = p.maxY - p.height * 0.155
        let labelSize = p.height * 0.072

        let groupW = eachW * 2 + gap
        var x = p.midX - groupW / 2
        for (i, w) in windows.enumerated() {
            let r = CGRect(x: x, y: winY, width: eachW, height: winH)
            // The prop's indicator lamps read orange-red; the clock-only saver
            // uses a true red.
            CounterChrome.drawLED(ctx, at: CGPoint(x: r.midX, y: lampY), radius: lampR,
                                  red: 0.94, green: 0.28, blue: 0.06)
            w.draw(ctx, in: r)
            // Clear of the bezel's lower edge, not just of the aperture — the
            // frame stands proud below the opening.
            let capY = winY - CounterChrome.bezelWidth(
                forAperture: CGRect(x: 0, y: 0, width: 1, height: winH)) - labelSize * 0.85
            CounterChrome.drawEtchedLabel(ctx, captions[i],
                                          centeredAt: CGPoint(x: r.midX, y: capY),
                                          size: labelSize)
            x += eachW + gap
        }

        // Light switch on the bottom row, as on the prop, centred between the
        // two captions. A static fitting, like the screws.
        if showsLightSwitch {
            let togS = p.height * 0.112
            let capSize = p.height * 0.052
            let capW = max(CounterChrome.labelWidth("LIGHT", size: capSize),
                           CounterChrome.labelWidth("SWITCH", size: capSize))
            let capClear = togS * 0.45
            let groupW = togS + capClear + capW
            let togX = p.midX - groupW / 2 + togS / 2
            let rowY = p.minY + p.height * 0.155
            Hardware.drawToggle(ctx, at: CGPoint(x: togX, y: rowY), scale: togS)
            CounterChrome.drawLegend(ctx, ["LIGHT", "SWITCH"],
                                     leftAt: CGPoint(x: togX + togS / 2 + capClear, y: rowY),
                                     size: capSize, etched: true)
        }
    }
}
