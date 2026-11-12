import Testing
import Foundation
import CoreGraphics
@testable import FlatlyCore

struct QuadStabilityTrackerTests {
    static let sheet = Quadrilateral(
        topLeft: CGPoint(x: 0.2, y: 0.85), topRight: CGPoint(x: 0.8, y: 0.85),
        bottomRight: CGPoint(x: 0.8, y: 0.15), bottomLeft: CGPoint(x: 0.2, y: 0.15)
    )

    static func jittered(_ q: Quadrilateral, by d: CGFloat) -> Quadrilateral {
        Quadrilateral(
            topLeft: CGPoint(x: q.topLeft.x + d, y: q.topLeft.y), topRight: q.topRight,
            bottomRight: CGPoint(x: q.bottomRight.x, y: q.bottomRight.y - d), bottomLeft: q.bottomLeft
        )
    }

    @Test func steadySheetBecomesStableAfterRequiredDuration() {
        var tracker = QuadStabilityTracker(requiredDuration: 0.9)
        let start = Date(timeIntervalSince1970: 0)
        for i in 0..<10 {   // 10 fps for 0.9 s, tiny jitter
            tracker.update(with: Self.jittered(Self.sheet, by: i.isMultiple(of: 2) ? 0.003 : -0.003), at: start + Double(i) * 0.1)
        }
        #expect(tracker.isStable(at: start + 0.9))
        #expect(!tracker.isStable(at: start + 0.5) || tracker.progress(at: start + 0.5) < 1)
    }

    @Test func movementRestartsTheSteadyPeriod() {
        var tracker = QuadStabilityTracker(requiredDuration: 0.9)
        let start = Date(timeIntervalSince1970: 0)
        for i in 0..<6 { tracker.update(with: Self.sheet, at: start + Double(i) * 0.1) }
        tracker.update(with: Self.jittered(Self.sheet, by: 0.1), at: start + 0.6)   // big move
        #expect(tracker.steadySince == start + 0.6)
        #expect(!tracker.isStable(at: start + 1.0))
    }

    @Test func smallSheetNeverAutoCaptures() {
        var tracker = QuadStabilityTracker(requiredDuration: 0.3, minimumArea: 0.15)
        let tiny = Quadrilateral(
            topLeft: CGPoint(x: 0.45, y: 0.55), topRight: CGPoint(x: 0.55, y: 0.55),
            bottomRight: CGPoint(x: 0.55, y: 0.45), bottomLeft: CGPoint(x: 0.45, y: 0.45)
        )
        let start = Date(timeIntervalSince1970: 0)
        for i in 0..<10 { tracker.update(with: tiny, at: start + Double(i) * 0.1) }
        #expect(!tracker.isStable(at: start + 1))
    }

    @Test func briefDropoutIsTolerated_longDropoutResets() {
        var tracker = QuadStabilityTracker(requiredDuration: 0.9, dropoutGrace: 0.35)
        let start = Date(timeIntervalSince1970: 0)
        for i in 0..<5 { tracker.update(with: Self.sheet, at: start + Double(i) * 0.1) }
        tracker.update(with: nil, at: start + 0.6)            // 0.2 s gap: tolerated
        #expect(tracker.smoothedQuad != nil)
        // The latest frame had no sheet (motion blur, a hand): never fire on it.
        #expect(!tracker.isStable(at: start + 0.9))
        tracker.update(with: nil, at: start + 1.0)            // 0.6 s gap: reset
        #expect(tracker.smoothedQuad == nil)
        #expect(tracker.progress(at: start + 1.0) == 0)
    }

    @Test func dropoutFrameNeverFiresButNextDetectionDoes() {
        var tracker = QuadStabilityTracker(requiredDuration: 0.9, dropoutGrace: 0.35)
        let start = Date(timeIntervalSince1970: 0)
        for i in 0..<8 { tracker.update(with: Self.sheet, at: start + Double(i) * 0.11) }   // last at 0.77
        for t in [0.88, 0.99, 1.10] {
            tracker.update(with: nil, at: start + t)
            #expect(!tracker.isStable(at: start + t))
            #expect(tracker.smoothedQuad != nil)
        }
        // The ring holds where the last real detection left it.
        #expect(abs(tracker.progress(at: start + 1.10) - 0.77 / 0.9) < 0.001)
        // The steady period survived the short dropout: the next real frame fires.
        tracker.update(with: Self.sheet, at: start + 1.21)
        #expect(tracker.isStable(at: start + 1.21))
    }

    @Test func tinySheetShowsNoProgressAndIsTooSmall() {
        var tracker = QuadStabilityTracker(requiredDuration: 0.3, minimumArea: 0.15)
        let tiny = Quadrilateral(
            topLeft: CGPoint(x: 0.45, y: 0.55), topRight: CGPoint(x: 0.55, y: 0.55),
            bottomRight: CGPoint(x: 0.55, y: 0.45), bottomLeft: CGPoint(x: 0.45, y: 0.45)
        )
        let start = Date(timeIntervalSince1970: 0)
        for i in 0..<10 { tracker.update(with: tiny, at: start + Double(i) * 0.1) }
        #expect(tracker.progress(at: start + 1) == 0)
        #expect(tracker.isSheetTooSmall)
    }

    @Test func normalSheetIsNotTooSmall() {
        #expect(!QuadStabilityTracker().isSheetTooSmall)
        var tracker = QuadStabilityTracker()
        let start = Date(timeIntervalSince1970: 0)
        tracker.update(with: Self.sheet, at: start)
        #expect(!tracker.isSheetTooSmall)
        #expect(tracker.progress(at: start + 0.3) > 0)
    }

    @Test func resetClearsState() {
        var tracker = QuadStabilityTracker()
        tracker.update(with: Self.sheet, at: Date())
        tracker.reset()
        #expect(tracker.smoothedQuad == nil && tracker.steadySince == nil)
    }
}
