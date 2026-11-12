import CoreGraphics
import FlatlyCore

/// One analysed camera frame, published from the video queue to the main actor.
struct LiveDetectionUpdate: Sendable, Equatable {
    /// Smoothed document outline (normalised, bottom-left origin, in the upright frame), or nil.
    let quad: Quadrilateral?
    /// Progress of the current steady period, 0...1.
    let progress: Double
    /// The sheet has been held steady long enough to capture it automatically.
    let isStable: Bool
    /// The tracked sheet is too small in the frame for auto-capture.
    let isTooSmall: Bool
    /// Orientation the frame was analysed for; outlines from another orientation are stale.
    let orientation: CameraOrientation
    /// Pixel size of the upright frame the quad refers to.
    let uprightSize: CGSize
}
