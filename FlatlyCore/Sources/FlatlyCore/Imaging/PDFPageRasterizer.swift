import Foundation
import CoreGraphics

/// Renders the pages of an existing PDF file into images (CoreGraphics only), so a PDF can be
/// imported as pages: signed, recombined or re-compressed like a scan.
///
/// Pages are drawn on opaque white (transparent PDF areas would otherwise turn black in a JPEG),
/// from the crop box (what viewers show), with the page's `/Rotate` applied so the result is
/// upright. Password-protected PDFs are refused; PDFs with only an owner password (printing or
/// copying restrictions) open normally.
public struct PDFPageRasterizer: Sendable {
    public init() {}

    /// Number of pages of the PDF at `url`.
    /// Throws `PDFPageRasterizerError.unreadable` (missing, not a PDF, no pages) or `.passwordProtected`.
    public func pageCount(of url: URL) throws -> Int {
        let document = try openDocument(url)
        guard document.numberOfPages > 0 else { throw PDFPageRasterizerError.unreadable }
        return document.numberOfPages
    }

    /// Renders page `index` (0-based) of the PDF at `url` so that its longer side is `maxDimension`
    /// pixels (small pages are scaled up), upright, on white, in sRGB.
    /// Throws `PDFPageRasterizerError` (`.pageOutOfRange` for a bad index).
    public func render(pageAt index: Int, of url: URL, maxDimension: Int = 3500) throws -> CGImage {
        let document = try openDocument(url)
        guard index >= 0, index < document.numberOfPages, let page = document.page(at: index + 1) else {
            throw PDFPageRasterizerError.pageOutOfRange
        }
        let box = page.getBoxRect(.cropBox)
        guard !box.isEmpty, box.width > 0, box.height > 0, maxDimension > 0 else { throw PDFPageRasterizerError.renderFailed }
        let turns = ((Int(page.rotationAngle) % 360) + 360) % 360 / 90
        let upright = turns % 2 == 1 ? CGSize(width: box.height, height: box.width) : box.size
        let scale = CGFloat(maxDimension) / max(upright.width, upright.height)
        let width = max(1, Int((upright.width * scale).rounded()))
        let height = max(1, Int((upright.height * scale).rounded()))
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
              ) else { throw PDFPageRasterizerError.renderFailed }
        context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.interpolationQuality = .high
        // `getDrawingTransform` never scales a page up, only down, so scale to the pixel size
        // first and let it map the (rotated) crop box onto the upright point-sized rect.
        context.scaleBy(x: CGFloat(width) / upright.width, y: CGFloat(height) / upright.height)
        context.concatenate(page.getDrawingTransform(.cropBox, rect: CGRect(origin: .zero, size: upright), rotate: 0, preserveAspectRatio: true))
        context.clip(to: box)
        context.drawPDFPage(page)
        guard let image = context.makeImage() else { throw PDFPageRasterizerError.renderFailed }
        return image
    }

    private func openDocument(_ url: URL) throws -> CGPDFDocument {
        guard let document = CGPDFDocument(url as CFURL) else { throw PDFPageRasterizerError.unreadable }
        if document.isEncrypted, !document.isUnlocked, !document.unlockWithPassword("") {
            throw PDFPageRasterizerError.passwordProtected
        }
        return document
    }
}
