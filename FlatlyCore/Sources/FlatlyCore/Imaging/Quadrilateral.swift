import Foundation
import CoreGraphics

/// Four corners of a document in **normalised** coordinates (0...1) with the origin at the
/// **bottom-left**, matching Vision's convention.
public struct Quadrilateral: Sendable, Hashable, Codable {
    public var topLeft: CGPoint
    public var topRight: CGPoint
    public var bottomRight: CGPoint
    public var bottomLeft: CGPoint

    public init(topLeft: CGPoint, topRight: CGPoint, bottomRight: CGPoint, bottomLeft: CGPoint) {
        self.topLeft = topLeft
        self.topRight = topRight
        self.bottomRight = bottomRight
        self.bottomLeft = bottomLeft
    }

    /// The whole image.
    public static let fullFrame = Quadrilateral(
        topLeft: CGPoint(x: 0, y: 1), topRight: CGPoint(x: 1, y: 1),
        bottomRight: CGPoint(x: 1, y: 0), bottomLeft: CGPoint(x: 0, y: 0)
    )

    /// Smallest turn (cross product of consecutive edges, normalised units) accepted at a corner;
    /// smaller turns count as collinear.
    public static let minimumTurn: CGFloat = 1e-4

    /// Shortest edge (normalised units) of a usable outline; shorter edges mean (nearly)
    /// coincident corners.
    public static let minimumEdgeLength: CGFloat = 0.01

    /// Corners in clockwise order starting at top-left.
    public var corners: [CGPoint] { [topLeft, topRight, bottomRight, bottomLeft] }

    /// Unsigned area (shoelace formula).
    public var area: CGFloat {
        let p = corners
        var sum: CGFloat = 0
        for i in 0..<4 {
            let a = p[i], b = p[(i + 1) % 4]
            sum += a.x * b.y - b.x * a.y
        }
        return abs(sum) / 2
    }

    /// True when the corners, in order top-left → top-right → bottom-right → bottom-left, turn
    /// strictly clockwise (bottom-left origin, normalised coordinates) at every corner and no edge
    /// is shorter than `minimumEdgeLength`. Rejects bow-ties, reflex corners, mirrored
    /// (counter-clockwise) outlines, collinear corners and coincident corners.
    public var isConvex: Bool {
        let p = corners
        for i in 0..<4 {
            let a = p[i], b = p[(i + 1) % 4], c = p[(i + 2) % 4]
            // `>=` / `<` comparisons are false for NaN, so NaN corners are rejected too.
            guard hypot(b.x - a.x, b.y - a.y) >= Self.minimumEdgeLength else { return false }
            // Four turns of the same sign on a quadrilateral also rule out self-intersection.
            let cross = (b.x - a.x) * (c.y - b.y) - (b.y - a.y) * (c.x - b.x)
            guard cross < -Self.minimumTurn else { return false }
        }
        return true
    }

    /// Multiplies every corner by `size`, keeping the bottom-left origin.
    public func scaled(to size: CGSize) -> Quadrilateral {
        func s(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x * size.width, y: p.y * size.height) }
        return Quadrilateral(topLeft: s(topLeft), topRight: s(topRight), bottomRight: s(bottomRight), bottomLeft: s(bottomLeft))
    }

    /// Converts between bottom-left and top-left origin (y' = 1 - y). Corner names stay meaningful
    /// in both systems: `topLeft` is still the visual top-left after flipping.
    public func flippedVertically() -> Quadrilateral {
        func f(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x, y: 1 - p.y) }
        return Quadrilateral(topLeft: f(topLeft), topRight: f(topRight), bottomRight: f(bottomRight), bottomLeft: f(bottomLeft))
    }

    /// Orders four arbitrary points into top-left, top-right, bottom-right, bottom-left
    /// (bottom-left origin: "top" means larger y). Returns nil unless exactly four points are given.
    public static func ordered(from points: [CGPoint]) -> Quadrilateral? {
        guard points.count == 4 else { return nil }
        let cx = points.map(\.x).reduce(0, +) / 4
        let cy = points.map(\.y).reduce(0, +) / 4
        var tl: CGPoint?, tr: CGPoint?, br: CGPoint?, bl: CGPoint?
        // Classify by quadrant relative to the centroid; fall back to angle sort if a quadrant is doubled.
        for p in points {
            switch (p.x < cx, p.y >= cy) {
            case (true, true): if tl == nil { tl = p } else { return angleOrdered(points, cx: cx, cy: cy) }
            case (false, true): if tr == nil { tr = p } else { return angleOrdered(points, cx: cx, cy: cy) }
            case (false, false): if br == nil { br = p } else { return angleOrdered(points, cx: cx, cy: cy) }
            case (true, false): if bl == nil { bl = p } else { return angleOrdered(points, cx: cx, cy: cy) }
            }
        }
        guard let tl, let tr, let br, let bl else { return angleOrdered(points, cx: cx, cy: cy) }
        return Quadrilateral(topLeft: tl, topRight: tr, bottomRight: br, bottomLeft: bl)
    }

    private static func angleOrdered(_ points: [CGPoint], cx: CGFloat, cy: CGFloat) -> Quadrilateral? {
        // Sort clockwise (in a bottom-left origin system clockwise means decreasing angle) starting
        // from the point whose angle is closest to 135° (top-left).
        let sorted = points.sorted { atan2($0.y - cy, $0.x - cx) > atan2($1.y - cy, $1.x - cx) }
        guard sorted.count == 4 else { return nil }
        let target = 3 * CGFloat.pi / 4
        let startIndex = sorted.indices.min { a, b in
            abs(atan2(sorted[a].y - cy, sorted[a].x - cx) - target) < abs(atan2(sorted[b].y - cy, sorted[b].x - cx) - target)
        } ?? 0
        let r = (0..<4).map { sorted[(startIndex + $0) % 4] }
        return Quadrilateral(topLeft: r[0], topRight: r[1], bottomRight: r[2], bottomLeft: r[3])
    }
}
