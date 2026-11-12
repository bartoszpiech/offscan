import Testing
import Foundation
import CoreGraphics
import PDFKit
@testable import FlatlyCore

/// Cross-service tests that the per-service suites could not cover while the services were being
/// written in parallel.
extension FixtureTests {
    @Suite struct IntegrationTests {
        /// original → crop → filter → rotate → signature, with the signature composited last.
        @Test(PencilKitAvailability.trait) func pageRendererCompositesSignature() throws {
            let original = Synthetic.image(width: 800, height: 1000, background: CGColor(gray: 1, alpha: 1))
            let signature = SignaturePlacement(
                drawingData: SignatureRendererTests.makeDrawingData(),
                frame: CGRect(x: 0.55, y: 0.8, width: 0.4, height: 0.12)   // bottom-right, top-left origin
            )
            let recipe = PageRenderRecipe(cropRect: nil, filter: .grayscale, rotation: .quarter, signature: signature)
            let rendered = try PageRenderer().render(original, recipe: recipe)
            // Rotated by a quarter turn: dimensions swap.
            #expect(rendered.width == 1000 && rendered.height == 800)
            let bitmap = Bitmap(rendered)
            // The signature frame is relative to the rotated image.
            let frame = CGRect(x: 0.55 * 1000, y: 0.8 * 800, width: 0.4 * 1000, height: 0.12 * 800)
            var darkInside = 0, darkOutside = 0
            for y in stride(from: 0, to: 800, by: 2) {
                for x in stride(from: 0, to: 1000, by: 2) {
                    let p = bitmap[x, y]
                    guard p.luminance < 128 else { continue }
                    if frame.insetBy(dx: -2, dy: -2).contains(CGPoint(x: x, y: y)) { darkInside += 1 } else { darkOutside += 1 }
                }
            }
            #expect(darkInside > 50, "signature ink should appear inside its frame")
            #expect(darkOutside == 0, "nothing outside the signature frame may change")
        }

        /// A photo through the whole import pipeline into a searchable PDF.
        @Test func fixtureBecomesSearchablePDF() throws {
            let name = "hours-portrait.heic"
            let photo = try Fixtures.photo(name)
            let detection = try DocumentDetector().detect(in: photo)
            let page = try PerspectiveCorrector().correct(photo, to: detection.quad)
            let rendered = try PageRenderer().render(page, recipe: PageRenderRecipe(filter: .blackAndWhite))
            let ocr = try TextRecognizer().recognize(rendered)
            #expect(ocr.lines.count > 10)

            let export = try ImageTransforms().resized(rendered, maxDimension: CompressionLevel.medium.maxPixelDimension)
            let pdfData = try PDFExporter().makePDF(
                pages: [ExportPage(image: export, ocr: ocr)], pageSize: .a4, compression: .medium, title: "Wykaz"
            )
            let pdf = try #require(PDFDocument(data: pdfData))
            #expect(pdf.pageCount == 1)
            let bounds = try #require(pdf.page(at: 0)).bounds(for: .mediaBox)
            #expect(bounds.width < bounds.height, "portrait scan → portrait A4")
            let text = try #require(pdf.page(at: 0)?.string)
            #expect(text.localizedCaseInsensitiveContains("PRZYKŁADOWY"))
            #expect(!pdf.findString("TESTOWA", withOptions: .caseInsensitive).isEmpty)
            #expect(pdfData.count < 2_000_000, "medium compression of one page stays under 2 MB")
        }
    }
}
