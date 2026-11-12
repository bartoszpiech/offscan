#if DEBUG
import Foundation
import CoreGraphics
import FlatlyCore

/// Fills the library with a realistic demo library (`DemoLibraryContent`) for screenshots and
/// manual testing. Active only in DEBUG builds launched with `FLATLY_UI_TESTING=1` (in-memory
/// store, see `FlatlyApp`) **and** `FLATLY_DEMO_DATA=1`.
///
/// Pages are drawn in the app language, then go through the regular `ScanProcessor` pipeline
/// (`preparePage`, or for the photographed invoice page `finishImport` on a desk photo, so its
/// edges can be re-adjusted) and are inserted with `DocumentAssembler` / `DocumentStore`. Each
/// page's drawn text is stored as its OCR result, so search and the text view work right away.
/// All documents are inserted together once every page is ready, so the library goes from empty
/// to complete in one update.
enum DemoLibrarySeeder {
    static var isEnabled: Bool {
        let environment = ProcessInfo.processInfo.environment
        return environment["FLATLY_UI_TESTING"] == "1" && environment["FLATLY_DEMO_DATA"] == "1"
    }

    /// Preferences reset before seeding, so every screenshot run starts from the defaults.
    private static let resetDefaultsKeys = [
        "librarySort", "didShowEditHint", "savedSignature", "exportFormat", "exportPageSize",
        "exportCompression", "defaultFilter", "cameraMode", "autoCapture", "cameraFlash",
        "signatureInk",
    ]

    /// Seeds the demo library when enabled and the library (Recently Deleted included) is still empty.
    @MainActor
    static func seedIfRequested(services: AppServices) async {
        let store = services.store
        guard isEnabled, store.documents.isEmpty, store.recentlyDeleted.isEmpty, store.folders.isEmpty else { return }
        for key in resetDefaultsKeys { UserDefaults.standard.removeObject(forKey: key) }

        let now = Date.now
        let language = DemoLanguage.current
        let specs = DemoLibraryContent.documents(language: language, now: now)
        let pages = await prepare(specs, processor: services.processor, imageStore: store.imageStore)

        var folders: [DemoFolder: Folder] = [:]
        for folder in DemoFolder.allCases {
            folders[folder] = store.createFolder(name: folder.name(language))
        }
        for (spec, prepared) in zip(specs, pages) where !prepared.isEmpty {
            let document = store.createDocument(title: spec.title, folder: spec.folder.flatMap { folders[$0] })
            let inserted = services.assembler.append(prepared.map(\.page), to: document).pages
            for (page, item) in zip(inserted, prepared) {
                store.updateOCR(page, result: item.ocr)
            }
            let date = now.addingTimeInterval(-spec.age)
            store.backdate(document, createdAt: date, modifiedAt: date)
        }
    }

    // MARK: Off the main actor

    private struct PreparedDemoPage: Sendable {
        let document: Int
        let index: Int
        let page: ScanProcessor.PreparedPage
        let ocr: OCRResult
    }

    /// Renders and processes every page concurrently. Returns, per document, its pages in order
    /// (a page that failed is left out and logged).
    private static func prepare(_ specs: [DemoDocumentSpec], processor: ScanProcessor, imageStore: PageImageStore) async -> [[PreparedDemoPage]] {
        await withTaskGroup(of: PreparedDemoPage?.self) { group in
            for (documentIndex, spec) in specs.enumerated() {
                for (pageIndex, page) in spec.pages.enumerated() {
                    group.addTask {
                        await prepare(page, document: documentIndex, index: pageIndex, processor: processor, imageStore: imageStore)
                    }
                }
            }
            var result = specs.map { _ in [PreparedDemoPage]() }
            for await item in group {
                if let item { result[item.document].append(item) }
            }
            return result.map { $0.sorted { $0.index < $1.index } }
        }
    }

    private static func prepare(_ spec: DemoPageSpec, document: Int, index: Int, processor: ScanProcessor, imageStore: PageImageStore) async -> PreparedDemoPage? {
        guard let rendered = spec.render() else {
            print("[DemoLibrarySeeder] Could not draw page \(index + 1) of document \(document + 1)")
            return nil
        }
        do {
            let page: ScanProcessor.PreparedPage
            if spec.capture == .deskPhoto, let photo = DemoDeskPhoto.compose(page: rendered.image) {
                let id = UUID()
                try imageStore.write(try ImageCodec().jpegData(photo.image, quality: 0.92), for: id, kind: .source)
                page = try await processor.finishImport(pageID: id, quad: photo.quad)
            } else {
                page = try await preparePage(rendered.image, processor: processor)
            }
            return PreparedDemoPage(document: document, index: index, page: page, ocr: rendered.ocr)
        } catch {
            print("[DemoLibrarySeeder] Page \(index + 1) of document \(document + 1) failed: \(error)")
            return nil
        }
    }

    /// The default (colour) filter, falling back to no filter should Core Image fail.
    private static func preparePage(_ image: CGImage, processor: ScanProcessor) async throws -> ScanProcessor.PreparedPage {
        do {
            return try await processor.preparePage(correctedImage: image)
        } catch {
            return try await processor.preparePage(correctedImage: image, recipe: PageRenderRecipe(filter: .original))
        }
    }
}
#endif
