import SwiftUI
import FlatlyCore

/// The outline of a normalised (bottom-left origin) quadrilateral drawn into the shape's rect,
/// which must be the displayed image's frame.
struct QuadOverlayShape: Shape {
    var quad: Quadrilateral

    func path(in rect: CGRect) -> Path {
        func point(_ p: CGPoint) -> CGPoint {
            CGPoint(x: rect.minX + p.x * rect.width, y: rect.minY + (1 - p.y) * rect.height)
        }
        var path = Path()
        path.move(to: point(quad.topLeft))
        path.addLine(to: point(quad.topRight))
        path.addLine(to: point(quad.bottomRight))
        path.addLine(to: point(quad.bottomLeft))
        path.closeSubpath()
        return path
    }
}
