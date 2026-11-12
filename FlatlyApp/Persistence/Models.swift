import Foundation
import SwiftData
import FlatlyCore

/// A folder grouping documents. Deleting a folder keeps its documents (they become unfiled).
@Model
final class Folder {
    @Attribute(.unique) var id: UUID
    var name: String
    var createdAt: Date
    @Relationship(deleteRule: .nullify, inverse: \ScanDocument.folder) var documents: [ScanDocument]

    init(id: UUID = UUID(), name: String, createdAt: Date = .now) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.documents = []
    }
}

/// A multi-page scanned document. Deleting one moves it to Recently Deleted (`deletedAt`) first;
/// `DocumentStore.deletePermanently` erases it.
@Model
final class ScanDocument {
    @Attribute(.unique) var id: UUID
    var title: String
    var createdAt: Date
    var modifiedAt: Date
    var folder: Folder?
    @Relationship(deleteRule: .cascade, inverse: \ScanPage.document) var pages: [ScanPage]
    /// Concatenated OCR text of all pages, kept in sync by `DocumentStore` for search.
    var ocrText: String
    /// When the user deleted it; nil while it is in the library. Documents with a date are listed
    /// in Recently Deleted until `DeletionRetention.standard` expires. An optional attribute, so
    /// SwiftData's lightweight migration adds it to existing stores (as nil).
    var deletedAt: Date? = nil

    init(id: UUID = UUID(), title: String, createdAt: Date = .now, folder: Folder? = nil) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.modifiedAt = createdAt
        self.folder = folder
        self.pages = []
        self.ocrText = ""
        self.deletedAt = nil
    }

    /// Pages in display order.
    var orderedPages: [ScanPage] { pages.sorted { $0.index < $1.index } }
}

/// One page of a document. Image files live in `PageImageStore` keyed by `id`.
@Model
final class ScanPage {
    @Attribute(.unique) var id: UUID
    /// Position within the document, 0-based, contiguous.
    var index: Int
    var document: ScanDocument?
    var createdAt: Date
    /// JSON-encoded `PageRenderRecipe`.
    var recipeData: Data
    /// JSON-encoded `OCRResult`, nil until OCR has run.
    var ocrData: Data?
    /// Plain OCR text (denormalised from `ocrData`).
    var ocrText: String
    /// True when `source.jpg` exists (imported photo) so corners can be re-adjusted.
    var hasSource: Bool
    /// JSON-encoded `Quadrilateral` used for the current `original.jpg` (imports only).
    var detectedQuadData: Data?
    /// Pixel size of `processed.jpg`.
    var widthPx: Int
    var heightPx: Int

    init(id: UUID = UUID(), index: Int, createdAt: Date = .now, recipe: PageRenderRecipe = .default, hasSource: Bool = false, quad: Quadrilateral? = nil, widthPx: Int = 0, heightPx: Int = 0) {
        self.id = id
        self.index = index
        self.createdAt = createdAt
        self.recipeData = (try? JSONEncoder().encode(recipe)) ?? Data()
        self.ocrData = nil
        self.ocrText = ""
        self.hasSource = hasSource
        self.detectedQuadData = quad.flatMap { try? JSONEncoder().encode($0) }
        self.widthPx = widthPx
        self.heightPx = heightPx
    }

    var recipe: PageRenderRecipe {
        get { (try? JSONDecoder().decode(PageRenderRecipe.self, from: recipeData)) ?? .default }
        set { recipeData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    var ocr: OCRResult? {
        get { ocrData.flatMap { try? JSONDecoder().decode(OCRResult.self, from: $0) } }
        set {
            ocrData = newValue.flatMap { try? JSONEncoder().encode($0) }
            ocrText = newValue?.text ?? ""
        }
    }

    var detectedQuad: Quadrilateral? {
        get { detectedQuadData.flatMap { try? JSONDecoder().decode(Quadrilateral.self, from: $0) } }
        set { detectedQuadData = newValue.flatMap { try? JSONEncoder().encode($0) } }
    }
}
