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

    /// How far the module wanders, as a fraction of the smaller screen
    /// dimension. Small, because it is already close to an edge.
    private static let driftAmp: CGFloat = 0.010

    public override init?(frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview)
        let face = DigitFacePreference.best()
        for w in [hoursMins, seconds, meridiem] { w.face = face }
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
        let w = min(bounds.width * 0.275, bounds.height * 0.54)
        let h = w * 0.44
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
        CounterChrome.drawScreen(ctx, in: bounds)
    }

    public override func draw(_ rect: NSRect) {
        super.draw(rect)                 // screen and bars

        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        let amp = min(bounds.width, bounds.height) * M5ClockView.driftAmp
        let d = CGSize(width: CGFloat(sin(clockDrift / 89.0 * 2 * .pi)) * amp,
                       height: CGFloat(sin(clockDrift / 113.0 * 2 * .pi)) * amp * 0.7)
        let p = plate(offsetBy: d)

        // Cover glass over the display, punched through where the module sits:
        // the module is a physical unit in a cut-out, not something on screen.
        ctx.saveGState()
        ctx.addRect(bounds)
        ctx.addRect(p.insetBy(dx: -3, dy: -3))
        ctx.clip(using: .evenOdd)
        Hardware.drawCoverGlass(ctx, over: bounds)
        ctx.restoreGState()

        CounterChrome.drawUnitPlate(ctx, p, screwInset: p.width * 0.045)

        // Vertical stack, as fractions of plate height from the top:
        // labels and lamps 0.10-0.22, apertures 0.30-0.70.
        let winH = p.height * 0.40
        let winY = p.maxY - p.height * 0.70
        let content = p.width * 0.88
        let bezelW = CounterChrome.bezelWidth(forAperture: CGRect(x: 0, y: 0, width: 1, height: winH))
        let gap = bezelW * 2 + winH * 0.16

        let stamp = Date()
        let texts = [ShipboardClock.hoursMinutes(stamp),
                     ShipboardClock.seconds(stamp),
                     ShipboardClock.meridiem(stamp)].filter { !$0.isEmpty }
        let windows = [hoursMins, seconds, meridiem]

        // One digit pitch across all three, so the widths follow real content
        // rather than character count and the drums look like one instrument.
        // The switch shares the readout row rather than taking a second one.
        let togS = winH * 0.72
        let togSlot = togS + gap

        let totalUnits = texts.reduce(CGFloat(0)) { $0 + CounterWindow.units(for: $1) }
        let totalPad = CGFloat(texts.count) * 2 * winH * CounterWindow.padFraction
        let gaps = gap * CGFloat(texts.count - 1)
        let pitch = max(1, (content - togSlot - gaps - totalPad) / max(1, totalUnits))

        let lampR = p.height * 0.043
        let lampY = p.maxY - p.height * 0.155
        let labelSize = p.height * 0.082

        var x = p.midX - content / 2
        for (i, text) in texts.enumerated() {
            let w = CounterWindow.apertureWidth(for: text, pitch: pitch, height: winH)
            let r = CGRect(x: x, y: winY, width: w, height: winH)
            windows[i].draw(ctx, in: r)

            // The prop puts the lamps inline with the captions rather than one
            // over each window: HRS . MIN either side of the first, and a lamp
            // ahead of SEC. The meridiem has no equivalent, so it gets none.
            // Space labels against the measured text; multiples of the lamp
            // radius have nothing to do with how wide a word actually is.
            let clear = lampR * 1.15
            switch i {
            case 0:
                let hrsW = CounterChrome.labelWidth("HRS", size: labelSize)
                let minW = CounterChrome.labelWidth("MIN", size: labelSize)
                CounterChrome.drawLED(ctx, at: CGPoint(x: r.midX, y: lampY), radius: lampR,
                                      red: 0.95, green: 0.13, blue: 0.08)
                CounterChrome.drawLabel(ctx, "HRS",
                                        centeredAt: CGPoint(x: r.midX - lampR - clear - hrsW / 2, y: lampY),
                                        size: labelSize)
                CounterChrome.drawLabel(ctx, "MIN",
                                        centeredAt: CGPoint(x: r.midX + lampR + clear + minW / 2, y: lampY),
                                        size: labelSize)
            case 1:
                let secW = CounterChrome.labelWidth("SEC", size: labelSize)
                let groupW = lampR * 2 + clear + secW
                let lampX = r.midX - groupW / 2 + lampR
                CounterChrome.drawLED(ctx, at: CGPoint(x: lampX, y: lampY),
                                      radius: lampR, red: 0.95, green: 0.13, blue: 0.08)
                CounterChrome.drawLabel(ctx, "SEC",
                                        centeredAt: CGPoint(x: lampX + lampR + clear + secW / 2, y: lampY),
                                        size: labelSize)
            default:
                break
            }
            x += w + gap
        }

        // Light switch alongside the readouts, captioned on the panel as on
        // the prop. A static fitting, like the screws — not a control.
        let togX = p.midX + content / 2 - togS / 2
        Hardware.drawToggle(ctx, at: CGPoint(x: togX, y: winY + winH / 2), scale: togS)
        CounterChrome.drawLabel(ctx, "LIGHT",
                                centeredAt: CGPoint(x: togX, y: p.minY + p.height * 0.175),
                                size: p.height * 0.062)
    }
}
