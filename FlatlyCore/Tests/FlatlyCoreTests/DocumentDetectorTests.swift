import Testing
import CoreGraphics
@testable import FlatlyCore

struct DocumentDetectorTests {
    @Test func blankImageFallsBackToFullFrame() throws {
        let image = Synthetic.image(width: 400, height: 300, background: Synthetic.gray(0.5))
        let result = try DocumentDetector().detect(in: image)
        #expect(result.source == .fullFrame)
        #expect(result.quad == .fullFrame)
        #expect(result.confidence == 0)
    }
}

extension FixtureTests {
    @Suite struct DocumentDetectorFixtureTests {
        @Test(arguments: Fixtures.names)
        func detectsSheet(name: String) throws {
            let photo = try Fixtures.photo(name)
            let result = try DocumentDetector().detect(in: photo)
            print("\(name): source \(result.source) confidence \(result.confidence) area \(result.quad.area)")
            #expect(result.source != .fullFrame)
            #expect(result.confidence >= 0.5)
            #expect(result.quad.isConvex)
            #expect(result.quad.area >= 0.1 && result.quad.area <= 0.95)
        }
    }
}
