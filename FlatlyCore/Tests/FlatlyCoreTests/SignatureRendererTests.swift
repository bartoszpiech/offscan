import Testing
import Foundation
import CoreGraphics
import PencilKit
#if canImport(UIKit)
import UIKit
private let black = UIColor.black
#elseif canImport(AppKit)
import AppKit
private let black = NSColor.black
#endif
@testable import FlatlyCore

@Suite(PencilKitAvailability.trait)
struct SignatureRendererTests {
    /// A zig-zag "signature" stroke spanning roughly x 20...320, y 30...130 pt.
    ///
    /// Built programmatically when the process has a bundle identifier. The SwiftPM test helper
    /// used by `scripts/test-core.sh` has none, and `PKDrawing(strokes:)` then crashes inside
    /// PencilKit (`PKReplicaManager` writes preferences for a NULL bundle ID). Decoding and
    /// rendering — all the production code does — work fine without one, so in that case we
    /// use `fixtureDrawingBase64`, produced by exactly the construction below.
    static func makeDrawingData() -> Data {
        guard Bundle.main.bundleIdentifier != nil else {
            return Data(base64Encoded: fixtureDrawingBase64.joined())!
        }
        let points = (0...12).map { i -> PKStrokePoint in
            PKStrokePoint(
                location: CGPoint(x: 20 + Double(i) * 25, y: i.isMultiple(of: 2) ? 30 : 130),
                timeOffset: Double(i) * 0.05,
                size: CGSize(width: 6, height: 6),
                opacity: 1,
                force: 1,
                azimuth: 0,
                altitude: .pi / 2
            )
        }
        let path = PKStrokePath(controlPoints: points, creationDate: Date(timeIntervalSince1970: 1_791_469_979))
        let stroke = PKStroke(ink: PKInk(.pen, color: black), path: path)
        return PKDrawing(strokes: [stroke]).dataRepresentation()
    }

    /// `PKDrawing.dataRepresentation()` of the zig-zag stroke built in `makeDrawingData()`.
    static let fixtureDrawingBase64 = [
        "d3Jk8AEACAASEAAAAAAAAAAAAAAAAAAAAAASEMbozRDiykoEioZO2izJFBUaBggAEAAYABoGCAEQARgBIjQKFA0AAAAAFQAA",
        "AAAdAAAAACUAAIA/EhFjb20uYXBwbGUuaW5rLnBlbhgDQQAAAAAAAAAAKp0CChB9MeCJNNlC5YJqwltsi3DQEgYIABABGAEa",
        "BggAEAEYACAAKtkBChCh4rTvPa9D/omyV9COycB/EQAAgI3wO8hBGA0gAyj8DzIWAADAQOgDAADoA/9/AAD/fwAAwEAAADqc",
        "AQAAoEEAAPBBAAAAAAAANEIAAAJDzcxMPQAAjEIAAPBBzczMPQAAvkIAAAJDmpkZPgAA8EIAAPBBzcxMPgAAEUMAAAJDAACA",
        "PgAAKkMAAPBBmpmZPgAAQ0MAAAJDMzOzPgAAXEMAAPBBzczMPgAAdUMAAAJDZmbmPgAAh0MAAPBBAAAAPwCAk0MAAAJDzcwM",
        "PwAAoEMAAPBBmpkZPzIUDQAAcEEVAADIQR0AAJtDJQAAmEJA4O/Nwd4GOgYIABAAGABCEA9HXIponU5Sslrgwq+YyUA="
    ]

    @Test func drawingDataDecodesToTheZigZag() throws {
        let drawing = try PKDrawing(data: Self.makeDrawingData())
        #expect(drawing.strokes.count == 1)
        // The stroke path is a spline through the control points, so it does not reach every
        // zig-zag apex; it stays inside the control polygon (plus half the 6 pt nib).
        let bounds = drawing.bounds
        #expect(CGRect(x: 10, y: 20, width: 320, height: 120).contains(bounds), "\(bounds)")
        #expect(bounds.width > 250 && bounds.height > 40, "\(bounds)")
    }

    @Test func renderProducesTransparentImageWithInk() throws {
        let image = try SignatureRenderer().render(drawingData: Self.makeDrawingData(), size: CGSize(width: 400, height: 200))
        #expect(image.width == 400)
        #expect(image.height == 200)
        let pixels = PixelBuffer(image)
        var inked = 0, transparent = 0, darkInk = 0
        for y in 0..<pixels.height {
            for x in 0..<pixels.width {
                let p = pixels.rgba(x: x, y: y)
                if p.a == 0 { transparent += 1 }
                if p.a > 0 { inked += 1 }
                if p.a > 200 && p.r < 60 && p.g < 60 && p.b < 60 { darkInk += 1 }
            }
        }
        #expect(inked > 500, "inked \(inked)")
        #expect(transparent > 10_000, "transparent \(transparent)")
        #expect(darkInk > 100, "ink should stay black, dark opaque pixels: \(darkInk)")
    }

    @Test func emptyDrawingRendersFullyTransparent() throws {
        let image = try SignatureRenderer().render(drawingData: PKDrawing().dataRepresentation(), size: CGSize(width: 50, height: 20))
        let pixels = PixelBuffer(image)
        #expect(pixels.data.enumerated().allSatisfy { $0.offset % 4 != 3 || $0.element == 0 })
    }

    @Test func invalidDataThrows() {
        #expect(throws: FlatlyCoreError.self) {
            _ = try SignatureRenderer().render(drawingData: Data([1, 2, 3]), size: CGSize(width: 10, height: 10))
        }
    }

    @Test func compositeDrawsOnlyInsideTheFrame() throws {
        let page = SyntheticImages.solid(width: 1000, height: 1000, gray: 1)
        let frame = CGRect(x: 0.5, y: 0.75, width: 0.4, height: 0.15)   // top-left origin
        let placement = SignaturePlacement(drawingData: Self.makeDrawingData(), frame: frame)
        let result = try SignatureRenderer().composite(placement, onto: page)
        #expect(result.width == 1000)
        #expect(result.height == 1000)

        let pixels = PixelBuffer(result)
        // Frame in top-left pixel coordinates: x 500..<900, y 750..<900.
        let inside = { (x: Int, y: Int) in x >= 500 && x < 900 && y >= 750 && y < 900 }
        var darkInside = 0, nonWhiteOutside = 0
        for y in 0..<1000 {
            for x in 0..<1000 {
                let p = pixels.rgba(x: x, y: y)
                let isWhite = p.r > 250 && p.g > 250 && p.b > 250 && p.a == 255
                if inside(x, y) {
                    if p.r < 80 && p.g < 80 && p.b < 80 { darkInside += 1 }
                } else if !isWhite {
                    nonWhiteOutside += 1
                }
            }
        }
        #expect(darkInside > 100, "dark pixels inside frame: \(darkInside)")
        #expect(nonWhiteOutside == 0, "non-white pixels outside frame: \(nonWhiteOutside)")
    }
}
