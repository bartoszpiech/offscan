import SwiftUI
import FlatlyCore

/// Draws the live document outline over the camera preview. Must be laid out with exactly the
/// preview layer's frame (see `CameraOverlayGeometry` for the mapping).
struct LiveQuadOverlay: View {
    /// Current outline, or nil when no sheet is tracked.
    let detection: LiveDetectionUpdate?

    var body: some View {
        GeometryReader { geo in
            if let detection, let quad = detection.quad {
                let corners = CameraOverlayGeometry.viewCorners(
                    of: quad,
                    imageSize: detection.uprightSize,
                    in: CGRect(origin: .zero, size: geo.size)
                )
                let shape = LiveQuadShape(corners: corners)
                shape
                    .fill(Color.accentColor.opacity(0.2))
                    .overlay(shape.stroke(Color.accentColor, style: StrokeStyle(lineWidth: 3, lineJoin: .round)))
                    .animation(.easeOut(duration: 0.12), value: quad)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: detection?.quad == nil)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
