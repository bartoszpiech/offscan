import Foundation

/// One of the four edges of a `Quadrilateral`; dragging its midpoint handle moves both end corners.
enum QuadEdge: CaseIterable, Hashable, Sendable {
    case top, right, bottom, left

    /// The edge's end corners, in clockwise order.
    var corners: (QuadCorner, QuadCorner) {
        switch self {
        case .top: (.topLeft, .topRight)
        case .right: (.topRight, .bottomRight)
        case .bottom: (.bottomRight, .bottomLeft)
        case .left: (.bottomLeft, .topLeft)
        }
    }

    var accessibilityIdentifier: String {
        switch self {
        case .top: "edge.top"
        case .right: "edge.right"
        case .bottom: "edge.bottom"
        case .left: "edge.left"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .top: String(localized: "Top edge")
        case .right: String(localized: "Right edge")
        case .bottom: String(localized: "Bottom edge")
        case .left: String(localized: "Left edge")
        }
    }
}
