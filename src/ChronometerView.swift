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

    public override init?(frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview)
        animationTimeInterval = 1.0 / 60.0
        wantsLayer = true
        let face = DigitFacePreference.best()
        stardate.face = face
        shipboard.face = face
        let now = Date()
        stardate.set(Stardate.string(now), animated: false)
        shipboard.set(ShipboardClock.string(now), animated: false)
    }

    required init?(coder: NSCoder) { super.init(coder: coder) }

    public override var isOpaque: Bool { return true }
    public override var hasConfigureSheet: Bool { return false }
    public override var configureSheet: NSWindow? { return nil }

    public override func animateOneFrame() {
        let now = Date.timeIntervalSinceReferenceDate
        var dt = lastTime > 0 ? now - lastTime : 1.0 / 60.0
        lastTime = now
        if dt > 0.25 { dt = 0.25 }

        drift += dt
        let date = Date()
        stardate.set(Stardate.string(date))
        shipboard.set(ShipboardClock.string(date))
        stardate.advance(dt)
        shipboard.advance(dt)

        setNeedsDisplay(bounds)
    }

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
        // The prop's indicator lamps read orange-red, so these keep that
        // colour; the clock-only saver uses a true red.
        CounterChrome.drawLED(ctx, at: CGPoint(x: left.midX,  y: lampY), radius: lampR,
                              red: 0.94, green: 0.28, blue: 0.06)
        CounterChrome.drawLED(ctx, at: CGPoint(x: right.midX, y: lampY), radius: lampR,
                              red: 0.94, green: 0.28, blue: 0.06)

        stardate.draw(ctx, in: left)
        shipboard.draw(ctx, in: right)

        let labelY = panel.maxY - panelH * 0.80
        let labelSize = panelH * 0.105
        CounterChrome.drawLabel(ctx, "STARDATE",  centeredAt: CGPoint(x: left.midX,  y: labelY), size: labelSize)
        CounterChrome.drawLabel(ctx, "SHIPBOARD", centeredAt: CGPoint(x: right.midX, y: labelY), size: labelSize)
    }

    private func drawPanel(_ ctx: CGContext, _ panel: CGRect) {
        ctx.setFillColor(CGColor(red: 0.055, green: 0.047, blue: 0.043, alpha: 1))
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
}
