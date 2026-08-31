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

    /// Aperture proportion: wide rather than square, as on the prop.
    private static let windowAspect: CGFloat = 2.2

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
        let w = min(bounds.width * 0.340, bounds.height * 0.68)
        let h = w * 0.235
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
        // Sized by height: the plate is 2.35x as tall as it is wide.
        let togS = winH * 0.55
        let capSize = winH * 0.185
        let capW = max(CounterChrome.labelWidth("LIGHT", size: capSize),
                       CounterChrome.labelWidth("SWITCH", size: capSize))
        let capClear = togS * 0.42
        let togSlot = togS + capClear + capW + gap

        // Every window the same size and a chosen proportion. Dividing up
        // whatever space is left over gives the apertures an arbitrary shape —
        // that is how they ended up nearly square.
        let eachW = winH * M5ClockView.windowAspect
        let widestUnits = texts.reduce(CGFloat(0)) { max($0, CounterWindow.units(for: $1)) }
        let gaps = gap * CGFloat(texts.count - 1)
        let pitch = max(1, (eachW - 2 * winH * CounterWindow.padFraction) / max(1, widestUnits))

        let lampR = p.height * 0.036
        let lampY = p.maxY - p.height * 0.155
        let labelSize = p.height * 0.068

        // One glyph height for all three: take the widest character anywhere in
        // the reading, so the sections cannot disagree on size.
        var widestRatio: CGFloat = 0
        for (i, _) in texts.enumerated() {
            windows[i].fixedPitch = pitch
            widestRatio = max(widestRatio, windows[i].widestGlyphRatio())
        }
        let digitH = widestRatio > 0
            ? min(winH * 0.60, pitch * CounterWindow.glyphFit / widestRatio)
            : winH * 0.60
        for w in windows { w.fixedDigitHeight = digitH }
        meridiem.splitsBetweenCharacters = false

        let groupW = eachW * CGFloat(texts.count) + gaps + togSlot
        var x = p.midX - groupW / 2
        for (i, text) in texts.enumerated() {
            let r = CGRect(x: x, y: winY, width: eachW, height: winH)
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
            x += eachW + gap
        }

        // Light switch alongside the readouts, legend set to its right in two
        // lines as on the prop. A static fitting, like the screws.
        let togX = p.midX + groupW / 2 - togSlot + gap + togS / 2
        let rowMidY = winY + winH / 2
        Hardware.drawToggle(ctx, at: CGPoint(x: togX, y: rowMidY), scale: togS)
        CounterChrome.drawLegend(ctx, ["LIGHT", "SWITCH"],
                                 leftAt: CGPoint(x: togX + togS / 2 + capClear, y: rowMidY),
                                 size: capSize)
    }
}
