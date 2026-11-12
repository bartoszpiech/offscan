import Testing
import CoreGraphics
@testable import FlatlyCore

@Suite struct SignatureSpotFinderTests {
    let finder = SignatureSpotFinder()
    /// Today's default spot (`SignatureFrameGeometry.initialFrame` for a typical page).
    let preferred = CGRect(x: 0.575, y: 0.70, width: 0.35, height: 0.10)

    /// An OCR line at a top-left-origin rect (stored with Vision's bottom-left box).
    private func line(topLeft r: CGRect) -> OCRLine {
        OCRLine(text: "line", boundingBox: CGRect(x: r.minX, y: 1 - r.maxY, width: r.width, height: r.height), confidence: 1)
    }

    private func topLeftBoxes(_ lines: [OCRLine]) -> [CGRect] {
        lines.map { CGRect(x: $0.boundingBox.minX, y: 1 - $0.boundingBox.maxY, width: $0.boundingBox.width, height: $0.boundingBox.height) }
    }

    @Test func returnsPreferredWithoutText() {
        #expect(finder.frame(near: preferred, avoiding: []) == preferred)
    }

    @Test func returnsPreferredWhenAlreadyClear() {
        let lines = stride(from: 0.10, through: 0.40, by: 0.03).map { line(topLeft: CGRect(x: 0.1, y: $0, width: 0.8, height: 0.02)) }
        #expect(finder.frame(near: preferred, avoiding: lines) == preferred)
    }

    @Test func movesBelowTextThatRunsIntoPreferredSpot() {
        let lines = (0...20).map { k in line(topLeft: CGRect(x: 0.1, y: 0.12 + 0.03 * Double(k), width: 0.8, height: 0.02)) }
        let result = finder.frame(near: preferred, avoiding: lines)
        #expect(abs(result.width - preferred.width) < 1e-9 && abs(result.height - preferred.height) < 1e-9)
        #expect(abs(result.minX - 0.575) < 1e-9)
        #expect((0.749...0.761).contains(result.minY), "minY \(result.minY)")
        let padded = result.insetBy(dx: -0.01, dy: -0.01)
        #expect(!topLeftBoxes(lines).contains { $0.intersects(padded) })
    }

    @Test func usesVisionBottomLeftCoordinates() {
        // Vision box y 0.70–0.75 is top-left 0.25–0.30: far above the preferred spot.
        let vision = OCRLine(text: "line", boundingBox: CGRect(x: 0.1, y: 0.70, width: 0.8, height: 0.05), confidence: 1)
        #expect(finder.frame(near: preferred, avoiding: [vision]) == preferred)
    }

    @Test func fallsBackWhenNoSpaceIsFree() {
        let page = line(topLeft: CGRect(x: 0, y: 0, width: 1, height: 1))
        #expect(finder.frame(near: preferred, avoiding: [page]) == preferred)
    }

    @Test func prefersLowerSpotOnTie() {
        let spot = CGRect(x: 0.3, y: 0.45, width: 0.4, height: 0.1)
        let result = finder.frame(near: spot, avoiding: [line(topLeft: CGRect(x: 0, y: 0.495, width: 1, height: 0.01))])
        #expect(result.minY > 0.5, "minY \(result.minY)")
        #expect(abs(result.minX - 0.3) < 1e-9)
        #expect(abs(result.width - 0.4) < 1e-9 && abs(result.height - 0.1) < 1e-9)
    }

    @Test func shiftsSidewaysWhenThatIsCloser() {
        let result = finder.frame(near: preferred, avoiding: [line(topLeft: CGRect(x: 0.1, y: 0.74, width: 0.5, height: 0.02))])
        #expect(abs(result.minY - 0.70) < 1e-9)
        #expect((0.609...0.621).contains(result.minX), "minX \(result.minX)")
        #expect(result.maxX <= 1 && result.maxY <= 1 && result.minX >= 0 && result.minY >= 0)
    }
}
