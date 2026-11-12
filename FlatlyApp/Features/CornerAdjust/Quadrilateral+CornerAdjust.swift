import CoreGraphics
import FlatlyCore

extension Quadrilateral {
    /// Access a corner by name (normalised, bottom-left origin).
    subscript(corner: QuadCorner) -> CGPoint {
        get {
            switch corner {
            case .topLeft: topLeft
            case .topRight: topRight
            case .bottomRight: bottomRight
            case .bottomLeft: bottomLeft
            }
        }
        set {
            switch corner {
            case .topLeft: topLeft = newValue
            case .topRight: topRight = newValue
            case .bottomRight: bottomRight = newValue
            case .bottomLeft: bottomLeft = newValue
            }
        }
    }

    /// Returns a copy with `handle` moved by `delta` (normalised, bottom-left origin), clamped to
    /// the unit square. Edge handles move both end corners together; their delta is clamped as a
    /// whole so the edge keeps its shape at the image border.
    func moving(_ handle: QuadHandle, by delta: CGVector) -> Quadrilateral {
        var result = self
        switch handle {
        case .corner(let corner):
            let p = self[corner]
            result[corner] = CGPoint(x: Self.clampUnit(p.x + delta.dx), y: Self.clampUnit(p.y + delta.dy))
        case .edge(let edge):
            let (a, b) = edge.corners
            let p = self[a], q = self[b]
            let dx = min(max(delta.dx, -min(p.x, q.x)), 1 - max(p.x, q.x))
            let dy = min(max(delta.dy, -min(p.y, q.y)), 1 - max(p.y, q.y))
            result[a] = CGPoint(x: Self.clampUnit(p.x + dx), y: Self.clampUnit(p.y + dy))
            result[b] = CGPoint(x: Self.clampUnit(q.x + dx), y: Self.clampUnit(q.y + dy))
        }
        return result
    }

    private static func clampUnit(_ v: CGFloat) -> CGFloat { min(max(v, 0), 1) }
}
