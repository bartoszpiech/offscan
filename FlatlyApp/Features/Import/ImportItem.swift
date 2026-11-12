import Foundation
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
import FlatlyCore

/// One photo, image-file page or PDF page picked for import. Image data is loaded lazily, right
/// before the page is staged, so only a couple of decoded images are in memory at any time.
///
/// A multi-page TIFF becomes one item per page (`FileImportSelection`); each of them re-reads the
/// file when it is staged (at most two at once: the current page plus the prefetched one). PDF
/// pages skip the corner review (`needsReview`) and are rasterized by
/// `ScanProcessor.preparePDFPage` instead of being loaded here.
enum ImportItem {
    /// A Photos library item; `ordinal` is its 1-based position in the selection (for messages).
    case photo(PhotosPickerItem, ordinal: Int)
    /// A security-scoped file URL from the document picker. `page` is the 0-based image index
    /// inside the file; `pageCount` > 1 only for a multi-page TIFF.
    case file(URL, page: Int, pageCount: Int)
    /// Page `index` (0-based) of a picked PDF, read from its temporary copy at `url`.
    case pdfPage(URL, index: Int, fileName: String)

    /// Name shown when the item fails to import.
    var displayName: String {
        switch self {
        case .photo(_, let ordinal):
            String(localized: "Photo \(ordinal)")
        case .file(let url, let page, let pageCount):
            pageCount > 1 ? String(localized: "\(url.lastPathComponent), page \(page + 1)") : url.lastPathComponent
        case .pdfPage(_, let index, let fileName):
            String(localized: "\(fileName), page \(index + 1)")
        }
    }

    /// False for PDF pages: they are digital, so there are no edges to adjust.
    var needsReview: Bool {
        if case .pdfPage = self { return false }
        return true
    }

    /// Image index inside the loaded data (`ImageCodec.decode(_:index:maxDimension:)`).
    var imageIndex: Int {
        switch self {
        case .photo, .pdfPage: 0
        case .file(_, let page, _): page
        }
    }

    /// Loads the item's raw image data (HEIC/JPEG/PNG/TIFF…).
    func loadData() async throws -> Data {
        switch self {
        case .photo(let item, _):
            guard let data = try await item.loadTransferable(type: Data.self) else { throw ImportItemError.unreadable }
            return data
        case .file(let url, _, _):
            return try await Task.detached(priority: .userInitiated) {
                try Self.coordinatedRead(url) { try Data(contentsOf: $0) }
            }.value
        case .pdfPage:
            // Never called: PDF pages are rasterized by `ScanProcessor.preparePDFPage`.
            throw ImportItemError.unreadable
        }
    }

    /// True for TIFF files, the only kind split into pages.
    static func isTIFF(_ url: URL) -> Bool {
        UTType(filenameExtension: url.pathExtension)?.conforms(to: .tiff) == true
    }

    /// Runs `body` on a picked file with security-scoped access, coordinating so iCloud files are
    /// downloaded first.
    static func coordinatedRead<T>(_ url: URL, _ body: (URL) throws -> T) throws -> T {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        var coordinationError: NSError?
        var result: Result<T, Error> = .failure(ImportItemError.unreadable)
        NSFileCoordinator().coordinate(readingItemAt: url, options: [.withoutChanges], error: &coordinationError) { readURL in
            result = Result { try body(readURL) }
        }
        if let coordinationError { throw coordinationError }
        return try result.get()
    }
}
