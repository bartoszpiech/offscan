#if DEBUG
import UIKit
import PencilKit

/// Handwritten-looking signatures for the demo library: drawn in ink on demo pages and, as a
/// `PKDrawing`, pre-filled on the signature canvas while the demo library is active.
enum DemoSignature {
    /// The strokes of signature `variant` (0, 1 or 2) as polylines fitted into `rect`
    /// (top-left origin).
    static func strokes(in rect: CGRect, variant: Int) -> [[CGPoint]] {
        unitStrokes(variant: variant).map { stroke in
            stroke.map { CGPoint(x: rect.minX + $0.x * rect.width, y: rect.minY + $0.y * rect.height) }
        }
    }

    /// Signature variant 0 as a PencilKit drawing fitted into `rect` (canvas points), in `color`.
    static func drawing(in rect: CGRect, color: UIColor = .black) -> PKDrawing {
        let ink = PKInk(.pen, color: color)
        let strokes = strokes(in: rect, variant: 0).map { polyline in
            let points = polyline.enumerated().map { offset, location in
                PKStrokePoint(
                    location: location,
                    timeOffset: TimeInterval(offset) * 0.008,
                    size: CGSize(width: 4, height: 4),
                    opacity: 1,
                    force: 1,
                    azimuth: 0,
                    altitude: .pi / 2
                )
            }
            return PKStroke(ink: ink, path: PKStrokePath(controlPoints: points, creationDate: Date()))
        }
        return PKDrawing(strokes: strokes)
    }

    // MARK: Shapes (unit square, top-left origin)

    private static func unitStrokes(variant: Int) -> [[CGPoint]] {
        switch variant % 3 {
        case 0:
            return [
                cubic(CGPoint(x: 0.03, y: 0.80), CGPoint(x: 0.08, y: -0.05), CGPoint(x: 0.26, y: -0.05), CGPoint(x: 0.20, y: 0.82))
                    + cubic(CGPoint(x: 0.20, y: 0.82), CGPoint(x: 0.17, y: 0.95), CGPoint(x: 0.05, y: 0.55), CGPoint(x: 0.30, y: 0.50)),
                cursive(from: 0.30, to: 0.90, baseline: 0.70, loops: 6, height: 0.34, slant: 0.12, wobble: 0.5),
                cubic(CGPoint(x: 0.94, y: 0.56), CGPoint(x: 0.80, y: 0.98), CGPoint(x: 0.35, y: 0.86), CGPoint(x: 0.06, y: 0.94)),
            ]
        case 1:
            return [
                cubic(CGPoint(x: 0.04, y: 0.22), CGPoint(x: 0.18, y: 0.08), CGPoint(x: 0.32, y: 0.14), CGPoint(x: 0.42, y: 0.18)),
                cubic(CGPoint(x: 0.23, y: 0.14), CGPoint(x: 0.18, y: 0.50), CGPoint(x: 0.22, y: 0.82), CGPoint(x: 0.12, y: 0.86)),
                cursive(from: 0.27, to: 0.86, baseline: 0.76, loops: 5, height: 0.38, slant: 0.05, wobble: 1.3),
                cubic(CGPoint(x: 0.86, y: 0.62), CGPoint(x: 0.92, y: 0.40), CGPoint(x: 0.96, y: 0.30), CGPoint(x: 0.99, y: 0.18)),
            ]
        default:
            return [
                cursive(from: 0.04, to: 0.74, baseline: 0.72, loops: 7, height: 0.55, slant: 0.25, wobble: 2.1),
                cubic(CGPoint(x: 0.70, y: 0.45), CGPoint(x: 0.86, y: 0.28), CGPoint(x: 0.96, y: 0.78), CGPoint(x: 0.30, y: 0.88)),
            ]
        }
    }

    /// A run of joined cursive loops: a prolate cycloid (loops at the top), with loop heights that
    /// vary a little and a baseline rising by `slant`.
    private static func cursive(from x0: CGFloat, to x1: CGFloat, baseline: CGFloat, loops: Int, height: CGFloat, slant: CGFloat, wobble: CGFloat) -> [CGPoint] {
        let end = 2 * CGFloat.pi * CGFloat(loops)
        let r = (x1 - x0) / end
        let d = r * 1.9
        var points: [CGPoint] = []
        var t: CGFloat = 0
        while t <= end {
            let loop = t / (2 * .pi)
            let amplitude = height * (0.72 + 0.28 * sin(loop * 1.7 + wobble))
            let x = x0 + r * t - d * sin(t)
            let y = baseline - amplitude * (1 + cos(t)) / 2 - slant * (x - x0)
            points.append(CGPoint(x: x, y: y))
            t += 0.09
        }
        return points
    }

    private static func cubic(_ p0: CGPoint, _ c1: CGPoint, _ c2: CGPoint, _ p1: CGPoint, samples: Int = 40) -> [CGPoint] {
        (0...samples).map { i in
            let t = CGFloat(i) / CGFloat(samples)
            let u = 1 - t
            let a = u * u * u, b = 3 * u * u * t, c = 3 * u * t * t, e = t * t * t
            return CGPoint(
                x: a * p0.x + b * c1.x + c * c2.x + e * p1.x,
                y: a * p0.y + b * c1.y + c * c2.y + e * p1.y
            )
        }
    }
}
#endif
