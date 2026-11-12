import SwiftUI

/// A closed four-point outline in view coordinates whose corners animate smoothly between
/// detections (unlike `Path`, which SwiftUI can't interpolate).
struct LiveQuadShape: Shape {
    var topLeft: CGPoint
    var topRight: CGPoint
    var bottomRight: CGPoint
    var bottomLeft: CGPoint

    /// `corners` in the order top-left, top-right, bottom-right, bottom-left.
    init(corners: [CGPoint]) {
        topLeft = corners.count > 0 ? corners[0] : .zero
        topRight = corners.count > 1 ? corners[1] : .zero
        bottomRight = corners.count > 2 ? corners[2] : .zero
        bottomLeft = corners.count > 3 ? corners[3] : .zero
    }

    var animatableData: AnimatablePair<
        AnimatablePair<CGPoint.AnimatableData, CGPoint.AnimatableData>,
        AnimatablePair<CGPoint.AnimatableData, CGPoint.AnimatableData>
    > {
        get {
            AnimatablePair(
                AnimatablePair(topLeft.animatableData, topRight.animatableData),
                AnimatablePair(bottomRight.animatableData, bottomLeft.animatableData)
            )
        }
        set {
            topLeft.animatableData = newValue.first.first
            topRight.animatableData = newValue.first.second
            bottomRight.animatableData = newValue.second.first
            bottomLeft.animatableData = newValue.second.second
        }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: topLeft)
        path.addLine(to: topRight)
        path.addLine(to: bottomRight)
        path.addLine(to: bottomLeft)
        path.closeSubpath()
        return path
    }
}
