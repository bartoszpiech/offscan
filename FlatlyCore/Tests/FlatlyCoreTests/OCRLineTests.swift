import Testing
import Foundation
import CoreGraphics
@testable import FlatlyCore

struct OCRLineTests {
    @Test func decodesLegacyJSONWithoutDirection() throws {
        let json = #"{"lines":[{"text":"Faktura","boundingBox":[[0.1,0.2],[0.3,0.04]],"confidence":0.9}]}"#
        let result = try JSONDecoder().decode(OCRResult.self, from: Data(json.utf8))
        #expect(result.lines.count == 1)
        let line = try #require(result.lines.first)
        #expect(line.text == "Faktura")
        #expect(line.direction == nil)
        #expect(line.boundingBox == CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.04))
    }

    @Test func roundTripsDirection() throws {
        let result = OCRResult(lines: [
            OCRLine(text: "Faktura VAT", boundingBox: CGRect(x: 0.6, y: 0.2, width: 0.04, height: 0.6), confidence: 0.8, direction: .quarter),
            OCRLine(text: "Łódź", boundingBox: CGRect(x: 0.1, y: 0.7, width: 0.25, height: 0.05), confidence: 1)
        ])
        let data = try JSONEncoder().encode(result)
        #expect(try JSONDecoder().decode(OCRResult.self, from: data) == result)
    }

    @Test func nilDirectionIsNotEncoded() throws {
        let result = OCRResult(lines: [OCRLine(text: "Faktura", boundingBox: CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.04), confidence: 0.9)])
        let json = String(decoding: try JSONEncoder().encode(result), as: UTF8.self)
        #expect(!json.contains("direction"), "\(json)")
    }
}
