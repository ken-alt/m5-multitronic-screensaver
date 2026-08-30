//
//  M5ClockView.swift
//  M-5 Panel with Clock screensaver
//
//  The M-5 readout field with the chronometer's shipboard clock along the top.
//  Subclasses the panel rather than duplicating it, and reserves the strip the
//  clock occupies so bars leave room instead of running underneath.
//

import ScreenSaver
import Cocoa

@objc(M5ClockView)
public class M5ClockView: M5PanelView {

    private let shipboard = CounterWindow()
    private var clockTime: TimeInterval = 0
    private var clockDrift: Double = 0

    /// How far the clock wanders, as a fraction of the smaller screen
    /// dimension. Small, because it is already close to an edge.
    private static let driftAmp: CGFloat = 0.012

    public override init?(frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview)
        shipboard.set(ShipboardClock.string(Date()), animated: false)
    }

    required init?(coder: NSCoder) { super.init(coder: coder) }

    // MARK: Layout

    /// The clock furniture for a given drift offset. Everything is derived from
    /// `bounds`, so this is safe to call before the subclass is fully set up.
    private func layout(offsetBy d: CGSize) -> (window: CGRect, lamp: CGPoint, lampR: CGFloat) {
        let winW = min(bounds.width * 0.22, bounds.height * 0.44)
        let winH = winW / 3.33                      // the prop's window aspect
        let lampR = winH * 0.17
        let topGap = bounds.height * 0.055

        let lampY = bounds.maxY - topGap - lampR + d.height
        let winTop = lampY - lampR - winH * 0.34
        let window = CGRect(x: bounds.midX - winW / 2 + d.width,
                            y: winTop - winH, width: winW, height: winH)
        return (window, CGPoint(x: window.midX, y: lampY), lampR)
    }

    /// The full extent the clock can ever occupy, so bars keep clear of it
    /// wherever the drift happens to put it.
    override var reservedRegion: CGRect {
        let l = layout(offsetBy: .zero)
        let amp = min(bounds.width, bounds.height) * M5ClockView.driftAmp
        let bezel = l.window.height * 0.16
        let region = l.window
            .union(CGRect(x: l.lamp.x - l.lampR * 1.3, y: l.lamp.y - l.lampR * 1.3,
                          width: l.lampR * 2.6, height: l.lampR * 2.6))
        return region.insetBy(dx: -(amp + bezel + l.window.height * 0.35),
                              dy: -(amp + bezel + l.window.height * 0.35))
    }

    // MARK: Animation

    public override func animateOneFrame() {
        super.animateOneFrame()          // advances the bar field

        let now = Date.timeIntervalSinceReferenceDate
        var dt = clockTime > 0 ? now - clockTime : 1.0 / 60.0
        clockTime = now
        if dt > 0.25 { dt = 0.25 }

        clockDrift += dt
        shipboard.set(ShipboardClock.string(Date()))
        shipboard.advance(dt)
    }

    // MARK: Drawing

    public override func draw(_ rect: NSRect) {
        super.draw(rect)                 // background and bars

        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        let amp = min(bounds.width, bounds.height) * M5ClockView.driftAmp
        let d = CGSize(width: CGFloat(sin(clockDrift / 89.0 * 2 * .pi)) * amp,
                       height: CGFloat(sin(clockDrift / 113.0 * 2 * .pi)) * amp * 0.7)
        let l = layout(offsetBy: d)

        CounterChrome.drawLED(ctx, at: l.lamp, radius: l.lampR,
                              red: 0.93, green: 0.10, blue: 0.07)
        shipboard.draw(ctx, in: l.window)
    }
}
