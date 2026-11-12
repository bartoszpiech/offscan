import SwiftUI
import CoreGraphics
import FlatlyCore

/// Circular magnifier shown while dragging a corner handle: a zoomed region of the image centred
/// on `focus`, with the quad outline and a crosshair.
struct MagnifierLoupe: View {
    let image: CGImage
    /// Size of the image as displayed on screen (points).
    let displayedSize: CGSize
    /// Focus point relative to the displayed image's top-left corner (points).
    let focus: CGPoint
    let quad: Quadrilateral
    var diameter: CGFloat = 120
    var zoom: CGFloat = 2.5

    var body: some View {
        let zoomedSize = CGSize(width: displayedSize.width * zoom, height: displayedSize.height * zoom)
        Color.black
            .overlay {
                ZStack {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .interpolation(.high)
                    QuadOverlayShape(quad: quad)
                        .stroke(Color.accentColor, lineWidth: 2)
                }
                .frame(width: zoomedSize.width, height: zoomedSize.height)
                .offset(x: zoomedSize.width / 2 - focus.x * zoom, y: zoomedSize.height / 2 - focus.y * zoom)
            }
            .overlay { crosshair }
            .frame(width: diameter, height: diameter)
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(.white, lineWidth: 3))
            .shadow(color: .black.opacity(0.5), radius: 6)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private var crosshair: some View {
        ZStack {
            Rectangle().frame(width: 18, height: 1.5)
            Rectangle().frame(width: 1.5, height: 18)
        }
        .foregroundStyle(.white)
        .shadow(color: .black, radius: 1)
    }

    /// Where to centre the loupe for a finger at `point` inside a container of `size`:
    /// above the finger, or below it when there is no room at the top; kept on screen horizontally.
    static func center(for point: CGPoint, in size: CGSize, diameter: CGFloat = 120) -> CGPoint {
        let gap: CGFloat = 56
        let margin: CGFloat = 8
        let radius = diameter / 2
        var y = point.y - gap - radius
        if y - radius < margin { y = point.y + gap + radius }
        let minX = radius + margin
        let maxX = max(minX, size.width - radius - margin)
        let x = min(max(point.x, minX), maxX)
        return CGPoint(x: x, y: y)
    }
}
