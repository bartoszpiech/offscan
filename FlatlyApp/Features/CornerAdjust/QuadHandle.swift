import CoreGraphics
import FlatlyCore

/// A draggable handle of the corner-adjust editor: a corner, or the midpoint of an edge.
enum QuadHandle: Hashable, Sendable {
    case corner(QuadCorner)
    case edge(QuadEdge)

    /// The handle's position in normalised, bottom-left-origin coordinates.
    func point(in quad: Quadrilateral) -> CGPoint {
        switch self {
        case .corner(let corner):
            return quad[corner]
        case .edge(let edge):
            let (a, b) = edge.corners
            let p = quad[a], q = quad[b]
            return CGPoint(x: (p.x + q.x) / 2, y: (p.y + q.y) / 2)
        }
    }

    var accessibilityIdentifier: String {
        switch self {
        case .corner(let corner): corner.accessibilityIdentifier
        case .edge(let edge): edge.accessibilityIdentifier
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .corner(let corner): corner.accessibilityLabel
        case .edge(let edge): edge.accessibilityLabel
        }
    }
}
