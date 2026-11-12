import Testing
import Foundation
import CoreGraphics
@testable import FlatlyCore

/// End-to-end import pipeline on real photos: decode → detect → correct → filter → OCR.
extension FixtureTests {
    @Suite struct OCRPipelineTests {
        /// Minimum match ratio for black & white output (bi-level images lose some anti-aliasing
        /// detail, so this is a little looser than the colour pipeline's `minimumMatchRatio`).
        static let blackAndWhiteMinimumMatchRatio = 0.7

        struct Score {
            var found: [String]
            var missing: [String]
            var ratio: Double { Double(found.count) / Double(max(1, found.count + missing.count)) }
        }

        static func runPipeline(_ name: String, filter: ScanFilter) throws -> (Score, OCRResult) {
            let photo = try Fixtures.photo(name, maxDimension: 3500)
            let detected = try DocumentDetector().detect(in: photo)
            let page = try PerspectiveCorrector().correct(photo, to: detected.quad)
            let filtered = try FilterEngine().apply(filter, to: page)
            let result = try TextRecognizer().recognize(filtered)
            let text = result.text.lowercased()
            var score = Score(found: [], missing: [])
            for word in Fixtures.fixture(name).words {
                if text.contains(word.lowercased()) { score.found.append(word) } else { score.missing.append(word) }
            }
            return (score, result)
        }

        static func report(_ name: String, _ filter: ScanFilter, _ score: Score) {
            let pct = String(format: "%.0f%%", score.ratio * 100)
            print("OCR[\(filter.rawValue)] \(name): \(score.found.count)/\(score.found.count + score.missing.count) = \(pct)"
                + (score.missing.isEmpty ? "" : " missing: \(score.missing.joined(separator: ", "))"))
        }

        /// One test over all fixtures (rather than one per fixture) so the average can be checked:
        /// Vision's output differs slightly between OS builds and hardware, so a single photo may
        /// dip a few words while the aggregate stays stable.
        @Test func colorPipelineFindsExpectedWords() throws {
            var ratios: [Double] = []
            for name in Fixtures.names {
                let (score, result) = try Self.runPipeline(name, filter: .color)
                Self.report(name, .color, score)
                #expect(!result.lines.isEmpty, "\(name) produced no text")
                for line in result.lines {
                    #expect(line.boundingBox.minX >= -0.01 && line.boundingBox.maxX <= 1.01)
                    #expect(line.boundingBox.minY >= -0.01 && line.boundingBox.maxY <= 1.01)
                }
                #expect(score.ratio >= Fixtures.expected.minimumMatchRatio, "\(name) missing \(score.missing)")
                // Joining wrapped lines for reading must never lose a word.
                let text = result.text.lowercased(), readable = result.readableText.lowercased()
                for word in Fixtures.fixture(name).words where text.contains(word.lowercased()) {
                    #expect(readable.contains(word.lowercased()), "\(name): readableText lost \(word)")
                }
                ratios.append(score.ratio)
            }
            let average = ratios.reduce(0, +) / Double(max(1, ratios.count))
            print(String(format: "OCR[color] average over %d fixtures: %.1f%%", ratios.count, average * 100))
            #expect(average >= Fixtures.expected.minimumAverageMatchRatio)
        }

        @Test(arguments: Fixtures.names)
        func blackAndWhitePipelineKeepsTextLegible(name: String) throws {
            let (score, _) = try Self.runPipeline(name, filter: .blackAndWhite)
            Self.report(name, .blackAndWhite, score)
            #expect(score.ratio >= Self.blackAndWhiteMinimumMatchRatio, "\(name) missing \(score.missing)")
        }
    }
}

struct TextRecognizerTests {
    @Test func recognisesSyntheticText() throws {
        let image = Synthetic.image(width: 1200, height: 400, background: Synthetic.gray(1)) { ctx in
            Synthetic.drawText("Zażółć gęślą jaźń 2026", at: CGPoint(x: 60, y: 220), size: 64, in: ctx)
            Synthetic.drawText("Flatly document scanner", at: CGPoint(x: 60, y: 80), size: 64, in: ctx)
        }
        let result = try TextRecognizer().recognize(image)
        let text = result.text.lowercased()
        #expect(text.contains("flatly"))
        #expect(text.contains("2026"))
        #expect(result.lines.allSatisfy { !$0.text.isEmpty && $0.confidence > 0 })
        // Bottom-left origin: the first line drawn higher up has the larger y.
        let top = try #require(result.lines.first { $0.text.contains("2026") })
        let bottom = try #require(result.lines.first { $0.text.lowercased().contains("flatly") })
        #expect(top.boundingBox.midY > bottom.boundingBox.midY)
    }

    @Test func blankImageHasNoText() throws {
        let image = Synthetic.image(width: 300, height: 200, background: Synthetic.gray(1))
        #expect(try TextRecognizer().recognize(image).isEmpty)
    }
}
