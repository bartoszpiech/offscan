import Foundation

/// One of the four corners of a `Quadrilateral`, in visual (on-screen) terms.
enum QuadCorner: CaseIterable, Hashable, Sendable {
    case topLeft, topRight, bottomRight, bottomLeft

    var accessibilityIdentifier: String {
        switch self {
        case .topLeft: "corner.topLeft"
        case .topRight: "corner.topRight"
        case .bottomRight: "corner.bottomRight"
        case .bottomLeft: "corner.bottomLeft"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .topLeft: String(localized: "Top left corner")
        case .topRight: String(localized: "Top right corner")
        case .bottomRight: String(localized: "Bottom right corner")
        case .bottomLeft: String(localized: "Bottom left corner")
        }
    }
}
