import Testing
import Foundation
import CoreGraphics
import PDFKit
@testable import FlatlyCore

struct PDFPageRasterizerTests {
    private let rasterizer = PDFPageRasterizer()

    /// A fresh temporary folder; the caller removes it.
    private func makeFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("PDFPageRasterizerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// Writes a one-page PDF of `size` points drawn by `draw` (PDF space, bottom-left origin).
    private func writePDF(to url: URL, size: CGSize, auxiliary: [CFString: Any] = [:], _ draw: (CGContext) -> Void = { _ in }) throws {
        var box = CGRect(origin: .zero, size: size)
        let context = try #require(CGContext(url as CFURL, mediaBox: &box, auxiliary as CFDictionary))
        context.beginPDFPage(nil)
        draw(context)
        context.endPDFPage()
        context.closePDF()
    }

    private func channels(_ image: CGImage, x: Int, y: Int) -> [UInt8] {
        let p = PixelBuffer(image).rgba(x: x, y: y)
        return [p.r, p.g, p.b]
    }

    @Test func countsAndRendersExportedPages() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("export.pdf")
        try PDFExporter().makePDF(pages: PDFExporterTests.makePages(), pageSize: .a4, compression: .medium, title: "Test").write(to: url)

        #expect(try rasterizer.pageCount(of: url) == 2)
        let portrait = try rasterizer.render(pageAt: 0, of: url)
        #expect(portrait.height == 3500)
        #expect(abs(portrait.width - 2475) <= 1)
        let landscape = try rasterizer.render(pageAt: 1, of: url)
        #expect(landscape.width == 3500)
        #expect(abs(landscape.height - 2475) <= 1)
        let small = try rasterizer.render(pageAt: 0, of: url, maxDimension: 1000)
        #expect(max(small.width, small.height) == 1000)
    }

    @Test func smallPagesAreScaledUp() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("small.pdf")
        try writePDF(to: url, size: CGSize(width: 200, height: 100))
        let image = try rasterizer.render(pageAt: 0, of: url, maxDimension: 400)
        #expect(image.width == 400 && image.height == 200)
    }

    @Test func transparentPageRendersOnWhite() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("half.pdf")
        try writePDF(to: url, size: CGSize(width: 200, height: 100)) { context in
            context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
            context.fill(CGRect(x: 100, y: 0, width: 100, height: 100))
        }
        let image = try rasterizer.render(pageAt: 0, of: url, maxDimension: 400)
        #expect(channels(image, x: 50, y: 100).allSatisfy { $0 >= 250 })
        #expect(channels(image, x: 300, y: 100).allSatisfy { $0 <= 10 })
    }

    @Test func appliesPageRotation() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let plain = folder.appendingPathComponent("plain.pdf")
        try writePDF(to: plain, size: CGSize(width: 200, height: 100)) { context in
            context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 50, height: 50))   // PDF bottom-left
        }
        let document = try #require(PDFDocument(url: plain))
        try #require(document.page(at: 0)).rotation = 90
        let rotated = folder.appendingPathComponent("rotated.pdf")
        #expect(document.write(to: rotated))

        let image = try rasterizer.render(pageAt: 0, of: rotated, maxDimension: 400)
        #expect(image.width == 200 && image.height == 400)
        // Turned clockwise, the bottom-left marker ends up in the top-left corner.
        #expect(channels(image, x: 20, y: 20).allSatisfy { $0 <= 10 })
        #expect(channels(image, x: 20, y: 380).allSatisfy { $0 >= 250 })
    }

    @Test func rejectsNonPDFAndMissingFiles() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let fake = folder.appendingPathComponent("x.pdf")
        try ImageCodec().jpegData(Synthetic.redCornerImage(width: 40, height: 30), quality: 0.8).write(to: fake)
        #expect(throws: PDFPageRasterizerError.unreadable) { try rasterizer.pageCount(of: fake) }
        #expect(throws: PDFPageRasterizerError.unreadable) { try rasterizer.pageCount(of: folder.appendingPathComponent("missing.pdf")) }
    }

    @Test func rejectsPageOutOfRange() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("export.pdf")
        try PDFExporter().makePDF(pages: PDFExporterTests.makePages(), pageSize: .a4, compression: .medium, title: "Test").write(to: url)
        #expect(throws: PDFPageRasterizerError.pageOutOfRange) { try rasterizer.render(pageAt: 2, of: url) }
        #expect(throws: PDFPageRasterizerError.pageOutOfRange) { try rasterizer.render(pageAt: -1, of: url) }
    }

    @Test func passwordProtectedIsRefused() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("locked.pdf")
        try writePDF(to: url, size: CGSize(width: 200, height: 100), auxiliary: [
            kCGPDFContextUserPassword: "secret", kCGPDFContextOwnerPassword: "owner",
        ])
        #expect(throws: PDFPageRasterizerError.passwordProtected) { try rasterizer.pageCount(of: url) }
    }

    @Test func ownerPasswordOnlyStillRenders() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("restricted.pdf")
        try writePDF(to: url, size: CGSize(width: 200, height: 100), auxiliary: [
            kCGPDFContextOwnerPassword: "owner", kCGPDFContextAllowsCopying: false,
        ])
        #expect(try rasterizer.pageCount(of: url) == 1)
        let image = try rasterizer.render(pageAt: 0, of: url, maxDimension: 400)
        #expect(image.width == 400)
    }
}
