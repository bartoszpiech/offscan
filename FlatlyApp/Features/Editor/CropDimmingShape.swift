import SwiftUI

/// Outer rect minus inner rect (even-odd fill) used to dim the area outside the crop.
struct CropDimmingShape: Shape {
    var outer: CGRect
    var inner: CGRect

    func path(in _: CGRect) -> Path {
        var p = Path()
        p.addRect(outer)
        p.addRect(inner)
        return p
    }
}
