import Testing
import Foundation
import CoreGraphics
@testable import FlatlyCore

/// Text direction of recognised lines (`OCRLine.direction`).
struct TextRecognizerDirectionTests {
    @Test func textDirectionBucketsQuarterTurns() {
        let square = CGSize(width: 100, height: 100)
        func direction(_ topLeft: CGPoint, _ topRight: CGPoint) -> Rotation {
            TextRecognizer.textDirection(topLeft: topLeft, topRight: topRight, imageSize: square)
        }
        #expect(direction(CGPoint(x: 0, y: 0.5), CGPoint(x: 1, y: 0.5)) == .none)
        #expect(direction(CGPoint(x: 0.5, y: 1), CGPoint(x: 0.5, y: 0)) == .quarter)
        #expect(direction(CGPoint(x: 1, y: 0.5), CGPoint(x: 0, y: 0.5)) == .half)
        #expect(direction(CGPoint(x: 0.5, y: 0), CGPoint(x: 0.5, y: 1)) == .threeQuarters)
        // A 10° skew either way is still upright text.
        let skew = 10 * Double.pi / 180
        #expect(direction(CGPoint(x: 0.5, y: 0.5), CGPoint(x: 0.5 + 0.4 * cos(skew), y: 0.5 + 0.4 * sin(skew))) == .none)
        #expect(direction(CGPoint(x: 0.5, y: 0.5), CGPoint(x: 0.5 + 0.4 * cos(skew), y: 0.5 - 0.4 * sin(skew))) == .none)
        // Just past ±180° is still upside down.
        let nearlyHalf = 179 * Double.pi / 180
        #expect(direction(CGPoint(x: 0.5, y: 0.5), CGPoint(x: 0.5 + 0.4 * cos(nearlyHalf), y: 0.5 - 0.4 * sin(nearlyHalf))) == .half)
        // Coincident corners carry no direction.
        #expect(direction(CGPoint(x: 0.3, y: 0.3), CGPoint(x: 0.3, y: 0.3)) == .none)
    }

    @Test func textDirectionUsesPixelAspect() {
        // Pixel dx = 300, dy = -200: about -34°, upright text. In normalised units (0.1, -0.2)
        // the same corners would look like -63° and wrongly bucket to `.quarter`.
        let direction = TextRecognizer.textDirection(
            topLeft: CGPoint(x: 0.2, y: 0.6), topRight: CGPoint(x: 0.3, y: 0.4),
            imageSize: CGSize(width: 3000, height: 1000)
        )
        #expect(direction == .none)
    }

    @Test(arguments: Rotation.allCases)
    func recognisesTextDirection(rotation: Rotation) throws {
        let image = Synthetic.image(width: 1200, height: 1200, background: Synthetic.gray(1)) { ctx in
            ctx.translateBy(x: 600, y: 600)
            ctx.rotate(by: -CGFloat(rotation.radians))   // clockwise in the y-up bitmap
            Synthetic.drawText("Faktura VAT 2026", at: CGPoint(x: -400, y: 120), size: 64, in: ctx)
            Synthetic.drawText("Flatly document scanner", at: CGPoint(x: -400, y: -40), size: 64, in: ctx)
        }
        let result = try TextRecognizer().recognize(image)
        let lines = result.lines.filter {
            let text = $0.text.lowercased()
            return text.contains("2026") || text.contains("flatly")
        }
        #expect(!lines.isEmpty, "\(result.lines.map(\.text))")
        for line in lines {
            #expect(line.direction == rotation, "\(line.text) \(line.boundingBox)")
        }
    }
}
