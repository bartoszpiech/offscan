// Stand-in for FlatlyApp/Persistence/*.swift during scripts/typecheck-app.sh.
// The SwiftData @Model macro plugin is unavailable in the Command Line Tools toolchain, so this
// file re-declares the persistence API as plain Observable classes. KEEP IN SYNC with
// FlatlyApp/Persistence/Models.swift and DocumentStore.swift (same names, properties, methods).
// It is never compiled into the app.

import Foundation
import Observation
import FlatlyCore

@Observable
final class Folder: Identifiable {
    var id: UUID
    var name: String
    var createdAt: Date
    var documents: [ScanDocument]
    init(id: UUID = UUID(), name: String, createdAt: Date = .now) {
        self.id = id; self.name = name; self.createdAt = createdAt; self.documents = []
    }
}

@Observable
final class ScanDocument: Identifiable {
    var id: UUID
    var title: String
    var createdAt: Date
    var modifiedAt: Date
    var folder: Folder?
    var pages: [ScanPage]
    var ocrText: String
    var deletedAt: Date? = nil
    init(id: UUID = UUID(), title: String, createdAt: Date = .now, folder: Folder? = nil) {
        self.id = id; self.title = title; self.createdAt = createdAt; self.modifiedAt = createdAt
        self.folder = folder; self.pages = []; self.ocrText = ""; self.deletedAt = nil
    }
    var orderedPages: [ScanPage] { pages.sorted { $0.index < $1.index } }
}

@Observable
final class ScanPage: Identifiable {
    var id: UUID
    var index: Int
    var document: ScanDocument?
    var createdAt: Date
    var recipeData: Data
    var ocrData: Data?
    var ocrText: String
    var hasSource: Bool
    var detectedQuadData: Data?
    var widthPx: Int
    var heightPx: Int
    init(id: UUID = UUID(), index: Int, createdAt: Date = .now, recipe: PageRenderRecipe = .default, hasSource: Bool = false, quad: Quadrilateral? = nil, widthPx: Int = 0, heightPx: Int = 0) {
        self.id = id; self.index = index; self.createdAt = createdAt
        self.recipeData = (try? JSONEncoder().encode(recipe)) ?? Data()
        self.ocrData = nil; self.ocrText = ""; self.hasSource = hasSource
        self.detectedQuadData = quad.flatMap { try? JSONEncoder().encode($0) }
        self.widthPx = widthPx; self.heightPx = heightPx
    }
    var recipe: PageRenderRecipe {
        get { (try? JSONDecoder().decode(PageRenderRecipe.self, from: recipeData)) ?? .default }
        set { recipeData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }
    var ocr: OCRResult? {
        get { ocrData.flatMap { try? JSONDecoder().decode(OCRResult.self, from: $0) } }
        set { ocrData = newValue.flatMap { try? JSONEncoder().encode($0) }; ocrText = newValue?.text ?? "" }
    }
    var detectedQuad: Quadrilateral? {
        get { detectedQuadData.flatMap { try? JSONDecoder().decode(Quadrilateral.self, from: $0) } }
        set { detectedQuadData = newValue.flatMap { try? JSONEncoder().encode($0) } }
    }
}

/// Opaque stand-ins for SwiftData container types.
final class ModelContainer: @unchecked Sendable {}
enum ModelContainerFactory {
    static func makePersistent() throws -> ModelContainer { ModelContainer() }
    static func makeInMemory() throws -> ModelContainer { ModelContainer() }
}

@MainActor
@Observable
final class DocumentStore {
    private(set) var documents: [ScanDocument] = []
    private(set) var folders: [Folder] = []
    private(set) var recentlyDeleted: [ScanDocument] = []
    private(set) var saveFailureNeedsAttention = false
    let imageStore: PageImageStore

    init(container: ModelContainer, imageStore: PageImageStore) { self.imageStore = imageStore }

    func refresh() {}
    func document(id: UUID) -> ScanDocument? { documents.first { $0.id == id } }
    func folder(id: UUID) -> Folder? { folders.first { $0.id == id } }
    func page(id: UUID) -> ScanPage? { nil }
    func documents(in folder: Folder?, includeAll: Bool, query: String, sort: SortOption) -> [ScanDocument] { documents }
    var allTitles: Set<String> { Set(documents.map(\.title)) }
    func pageMaintenanceSnapshot() async -> (known: Set<UUID>, pending: [UUID])? { nil }
    var hasUnsavedChanges: Bool { false }
    func warmSearch() async {}
    func searchMatch(for document: ScanDocument, query: SearchMatcher.PreparedQuery) -> SearchMatch? { nil }

    @discardableResult func createDocument(title: String, folder: Folder? = nil) -> ScanDocument { ScanDocument(title: title, folder: folder) }
    func rename(_ document: ScanDocument, to title: String) {}
    func move(_ document: ScanDocument, to folder: Folder?) {}
    func move(_ documents: [ScanDocument], to folder: Folder?) {}
    func moveToRecentlyDeleted(_ documents: [ScanDocument]) {}
    func restore(_ documents: [ScanDocument]) {}
    func deletePermanently(_ documents: [ScanDocument]) {}
    func purgeExpiredDeletions(now: Date = .now, retention: DeletionRetention = .standard) {}
    func merge(_ sources: [ScanDocument], into target: ScanDocument) {}
    #if DEBUG
    func backdate(_ document: ScanDocument, createdAt: Date, modifiedAt: Date) {}
    #endif

    @discardableResult func addPage(to document: ScanDocument, page: ScanPage) -> ScanPage { page }
    @discardableResult func addPages(_ pages: [ScanPage], to document: ScanDocument) -> [ScanPage] { pages }
    func deletePage(_ page: ScanPage) {}
    func deletePages(_ pages: [ScanPage]) {}
    func movePage(in document: ScanDocument, from source: IndexSet, to destination: Int) {}
    func updateRecipe(_ page: ScanPage, recipe: PageRenderRecipe, widthPx: Int, heightPx: Int) {}
    func updateOCR(_ page: ScanPage, result: OCRResult) {}
    func clearOCR(_ page: ScanPage) {}
    func updateQuad(_ page: ScanPage, quad: Quadrilateral) {}

    @discardableResult func createFolder(name: String) -> Folder { Folder(name: name) }
    func rename(_ folder: Folder, to name: String) {}
    func delete(_ folder: Folder) {}

    func retryFailedSave() {}
    func acknowledgeSaveFailure() { saveFailureNeedsAttention = false }
}
