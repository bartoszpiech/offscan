import SwiftUI
import CoreGraphics

/// The eight handles of the crop rectangle.
enum CropHandle: String, CaseIterable, Identifiable {
    case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left

    var id: String { rawValue }

    /// -1 = moves the left edge, +1 = moves the right edge, 0 = no horizontal edge.
    var horizontalSign: CGFloat {
        switch self {
        case .topLeft, .left, .bottomLeft: -1
        case .topRight, .right, .bottomRight: 1
        case .top, .bottom: 0
        }
    }

    /// -1 = moves the top edge, +1 = moves the bottom edge, 0 = no vertical edge.
    var verticalSign: CGFloat {
        switch self {
        case .topLeft, .top, .topRight: -1
        case .bottomLeft, .bottom, .bottomRight: 1
        case .left, .right: 0
        }
    }

    func point(in frame: CGRect) -> CGPoint {
        let x: CGFloat = horizontalSign < 0 ? frame.minX : (horizontalSign > 0 ? frame.maxX : frame.midX)
        let y: CGFloat = verticalSign < 0 ? frame.minY : (verticalSign > 0 ? frame.maxY : frame.midY)
        return CGPoint(x: x, y: y)
    }

    /// Moves this handle's edges of `rect` by the normalised `delta`, clamped to the unit square.
    func resize(_ rect: CGRect, by delta: CGSize) -> CGRect {
        let minSize = CropGeometry.minimumSize
        var minX = rect.minX, maxX = rect.maxX, minY = rect.minY, maxY = rect.maxY
        if horizontalSign < 0 { minX = min(max(minX + delta.width, 0), maxX - minSize) }
        if horizontalSign > 0 { maxX = max(min(maxX + delta.width, 1), minX + minSize) }
        if verticalSign < 0 { minY = min(max(minY + delta.height, 0), maxY - minSize) }
        if verticalSign > 0 { maxY = max(min(maxY + delta.height, 1), minY + minSize) }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    var accessibilityLabel: Text {
        switch self {
        case .topLeft: Text("Top left crop handle")
        case .top: Text("Top crop handle")
        case .topRight: Text("Top right crop handle")
        case .right: Text("Right crop handle")
        case .bottomRight: Text("Bottom right crop handle")
        case .bottom: Text("Bottom crop handle")
        case .bottomLeft: Text("Bottom left crop handle")
        case .left: Text("Left crop handle")
        }
    }
}
