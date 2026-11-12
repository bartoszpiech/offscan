import Foundation
import UniformTypeIdentifiers
import FlatlyCore

/// Files picked in the document picker, opened before the review.
///
/// Each PDF is copied once into a temporary folder (inside the picker's security scope, coordinated
/// so iCloud files are downloaded) and expanded into one item per page; a multi-page TIFF becomes
/// one item per page too. Locked or corrupt PDFs are listed in `unreadableNames`. A new document is
/// named after the first picked file when it is a PDF (`suggestedTitle`). The copies are deleted
/// when the import flow ends; copies left by an interrupted import (e.g. killed mid-import) are
/// deleted at launch and at the next import (`removeLeftovers()`).
struct FileImportSelection: Sendable {
    enum Item: Sendable {
        /// An image file; `page` is the image index inside it, `pageCount` > 1 only for a multi-page TIFF.
        case image(URL, page: Int, pageCount: Int)
        /// Page `index` (0-based) of a PDF copied to `url`; `fileName` is the picked file's name.
        case pdfPage(URL, index: Int, fileName: String)
    }

    let items: [Item]
    /// Names of picked files that couldn't be opened (password-protected or corrupt PDFs).
    let unreadableNames: [String]
    /// Title for a new document: the first picked file's name when it is a PDF.
    let suggestedTitle: String?
    /// This import's folder of PDF copies; `removeTemporaryFiles()` deletes it.
    let temporaryDirectory: URL

    /// Parent of every import's temporary folder.
    static var temporaryRoot: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("FlatlyImports", isDirectory: true)
    }

    /// Deletes every import's PDF copies. Call it only when no import is running: at launch, and
    /// when a new import starts (only one import flow exists at a time).
    static func removeLeftovers() {
        try? FileManager.default.removeItem(at: temporaryRoot)
    }

    static func isPDF(_ url: URL) -> Bool {
        UTType(filenameExtension: url.pathExtension)?.conforms(to: .pdf) == true
    }

    /// True when some picked file must be opened first (a PDF or a TIFF); plain images can be
    /// reviewed right away.
    static func needsOpening(_ urls: [URL]) -> Bool {
        urls.contains { isPDF($0) || ImportItem.isTIFF($0) }
    }

    /// Opens the picked files off the main actor (see the type's documentation).
    static func prepare(_ urls: [URL]) async -> FileImportSelection {
        await Task.detached(priority: .userInitiated) { open(urls) }.value
    }

    /// Deletes this import's PDF copies.
    func removeTemporaryFiles() {
        try? FileManager.default.removeItem(at: temporaryDirectory)
    }

    private static func open(_ urls: [URL]) -> FileImportSelection {
        let fileManager = FileManager.default
        // Leftovers of an interrupted import: only one import flow exists at a time.
        removeLeftovers()
        let folder = temporaryRoot.appendingPathComponent(UUID().uuidString, isDirectory: true)
        var items: [Item] = []
        var unreadable: [String] = []
        var title: String?
        for (position, url) in urls.enumerated() {
            if isPDF(url) {
                let copy = folder.appendingPathComponent("\(position).pdf")
                do {
                    try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
                    try ImportItem.coordinatedRead(url) { try fileManager.copyItem(at: $0, to: copy) }
                    let count = try PDFPageRasterizer().pageCount(of: copy)
                    items += (0..<count).map { .pdfPage(copy, index: $0, fileName: url.lastPathComponent) }
                    if position == 0 { title = url.deletingPathExtension().lastPathComponent }
                } catch {
                    unreadable.append(url.lastPathComponent)
                    try? fileManager.removeItem(at: copy)
                }
            } else if ImportItem.isTIFF(url) {
                // An unreadable file stays one item, so staging reports it as failed.
                let count = (try? ImportItem.coordinatedRead(url) { ImageCodec().pageCount(contentsOf: $0) }) ?? 1
                if count > 1 {
                    items += (0..<count).map { .image(url, page: $0, pageCount: count) }
                } else {
                    items.append(.image(url, page: 0, pageCount: 1))
                }
            } else {
                items.append(.image(url, page: 0, pageCount: 1))
            }
        }
        return FileImportSelection(items: items, unreadableNames: unreadable, suggestedTitle: title, temporaryDirectory: folder)
    }
}
