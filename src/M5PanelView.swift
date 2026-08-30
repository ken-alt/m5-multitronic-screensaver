//
//  M5PanelView.swift
//  M-5 Multitronic screensaver
//
//  Inspired by the M-5 computer readout panel from Star Trek TOS,
//  "The Ultimate Computer" (S2E24) — the black panel of short coloured
//  light bars that blink, extend and retract while the machine "thinks".
//

import ScreenSaver
import Cocoa

// MARK: - Palette

/// Sampled from the M-5 readout panel. 1960s Technicolor pushes everything
/// warm, so the greens sit yellow and the reds sit orange.
private struct PaletteEntry {
    let r, g, b: CGFloat
    let weight: CGFloat
}

/// Deliberately type-scoped rather than file-scope globals. A file-scope
/// `let` with a non-trivial initialiser crashes on first access once this
/// bundle is dlopen'd by the screensaver host — the lazy-initialisation
/// accessor emitted by the Swift 5.2 compiler does not survive the trip into
/// a much newer Swift runtime. Statics on a type use a different mechanism
/// and are fine.
private enum Palette {
    static let entries: [PaletteEntry] = [
        PaletteEntry(r: 0.620, g: 0.839, b: 0.235, weight: 1.00),   // lime
        PaletteEntry(r: 0.784, g: 0.847, b: 0.243, weight: 0.85),   // yellow-green
        PaletteEntry(r: 0.267, g: 0.745, b: 0.290, weight: 0.70),   // green
        PaletteEntry(r: 0.878, g: 0.729, b: 0.188, weight: 0.95),   // amber
        PaletteEntry(r: 0.886, g: 0.627, b: 0.157, weight: 0.85),   // gold
        PaletteEntry(r: 0.902, g: 0.502, b: 0.149, weight: 0.90),   // orange
        PaletteEntry(r: 0.863, g: 0.282, b: 0.157, weight: 0.80),   // red-orange
        PaletteEntry(r: 0.769, g: 0.157, b: 0.118, weight: 0.65),   // deep red
        PaletteEntry(r: 0.235, g: 0.784, b: 0.706, weight: 0.18),   // teal (rare)
    ]

    static let totalWeight: CGFloat = Palette.entries.reduce(0) { $0 + $1.weight }

    static func pickIndex() -> Int {
        var r = CGFloat.random(in: 0 ..< Palette.totalWeight)
        for (i, entry) in Palette.entries.enumerated() {
            r -= entry.weight
            if r <= 0 { return i }
        }
        return 0
    }
}

// MARK: - Bar model

private enum Phase {
    case grow, hold, leave, gap
}

private enum LeaveStyle {
    case retract    // shrinks back into its anchor
    case fade       // dims out at full length
    case cut        // snaps off
}

private struct Bar {
    var x: CGFloat = 0
    var y: CGFloat = 0
    var cell: Int = -1              // occupied grid cell, -1 when free
    var vertical = true
    var dir: CGFloat = 1            // +1 / -1 growth direction
    var maxLen: CGFloat = 0
    var thickness: CGFloat = 1
    var colorIndex = 0
    var vignette: CGFloat = 1       // edge falloff, baked in at spawn

    var phase: Phase = .gap
    var leaveStyle: LeaveStyle = .fade
    var t: Double = 0               // seconds elapsed in current phase
    var growDur: Double = 0
    var holdDur: Double = 0
    var leaveDur: Double = 0
    var gapDur: Double = 0

    // Hold-phase modulation
    var flickers = false            // hard on/off stutter
    var breathes = false            // slow smooth pulse
    var modRate: Double = 0
    var modPhase: Double = 0
}

private func easeOutCubic(_ p: Double) -> Double {
    let q = 1.0 - p
    return 1.0 - q * q * q
}

/// Drawn length and brightness for a bar. A length of 0 means don't draw.
private func barState(_ b: Bar) -> (len: CGFloat, alpha: CGFloat) {
    switch b.phase {
    case .grow:
        let p = b.growDur > 0 ? min(1.0, b.t / b.growDur) : 1.0
        return (b.maxLen * CGFloat(easeOutCubic(p)), 1.0)

    case .hold:
        if b.flickers {
            let s = sin(b.modPhase + b.t * b.modRate * .pi * 2.0)
            return (b.maxLen, s > -0.35 ? 1.0 : 0.10)   // hard stutter, mostly on
        }
        if b.breathes {
            let s = sin(b.modPhase + b.t * b.modRate * .pi * 2.0)
            return (b.maxLen, 0.72 + 0.28 * CGFloat((s + 1.0) * 0.5))
        }
        return (b.maxLen, 1.0)

    case .leave:
        switch b.leaveStyle {
        case .retract:
            let p = b.leaveDur > 0 ? min(1.0, b.t / b.leaveDur) : 1.0
            return (b.maxLen * CGFloat(1.0 - easeOutCubic(p)), 1.0)
        case .fade:
            let p = b.leaveDur > 0 ? min(1.0, b.t / b.leaveDur) : 1.0
            return (b.maxLen, CGFloat(1.0 - p))
        case .cut:
            return (0, 0)
        }

    case .gap:
        return (0, 0)
    }
}

// MARK: -

@objc(M5PanelView)
public class M5PanelView: ScreenSaverView {

    private var bars: [Bar] = []
    private var cellUsed: [Bool] = []

    private var cols = 0
    private var rows = 0
    private var cellW: CGFloat = 1
    private var cellH: CGFloat = 1
    private var originX: CGFloat = 0
    private var originY: CGFloat = 0

    private var unit: CGFloat = 1           // base thickness unit
    private var invHalfW: CGFloat = 1
    private var invHalfH: CGFloat = 1
    private var lastTime: TimeInterval = 0

    // MARK: Lifecycle

    public override init?(frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview)
        animationTimeInterval = 1.0 / 60.0
        wantsLayer = true
        buildLayout(for: frame.size, isPreview: isPreview)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    public override var isOpaque: Bool { return true }
    public override var hasConfigureSheet: Bool { return false }
    public override var configureSheet: NSWindow? { return nil }

    // MARK: Layout

    public override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        buildLayout(for: newSize, isPreview: isPreview)
    }

    private func buildLayout(for size: NSSize, isPreview: Bool) {
        guard size.width >= 8, size.height >= 8 else { return }

        let minDim = min(size.width, size.height)

        // A loose grid the bars snap to; the prop reads as a rough matrix
        // rather than free scatter.
        cellH = max(isPreview ? 9.0 : 34.0, minDim / (isPreview ? 13.0 : 21.0))
        cellW = cellH * 1.15

        cols = max(4, Int(size.width / cellW))
        rows = max(4, Int(size.height / cellH))

        // Centre the grid so the margins match on both sides.
        originX = (size.width - CGFloat(cols) * cellW) * 0.5
        originY = (size.height - CGFloat(rows) * cellH) * 0.5

        unit = max(isPreview ? 1.2 : 2.8, minDim / 225.0)

        invHalfW = 2.0 / max(1.0, size.width)
        invHalfH = 2.0 / max(1.0, size.height)

        cellUsed = [Bool](repeating: false, count: cols * rows)

        // Sparse: the panel is mostly black, with a couple dozen live bars.
        let want = min(max(8, Int(Double(cols * rows) * 0.060)), 80)

        bars = (0 ..< want).map { _ in
            var bar = spawnBar(releasing: -1)
            // Stagger the initial state so nothing starts in lockstep.
            bar.phase = [Phase.grow, .hold, .leave, .gap].randomElement()!
            bar.t = Double.random(in: 0 ..< 1.4)
            return bar
        }
    }

    // MARK: Bar spawning

    private func releaseCell(_ cell: Int) {
        if cell >= 0 && cell < cellUsed.count { cellUsed[cell] = false }
    }

    private func claimFreeCell() -> Int {
        let total = cellUsed.count
        guard total > 0 else { return -1 }
        for _ in 0 ..< 40 {
            let c = Int.random(in: 0 ..< total)
            if !cellUsed[c] { cellUsed[c] = true; return c }
        }
        return -1
    }

    /// Frees `oldCell` and returns a freshly configured bar in a new slot.
    private func spawnBar(releasing oldCell: Int) -> Bar {
        releaseCell(oldCell)

        let bounds = self.bounds
        var bar = Bar()

        let cell = claimFreeCell()
        bar.cell = cell

        let cx = cell >= 0 ? cell % cols : Int.random(in: 0 ..< max(1, cols))
        let cy = cell >= 0 ? cell / cols : Int.random(in: 0 ..< max(1, rows))

        // Snap to the grid, then jitter a little so it doesn't read as graph paper.
        bar.x = originX + (CGFloat(cx) + 0.5) * cellW + CGFloat.random(in: -0.16 ... 0.16) * cellW
        bar.y = originY + (CGFloat(cy) + 0.5) * cellH + CGFloat.random(in: -0.16 ... 0.16) * cellH

        // The prop is mostly upright bars with a scattering of horizontals.
        bar.vertical = Double.random(in: 0 ..< 1) < 0.72

        let span = bar.vertical ? cellH : cellW
        var cells: CGFloat
        let roll = Double.random(in: 0 ..< 1)
        if roll < 0.26 {
            cells = CGFloat.random(in: 0.95 ... 1.70)       // stub
        } else if roll < 0.70 {
            cells = CGFloat.random(in: 2.00 ... 3.80)       // medium
        } else {
            cells = CGFloat.random(in: 4.20 ... 7.60)       // long stroke
        }

        // The uprights run noticeably longer than the horizontals.
        if bar.vertical { cells *= 1.40 }
        let wantLen = span * cells

        // Grow towards whichever side has the room. Without this, long bars
        // that spawn near an edge just get clamped back into stubs.
        let roomPos = bar.vertical ? bounds.height - bar.y : bounds.width - bar.x
        let roomNeg = bar.vertical ? bar.y : bar.x
        if roomPos >= wantLen && roomNeg >= wantLen {
            bar.dir = Double.random(in: 0 ..< 1) < 0.5 ? 1 : -1
        } else {
            bar.dir = roomPos >= roomNeg ? 1 : -1
        }

        let limit = (bar.dir > 0 ? roomPos : roomNeg) - unit * 2.0
        bar.maxLen = min(wantLen, max(span * 0.5, limit))

        // Bake in the CRT edge falloff once, rather than compositing a
        // full-screen gradient every frame (that cost ~70ms at 2560x1600).
        let nx = (bar.x - bounds.midX) * invHalfW
        let ny = (bar.y - bounds.midY) * invHalfH
        let r2 = min(1.0, (nx * nx + ny * ny) * 0.75)
        bar.vignette = 1.0 - 0.45 * r2 * r2

        bar.thickness = unit * CGFloat.random(in: 0.88 ... 1.40)
        bar.colorIndex = Palette.pickIndex()

        // 25% snap on instantly — the readout should feel switched, not drawn.
        bar.growDur = Double.random(in: 0 ..< 1) < 0.25
            ? Double.random(in: 0.03 ... 0.10)
            : Double.random(in: 0.28 ... 0.90)
        bar.holdDur = Double.random(in: 1.20 ... 6.50)
        bar.leaveDur = Double.random(in: 0.20 ... 0.75)
        bar.gapDur = Double.random(in: 0.60 ... 4.80)

        let leaveRoll = Double.random(in: 0 ..< 1)
        bar.leaveStyle = leaveRoll < 0.40 ? .retract : (leaveRoll < 0.80 ? .fade : .cut)

        bar.flickers = Double.random(in: 0 ..< 1) < 0.22
        bar.breathes = !bar.flickers && Double.random(in: 0 ..< 1) < 0.30
        bar.modRate = bar.flickers
            ? Double.random(in: 1.4 ... 4.5)
            : Double.random(in: 0.18 ... 0.60)
        bar.modPhase = Double.random(in: 0 ..< (.pi * 2.0))

        bar.phase = .grow
        bar.t = 0
        return bar
    }

    // MARK: Animation

    public override func animateOneFrame() {
        let now = Date.timeIntervalSinceReferenceDate
        var dt = lastTime > 0 ? now - lastTime : 1.0 / 60.0
        lastTime = now
        if dt > 0.25 { dt = 0.25 }      // don't lurch after a stall

        for i in bars.indices {
            bars[i].t += dt
            switch bars[i].phase {
            case .grow:
                if bars[i].t >= bars[i].growDur {
                    bars[i].t -= bars[i].growDur
                    bars[i].phase = .hold
                }
            case .hold:
                if bars[i].t >= bars[i].holdDur {
                    bars[i].t -= bars[i].holdDur
                    bars[i].phase = .leave
                }
            case .leave:
                let d = bars[i].leaveStyle == .cut ? 0.0 : bars[i].leaveDur
                if bars[i].t >= d {
                    bars[i].t -= d
                    bars[i].phase = .gap
                    // Free the slot as soon as it goes dark so others can use it.
                    releaseCell(bars[i].cell)
                    bars[i].cell = -1
                }
            case .gap:
                if bars[i].t >= bars[i].gapDur {
                    let fresh = spawnBar(releasing: bars[i].cell)
                    bars[i] = fresh
                }
            }
        }

        setNeedsDisplay(bounds)
    }

    // MARK: Drawing

    public override func draw(_ rect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        // The panel face.
        ctx.setFillColor(gray: 0.016, alpha: 1.0)
        ctx.fill(bounds)

        guard !bars.isEmpty else { return }

        ctx.setLineCap(.round)
        ctx.setBlendMode(.plusLighter)

        // Each bar is a wide dim bloom, a tighter halo, and the saturated
        // core. plusLighter is saturating addition, so the three are
        // order-independent and can all be laid down in one visit to the bar —
        // no need for three passes over the whole array to get the core on top.
        let widthMul: [CGFloat] = [4.6, 2.5, 1.0]
        let alphaMul: [CGFloat] = [0.115, 0.25, 0.95]

        for bar in bars {
            let (len, alpha) = barState(bar)
            if len <= 0.5 || alpha <= 0.01 { continue }

            // Pull the bloom in on stubby bars so they read as short strokes
            // rather than glowing dots.
            let tight = min(1.0, len / (bar.thickness * 9.0))

            let c = Palette.entries[bar.colorIndex]
            let a = alpha * bar.vignette
            let start = CGPoint(x: bar.x, y: bar.y)
            let end = CGPoint(x: bar.x + (bar.vertical ? 0 : len * bar.dir),
                              y: bar.y + (bar.vertical ? len * bar.dir : 0))

            for pass in 0 ..< 3 {
                ctx.setStrokeColor(red: c.r, green: c.g, blue: c.b, alpha: a * alphaMul[pass])
                ctx.setLineWidth(bar.thickness * (1.0 + (widthMul[pass] - 1.0) * tight))
                ctx.move(to: start)
                ctx.addLine(to: end)
                ctx.strokePath()
            }
        }

        ctx.setBlendMode(.normal)
    }
}
