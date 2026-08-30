//
//  DrumDigits.swift
//  Chronometer screensaver
//
//  The TOS chronometer readout is a mechanical drum counter, not a segmented
//  display: rounded, wide, geometric numerals with a horizontal seam where the
//  two halves of the drum meet. These are stroked paths on a unit box rather
//  than a typeface, so nothing has to be bundled or installed.
//

import CoreGraphics
import Foundation

enum DrumDigits {

    /// Stroke weight as a fraction of digit height.
    static let strokeFraction: CGFloat = 0.165

    /// A stroked path for `d` (0...9) fitted to `box`, y-up.
    /// The path is built on a unit square and transformed, so the caller only
    /// controls placement and line width.
    static func path(_ d: Int, in box: CGRect) -> CGPath {
        let p = CGMutablePath()
        // Inset so the stroke stays inside the box.
        let t = strokeFraction
        let inset = t * 0.5
        let w = box.width * (1 - t)
        let h = box.height * (1 - t)
        let ox = box.minX + box.width * inset
        let oy = box.minY + box.height * inset

        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            return CGPoint(x: ox + x * w, y: oy + y * h)
        }
        func move(_ x: CGFloat, _ y: CGFloat) { p.move(to: pt(x, y)) }
        func line(_ x: CGFloat, _ y: CGFloat) { p.addLine(to: pt(x, y)) }
        func quad(_ cx: CGFloat, _ cy: CGFloat, _ x: CGFloat, _ y: CGFloat) {
            p.addQuadCurve(to: pt(x, y), control: pt(cx, cy))
        }
        /// Stadium ring — the shape of a drum-counter 0.
        func ring(_ x0: CGFloat, _ y0: CGFloat, _ x1: CGFloat, _ y1: CGFloat) {
            let r = CGRect(x: ox + x0 * w, y: oy + y0 * h,
                           width: (x1 - x0) * w, height: (y1 - y0) * h)
            let rad = min(r.width, r.height) * 0.48
            p.addRoundedRect(in: r, cornerWidth: rad, cornerHeight: rad)
        }

        switch d {
        case 0:
            ring(0, 0, 1, 1)

        case 1:
            move(0.20, 0.79); quad(0.38, 0.94, 0.52, 1.0)
            move(0.52, 1.0);  line(0.52, 0.0)

        case 2:
            move(0.03, 0.76)
            quad(0.06, 1.02, 0.50, 1.0)
            quad(0.97, 0.98, 0.96, 0.72)
            quad(0.94, 0.40, 0.02, 0.0)
            line(1.0, 0.0)

        case 3:
            move(0.06, 0.86)
            quad(0.30, 1.03, 0.60, 1.0)
            quad(1.02, 0.96, 0.94, 0.74)
            quad(0.88, 0.57, 0.44, 0.53)
            quad(0.94, 0.50, 0.97, 0.27)
            quad(1.0, 0.0, 0.55, 0.0)
            quad(0.20, 0.0, 0.05, 0.14)

        case 4:
            move(0.80, 0.0);  line(0.80, 1.0)
            move(0.80, 1.0);  line(0.02, 0.29)
            line(1.0, 0.29)

        case 5:
            move(0.94, 1.0);  line(0.16, 1.0)
            line(0.10, 0.60)
            quad(0.55, 0.72, 0.85, 0.53)
            quad(1.03, 0.40, 0.93, 0.20)
            quad(0.80, 0.0, 0.44, 0.0)
            quad(0.16, 0.0, 0.03, 0.11)

        case 6:
            move(0.88, 0.90)
            quad(0.62, 1.03, 0.36, 0.90)
            quad(0.05, 0.72, 0.04, 0.32)
            ring(0.04, 0.0, 0.96, 0.56)

        case 7:
            move(0.03, 1.0);  line(0.97, 1.0)
            line(0.32, 0.0)

        case 8:
            ring(0.06, 0.53, 0.94, 1.0)
            ring(0.0,  0.0,  1.0,  0.52)

        case 9:
            move(0.12, 0.10)
            quad(0.38, -0.03, 0.64, 0.10)
            quad(0.95, 0.28, 0.96, 0.68)
            ring(0.04, 0.44, 0.96, 1.0)

        default:
            break
        }
        return p
    }

    /// The colon between hour/minute/second groups: two square-ish dots.
    static func colonPath(in box: CGRect) -> CGPath {
        let p = CGMutablePath()
        let s = box.width * 0.46
        let r = s * 0.3
        for cy in [box.minY + box.height * 0.30, box.minY + box.height * 0.68] {
            let rect = CGRect(x: box.midX - s / 2, y: cy - s / 2, width: s, height: s)
            p.addRoundedRect(in: rect, cornerWidth: r, cornerHeight: r)
        }
        return p
    }
}
