import SwiftUI
import FlatlyCore

/// The displayed image's rect minus the quad (fill it with an even-odd style), used to dim
/// everything outside the document outline so the page keeps its true colour.
struct QuadDimmingShape: Shape {
    var quad: Quadrilateral

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addRect(rect)
        path.addPath(QuadOverlayShape(quad: quad).path(in: rect))
        return path
    }
}
