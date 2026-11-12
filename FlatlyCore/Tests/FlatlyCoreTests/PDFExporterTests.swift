import Testing
import Foundation
import CoreGraphics
import PDFKit
@testable import FlatlyCore

struct PDFExporterTests {
    static let lodzBox = CGRect(x: 0.1, y: 0.70, width: 0.25, height: 0.05)

    /// Two pages: portrait 1200×1600 and landscape 1600×1200, each with a hand-made OCR result.
    static func makePages() -> [ExportPage] {
        let (portrait, portraitOCR) = SyntheticImages.page(width: 1200, height: 1600, lines: [
            ("Faktura", CGRect(x: 0.1, y: 0.85, width: 0.4, height: 0.06)),
            ("Łódź", lodzBox),
            ("Invoice 2026", CGRect(x: 0.1, y: 0.55, width: 0.5, height: 0.05))
        ])
        let (landscape, landscapeOCR) = SyntheticImages.page(width: 1600, height: 1200, lines: [
            ("Invoice", CGRect(x: 0.2, y: 0.5, width: 0.4, height: 0.08))
        ])
        return [ExportPage(image: portrait, ocr: portraitOCR), ExportPage(image: landscape, ocr: landscapeOCR)]
    }

    private func document(_ pageSize: PageSizeOption, compression: CompressionLevel = .medium, title: String = "Test") throws -> PDFDocument {
        let data = try PDFExporter().makePDF(pages: Self.makePages(), pageSize: pageSize, compression: compression, title: title)
        return try #require(PDFDocument(data: data))
    }

    private func isClose(_ a: CGFloat, _ b: CGFloat, tolerance: CGFloat = 1) -> Bool {
        abs(a - b) <= tolerance
    }

    @Test func a4PagesTurnLandscapeForLandscapeImages() throws {
        let doc = try document(.a4)
        #expect(doc.pageCount == 2)
        let first = try #require(doc.page(at: 0)).bounds(for: .mediaBox)
        let second = try #require(doc.page(at: 1)).bounds(for: .mediaBox)
        #expect(isClose(first.width, 595.276) && isClose(first.height, 841.89), "\(first)")
        #expect(isClose(second.width, 841.89) && isClose(second.height, 595.276), "\(second)")
    }

    @Test func letterPageSize() throws {
        let doc = try document(.letter)
        let first = try #require(doc.page(at: 0)).bounds(for: .mediaBox)
        let second = try #require(doc.page(at: 1)).bounds(for: .mediaBox)
        #expect(isClose(first.width, 612) && isClose(first.height, 792), "\(first)")
        #expect(isClose(second.width, 792) && isClose(second.height, 612), "\(second)")
    }

    @Test func fitToContentKeepsImageAspectRatio() throws {
        let doc = try document(.fitToContent)
        let first = try #require(doc.page(at: 0)).bounds(for: .mediaBox)
        let second = try #require(doc.page(at: 1)).bounds(for: .mediaBox)
        #expect(isClose(first.width, 595.276))
        #expect(isClose(first.height / first.width, 1600.0 / 1200.0, tolerance: 0.01), "\(first)")
        #expect(isClose(second.width, 595.276))
        #expect(isClose(second.height / second.width, 1200.0 / 1600.0, tolerance: 0.01), "\(second)")
    }

    @Test func textLayerIsSearchableAndKeepsPolishDiacritics() throws {
        let doc = try document(.a4)
        let firstText = try #require(doc.page(at: 0)?.string)
        let secondText = try #require(doc.page(at: 1)?.string)
        #expect(firstText.contains("Łódź"), "\(firstText)")
        #expect(firstText.contains("Faktura"))
        #expect(firstText.contains("Invoice"))
        #expect(secondText.contains("Invoice"), "\(secondText)")
        #expect(doc.string?.contains("Łódź") == true)
    }

    @Test func searchHighlightCoversTheLineBox() throws {
        let doc = try document(.a4)
        let page = try #require(doc.page(at: 0))
        let hits = doc.findString("Łódź", withOptions: .caseInsensitive)
        let hit = try #require(hits.first)
        let found = hit.bounds(for: page)

        // Expected rect: image (1200×1600) aspect-fit into A4 portrait, then the normalised box.
        let pageBox = page.bounds(for: .mediaBox)
        let scale = min(pageBox.width / 1200, pageBox.height / 1600)
        let imageRect = CGRect(
            x: (pageBox.width - 1200 * scale) / 2, y: (pageBox.height - 1600 * scale) / 2,
            width: 1200 * scale, height: 1600 * scale
        )
        let box = Self.lodzBox
        let expected = CGRect(
            x: imageRect.minX + box.minX * imageRect.width,
            y: imageRect.minY + box.minY * imageRect.height,
            width: box.width * imageRect.width,
            height: box.height * imageRect.height
        )
        let tolX = expected.width * 0.1, tolY = expected.height * 0.1
        #expect(found.intersects(expected), "found \(found) expected \(expected)")
        #expect(abs(found.minX - expected.minX) <= tolX, "found \(found) expected \(expected)")
        #expect(abs(found.maxX - expected.maxX) <= tolX, "found \(found) expected \(expected)")
        #expect(abs(found.minY - expected.minY) <= tolY, "found \(found) expected \(expected)")
        #expect(abs(found.maxY - expected.maxY) <= tolY, "found \(found) expected \(expected)")
    }

    @Test func titleAndCreatorMetadata() throws {
        let doc = try document(.a4, title: "Faktura Łódź 2026")
        let attributes = try #require(doc.documentAttributes)
        #expect(attributes[PDFDocumentAttribute.titleAttribute] as? String == "Faktura Łódź 2026")
        #expect(attributes[PDFDocumentAttribute.creatorAttribute] as? String == "Offscan")
    }

    @Test func compressionLevelChangesFileSize() throws {
        let pages = Self.makePages()
        let exporter = PDFExporter()
        let low = try exporter.makePDF(pages: pages, pageSize: .a4, compression: .low, title: "T").count
        let medium = try exporter.makePDF(pages: pages, pageSize: .a4, compression: .medium, title: "T").count
        let high = try exporter.makePDF(pages: pages, pageSize: .a4, compression: .high, title: "T").count
        #expect(high < medium, "high \(high) medium \(medium)")
        #expect(medium < low, "medium \(medium) low \(low)")
    }

    @Test func imagesAreEmbeddedAsJPEGStreams() throws {
        let data = try PDFExporter().makePDF(pages: Self.makePages(), pageSize: .a4, compression: .medium, title: "T")
        let raw = String(decoding: data, as: UTF8.self)
        #expect(raw.components(separatedBy: "/DCTDecode").count - 1 == 2)
    }

    @Test func pageWithoutOCRIsImageOnly() throws {
        let image = SyntheticImages.solid(width: 300, height: 400, gray: 0.5)
        let data = try PDFExporter().makePDF(pages: [ExportPage(image: image, ocr: nil), ExportPage(image: image, ocr: .empty)], pageSize: .fitToContent, compression: .medium, title: "T")
        let doc = try #require(PDFDocument(data: data))
        #expect(doc.pageCount == 2)
        for index in 0..<2 {
            let text = (doc.page(at: index)?.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            #expect(text == "")
        }
    }

    @Test func zeroPagesThrows() {
        #expect(throws: FlatlyCoreError.self) {
            _ = try PDFExporter().makePDF(pages: [], pageSize: .a4, compression: .medium, title: "T")
        }
    }

    // MARK: Text direction

    /// A blank 1200×1600 page carrying `lines`, exported as A4 portrait.
    private func directionDocument(_ lines: [OCRLine]) throws -> PDFDocument {
        let page = ExportPage(image: SyntheticImages.solid(width: 1200, height: 1600), ocr: OCRResult(lines: lines))
        let data = try PDFExporter().makePDF(pages: [page], pageSize: .a4, compression: .medium, title: "T")
        return try #require(PDFDocument(data: data))
    }

    /// The normalised `box` in points on `page`: the 1200×1600 image aspect-fit into the page.
    private func expectedRect(for box: CGRect, on page: PDFPage) -> CGRect {
        let pageBox = page.bounds(for: .mediaBox)
        let scale = min(pageBox.width / 1200, pageBox.height / 1600)
        let imageRect = CGRect(
            x: (pageBox.width - 1200 * scale) / 2, y: (pageBox.height - 1600 * scale) / 2,
            width: 1200 * scale, height: 1600 * scale
        )
        return CGRect(
            x: imageRect.minX + box.minX * imageRect.width,
            y: imageRect.minY + box.minY * imageRect.height,
            width: box.width * imageRect.width,
            height: box.height * imageRect.height
        )
    }

    @Test(arguments: [Rotation.quarter, .threeQuarters])
    func sidewaysLineHighlightMatchesItsBox(direction: Rotation) throws {
        let box = CGRect(x: 0.6, y: 0.2, width: 0.04, height: 0.6)
        let doc = try directionDocument([OCRLine(text: "Faktura VAT 2026", boundingBox: box, confidence: 1, direction: direction)])
        let page = try #require(doc.page(at: 0))
        let expected = expectedRect(for: box, on: page)
        let hit = try #require(doc.findString("Faktura", withOptions: .caseInsensitive).first).bounds(for: page)

        // The highlight is a column as wide as the box, covering only the first word.
        let tolX = expected.width * 0.15
        #expect(abs(hit.width - expected.width) <= tolX, "hit \(hit) expected \(expected)")
        #expect(hit.height < expected.height * 0.6, "hit \(hit) expected \(expected)")
        #expect(abs(hit.minX - expected.minX) <= tolX, "hit \(hit) expected \(expected)")
        #expect(abs(hit.maxX - expected.maxX) <= tolX, "hit \(hit) expected \(expected)")
        #expect(expected.insetBy(dx: -2, dy: -2).contains(hit), "hit \(hit) expected \(expected)")
        if direction == .quarter {
            // Reads top to bottom: the first word sits at the top of the box.
            #expect(abs(hit.maxY - expected.maxY) <= 3, "hit \(hit) expected \(expected)")
        } else {
            // Reads bottom to top: the first word sits at the bottom of the box.
            #expect(abs(hit.minY - expected.minY) <= 3, "hit \(hit) expected \(expected)")
        }
        #expect(page.string?.contains("Faktura VAT 2026") == true, "\(page.string ?? "")")
    }

    @Test func upsideDownLineHighlightsTheRightEnd() throws {
        let box = CGRect(x: 0.2, y: 0.5, width: 0.6, height: 0.04)
        let doc = try directionDocument([OCRLine(text: "Faktura VAT 2026", boundingBox: box, confidence: 1, direction: .half)])
        let page = try #require(doc.page(at: 0))
        let expected = expectedRect(for: box, on: page)
        let hit = try #require(doc.findString("Faktura", withOptions: .caseInsensitive).first).bounds(for: page)

        // Upside down, the first word sits at the right end of the box.
        #expect(abs(hit.maxX - expected.maxX) <= 3, "hit \(hit) expected \(expected)")
        #expect(hit.width < expected.width * 0.6, "hit \(hit) expected \(expected)")
        #expect(abs(hit.height - expected.height) <= expected.height * 0.15, "hit \(hit) expected \(expected)")
        #expect(page.string?.contains("Faktura VAT 2026") == true, "\(page.string ?? "")")
    }

    @Test func sidewaysLinesKeepTextAndDiacritics() throws {
        let doc = try directionDocument([
            OCRLine(text: "Łódź Sprzedawca", boundingBox: CGRect(x: 0.6, y: 0.2, width: 0.04, height: 0.6), confidence: 1, direction: .quarter),
            OCRLine(text: "Faktura 2026", boundingBox: CGRect(x: 0.5, y: 0.35, width: 0.04, height: 0.45), confidence: 1, direction: .quarter)
        ])
        let text = try #require(doc.page(at: 0)?.string)
        #expect(text.contains("Łódź Sprzedawca"), "\(text)")
        #expect(text.contains("Faktura 2026"), "\(text)")
    }

    // MARK: Streaming

    private func temporaryPDFURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("PDFExporterTests-\(UUID().uuidString).pdf")
    }

    @Test func writePDFRequestsPagesInOrderAndMatchesMakePDF() throws {
        let pages = Self.makePages()
        let url = temporaryPDFURL()
        defer { try? FileManager.default.removeItem(at: url) }
        var requested: [Int] = []
        try PDFExporter().writePDF(to: url, pageCount: pages.count, pageSize: .a4, compression: .medium, title: "Faktura") { index in
            requested.append(index)
            return pages[index]
        }
        #expect(requested == [0, 1])

        let streamed = try #require(PDFDocument(url: url))
        let inMemory = try document(.a4, title: "Faktura")
        #expect(streamed.pageCount == inMemory.pageCount)
        for index in 0..<inMemory.pageCount {
            #expect(streamed.page(at: index)?.bounds(for: .mediaBox) == inMemory.page(at: index)?.bounds(for: .mediaBox))
            #expect(streamed.page(at: index)?.string == inMemory.page(at: index)?.string)
        }
        #expect(streamed.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String == "Faktura")
    }

    @Test func writePDFPropagatesPageErrors() {
        let pages = Self.makePages()
        let url = temporaryPDFURL()
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(throws: CancellationError.self) {
            try PDFExporter().writePDF(to: url, pageCount: 2, pageSize: .a4, compression: .medium, title: "T") { index in
                if index == 1 { throw CancellationError() }
                return pages[index]
            }
        }
    }

    @Test func writePDFWithZeroPagesThrows() {
        let url = temporaryPDFURL()
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(throws: FlatlyCoreError.self) {
            try PDFExporter().writePDF(to: url, pageCount: 0, pageSize: .a4, compression: .medium, title: "T") { _ in
                Issue.record("page(_:) must not be called")
                return Self.makePages()[0]
            }
        }
    }

    // MARK: Password

    @Test func passwordEncryptsPDF() throws {
        let data = try PDFExporter().makePDF(pages: Self.makePages(), pageSize: .a4, compression: .medium, title: "T", password: "s3cret pass")
        let doc = try #require(PDFDocument(data: data))
        #expect(doc.isEncrypted)
        #expect(doc.isLocked)
        #expect(!doc.unlock(withPassword: "wrong"))
        #expect(doc.unlock(withPassword: "s3cret pass"))
        #expect(!doc.isLocked)
        #expect(doc.pageCount == 2)
        let text = try #require(doc.string)
        #expect(text.contains("Faktura"), "\(text)")
        #expect(text.contains("Łódź"), "\(text)")

        // AES (crypt filter AESV2, 128-bit), not RC4. The encryption dictionary itself is plain.
        let raw = String(decoding: data, as: UTF8.self)
        #expect(raw.contains("/AESV2"))
    }

    @Test func writePDFWithPasswordEncryptsFile() throws {
        let pages = Self.makePages()
        let url = temporaryPDFURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try PDFExporter().writePDF(to: url, pageCount: pages.count, pageSize: .a4, compression: .medium, title: "T", password: "s3cret pass") { pages[$0] }

        let doc = try #require(PDFDocument(url: url))
        #expect(doc.isEncrypted)
        #expect(doc.isLocked)
        #expect(!doc.unlock(withPassword: "wrong"))
        #expect(doc.unlock(withPassword: "s3cret pass"))
        #expect(doc.pageCount == 2)
        let text = try #require(doc.string)
        #expect(text.contains("Faktura"), "\(text)")
        #expect(text.contains("Łódź"), "\(text)")
    }

    @Test func noPasswordLeavesPDFOpen() throws {
        let doc = try document(.a4)
        #expect(!doc.isEncrypted)
        #expect(!doc.isLocked)
    }

    @Test(arguments: ["hasło", "", "😀x"])
    func unsupportedPasswordThrows(password: String) {
        #expect(throws: FlatlyCoreError.processingFailed("Unsupported PDF password")) {
            _ = try PDFExporter().makePDF(pages: Self.makePages(), pageSize: .a4, compression: .medium, title: "T", password: password)
        }
    }

    @Test func writePDFWithUnsupportedPasswordLeavesNoFile() {
        let url = temporaryPDFURL()
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(throws: FlatlyCoreError.processingFailed("Unsupported PDF password")) {
            try PDFExporter().writePDF(to: url, pageCount: 2, pageSize: .a4, compression: .medium, title: "T", password: "zażółć") { _ in
                Issue.record("page(_:) must not be called")
                return Self.makePages()[0]
            }
        }
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test(arguments: [
        ("abc", true), ("two words", true), ("p@ss!~#", true),
        ("", false), ("hasło", false), ("café", false), ("😀", false)
    ])
    func isSupportedPassword(password: String, expected: Bool) {
        #expect(PDFExporter.isSupportedPassword(password) == expected)
    }
}
