import Testing
import Foundation
import CoreGraphics
import ImageIO
@testable import FlatlyCore

struct JPEGExporterTests {
    @Test func outputDecodesWithSameSize() throws {
        let (image, _) = SyntheticImages.page(width: 800, height: 1000, lines: [("Faktura", CGRect(x: 0.1, y: 0.8, width: 0.5, height: 0.08))])
        let data = try JPEGExporter().makeJPEG(image, compression: .medium)
        #expect(data.starts(with: [0xFF, 0xD8, 0xFF]))
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        #expect(CGImageSourceGetType(source) as String? == "public.jpeg")
        let decoded = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(decoded.width == 800)
        #expect(decoded.height == 1000)
    }

    @Test func sizesAreOrderedByCompression() throws {
        let (image, _) = SyntheticImages.page(width: 1200, height: 1600, lines: [
            ("Faktura", CGRect(x: 0.1, y: 0.8, width: 0.5, height: 0.06)),
            ("Łódź 2026", CGRect(x: 0.1, y: 0.6, width: 0.6, height: 0.05))
        ])
        let exporter = JPEGExporter()
        let low = try exporter.makeJPEG(image, compression: .low).count
        let medium = try exporter.makeJPEG(image, compression: .medium).count
        let high = try exporter.makeJPEG(image, compression: .high).count
        #expect(high < medium, "high \(high) medium \(medium)")
        #expect(medium < low, "medium \(medium) low \(low)")
    }
}
