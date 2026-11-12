import Foundation
import CoreGraphics

/// Decides when a live-detected document has been held steady long enough to capture it
/// automatically, and smooths the quad shown over the viewfinder.
///
/// Feed every detection result (or nil when nothing was found) with its timestamp. The tracker
/// reports `isStable` once every corner has stayed within `tolerance` (normalised units) of the
/// running average for at least `requiredDuration`, the sheet covers at least `minimumArea`, and
/// the latest frame contained a sheet (a frame without one — motion blur, a hand over the page —
/// never fires, though a short dropout keeps the outline and the steady period).
/// `progress` is 0 for sheets below `minimumArea` and holds during dropouts.
/// After a capture call `reset()` so the next page needs a fresh steady period.
public struct QuadStabilityTracker: Sendable {
    /// Maximum corner movement (normalised) still considered "steady".
    public var tolerance: CGFloat
    /// How long the quad must stay steady.
    public var requiredDuration: TimeInterval
    /// Smallest sheet (fraction of the frame) that may trigger auto-capture.
    public var minimumArea: CGFloat
    /// A gap without detections longer than this restarts the steady period.
    public var dropoutGrace: TimeInterval

    /// Exponentially smoothed quad for display; nil when nothing is being tracked.
    public private(set) var smoothedQuad: Quadrilateral?
    /// When the current steady period started.
    public private(set) var steadySince: Date?
    private var lastDetection: Date?
    /// The most recent frame contained a convex sheet.
    private var latestHadDetection = false

    public init(tolerance: CGFloat = 0.02, requiredDuration: TimeInterval = 0.9, minimumArea: CGFloat = 0.15, dropoutGrace: TimeInterval = 0.35) {
        self.tolerance = tolerance
        self.requiredDuration = requiredDuration
        self.minimumArea = minimumArea
        self.dropoutGrace = dropoutGrace
    }

    /// Progress of the current steady period, 0...1 (useful for a capture ring animation). 0 while
    /// the sheet is smaller than `minimumArea` (it can't be captured); during a dropout it holds
    /// where the last real detection left it.
    public func progress(at now: Date) -> Double {
        guard let smoothedQuad, smoothedQuad.area >= minimumArea, let steadySince else { return 0 }
        let end = latestHadDetection ? now : (lastDetection ?? steadySince)
        return max(0, min(1, end.timeIntervalSince(steadySince) / requiredDuration))
    }

    /// True when auto-capture should fire (also requires a detection in the latest frame).
    public func isStable(at now: Date) -> Bool {
        guard latestHadDetection, let smoothedQuad, smoothedQuad.area >= minimumArea, let steadySince else { return false }
        // Small epsilon: Date arithmetic is not exact at millisecond scale.
        return now.timeIntervalSince(steadySince) + 0.001 >= requiredDuration
    }

    /// True while a sheet is tracked but covers less of the frame than `minimumArea` (auto-capture
    /// can't fire; ask the user to move closer).
    public var isSheetTooSmall: Bool {
        guard let smoothedQuad else { return false }
        return smoothedQuad.area < minimumArea
    }

    /// Records a detection result.
    public mutating func update(with quad: Quadrilateral?, at now: Date) {
        guard let quad, quad.isConvex else {
            latestHadDetection = false
            if let last = lastDetection, now.timeIntervalSince(last) > dropoutGrace {
                smoothedQuad = nil
                steadySince = nil
            }
            return
        }
        lastDetection = now
        latestHadDetection = true
        guard let current = smoothedQuad else {
            smoothedQuad = quad
            steadySince = now
            return
        }
        if Self.maxCornerDistance(current, quad) > tolerance {
            // Moved: follow quickly, restart the steady period.
            smoothedQuad = Self.blend(current, quad, weight: 0.6)
            steadySince = now
        } else {
            smoothedQuad = Self.blend(current, quad, weight: 0.3)
            if steadySince == nil { steadySince = now }
        }
    }

    /// Forgets everything (call after a capture).
    public mutating func reset() {
        smoothedQuad = nil
        steadySince = nil
        lastDetection = nil
        latestHadDetection = false
    }

    static func maxCornerDistance(_ a: Quadrilateral, _ b: Quadrilateral) -> CGFloat {
        zip(a.corners, b.corners).map { hypot($0.x - $1.x, $0.y - $1.y) }.max() ?? 0
    }

    static func blend(_ a: Quadrilateral, _ b: Quadrilateral, weight: CGFloat) -> Quadrilateral {
        func mix(_ p: CGPoint, _ q: CGPoint) -> CGPoint {
            CGPoint(x: p.x + (q.x - p.x) * weight, y: p.y + (q.y - p.y) * weight)
        }
        return Quadrilateral(
            topLeft: mix(a.topLeft, b.topLeft), topRight: mix(a.topRight, b.topRight),
            bottomRight: mix(a.bottomRight, b.bottomRight), bottomLeft: mix(a.bottomLeft, b.bottomLeft)
        )
    }
}
