import Testing
import Foundation
import CoreGraphics
@testable import FlatlyCore

struct QuadrilateralTests {
    @Test func fullFrameHasUnitArea() {
        #expect(Quadrilateral.fullFrame.area == 1)
        #expect(Quadrilateral.fullFrame.isConvex)
    }

    @Test func orderedSortsArbitraryPoints() throws {
        let points = [CGPoint(x: 0.9, y: 0.1), CGPoint(x: 0.1, y: 0.9), CGPoint(x: 0.1, y: 0.1), CGPoint(x: 0.9, y: 0.9)]
        let q = try #require(Quadrilateral.ordered(from: points))
        #expect(q.topLeft == CGPoint(x: 0.1, y: 0.9))
        #expect(q.topRight == CGPoint(x: 0.9, y: 0.9))
        #expect(q.bottomRight == CGPoint(x: 0.9, y: 0.1))
        #expect(q.bottomLeft == CGPoint(x: 0.1, y: 0.1))
    }

    @Test func flipKeepsCornerNames() {
        let q = Quadrilateral.fullFrame.flippedVertically()
        #expect(q.topLeft == CGPoint(x: 0, y: 0))
        #expect(q.bottomRight == CGPoint(x: 1, y: 1))
    }

    @Test func bowtieIsNotConvex() {
        let q = Quadrilateral(topLeft: CGPoint(x: 0, y: 1), topRight: CGPoint(x: 1, y: 0), bottomRight: CGPoint(x: 1, y: 1), bottomLeft: CGPoint(x: 0, y: 0))
        #expect(!q.isConvex)
    }

    // MARK: Strict convexity

    private func quad(_ tl: (CGFloat, CGFloat), _ tr: (CGFloat, CGFloat), _ br: (CGFloat, CGFloat), _ bl: (CGFloat, CGFloat)) -> Quadrilateral {
        Quadrilateral(
            topLeft: CGPoint(x: tl.0, y: tl.1), topRight: CGPoint(x: tr.0, y: tr.1),
            bottomRight: CGPoint(x: br.0, y: br.1), bottomLeft: CGPoint(x: bl.0, y: bl.1)
        )
    }

    @Test func coincidentCornersAreNotConvex() {
        // Top-left dragged onto top-right: a triangle.
        #expect(!quad((1, 1), (1, 1), (1, 0), (0, 0)).isConvex)
    }

    @Test func nearlyCoincidentCornersAreNotConvex() {
        // Top edge only 0.005 long.
        #expect(!quad((0.995, 1), (1, 1), (1, 0), (0, 0)).isConvex)
    }

    @Test func collinearCornersAreNotConvex() {
        // Top-left on the diagonal from bottom-left to top-right.
        #expect(!quad((0.5, 0.5), (1, 1), (1, 0), (0, 0)).isConvex)
    }

    @Test func mirroredQuadIsNotConvex() {
        // Left and right swapped: counter-clockwise, the page would come out mirrored.
        #expect(!quad((1, 1), (0, 1), (0, 0), (1, 0)).isConvex)
        // What dragging the left edge past the right edge produces.
        #expect(!quad((0.95, 0.9), (0.9, 0.9), (0.9, 0.1), (0.95, 0.1)).isConvex)
    }

    @Test func nonFiniteCornersAreNotConvex() {
        #expect(!quad((.nan, 1), (1, 1), (1, 0), (0, 0)).isConvex)
    }

    @Test func typicalSheetsAreConvex() {
        // The skewed sheet from PerspectiveCorrectorTests, normalised by 1000×800.
        #expect(quad((0.18, 0.8125), (0.82, 0.875), (0.88, 0.15), (0.12, 0.225)).isConvex)
        // A small 0.1×0.1 square.
        #expect(quad((0.45, 0.55), (0.55, 0.55), (0.55, 0.45), (0.45, 0.45)).isConvex)
    }

    // MARK: Callers

    @Test func rejectsDegenerateQuad() {
        let image = Synthetic.image(width: 100, height: 100, background: Synthetic.gray(1))
        #expect(throws: FlatlyCoreError.invalidQuadrilateral) {
            try PerspectiveCorrector().correct(image, to: quad((1, 1), (1, 1), (1, 0), (0, 0)))
        }
    }

    @Test func rejectsMirroredQuad() {
        let image = Synthetic.image(width: 100, height: 100, background: Synthetic.gray(1))
        #expect(throws: FlatlyCoreError.invalidQuadrilateral) {
            try PerspectiveCorrector().correct(image, to: quad((1, 1), (0, 1), (0, 0), (1, 0)))
        }
    }

    @Test func mirroredDetectionIsIgnored() {
        let sheet = QuadStabilityTrackerTests.sheet
        func mirrored(_ p: CGPoint) -> CGPoint { CGPoint(x: 1 - p.x, y: p.y) }
        let mirror = Quadrilateral(
            topLeft: mirrored(sheet.topLeft), topRight: mirrored(sheet.topRight),
            bottomRight: mirrored(sheet.bottomRight), bottomLeft: mirrored(sheet.bottomLeft)
        )
        var tracker = QuadStabilityTracker(requiredDuration: 0.5)
        let start = Date(timeIntervalSince1970: 0)
        for i in 0...10 { tracker.update(with: mirror, at: start + Double(i) * 0.1) }
        #expect(tracker.smoothedQuad == nil)
        #expect(!tracker.isStable(at: start + 1))
    }
}
