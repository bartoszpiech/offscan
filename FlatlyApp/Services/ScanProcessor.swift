import Foundation
import CoreGraphics
import FlatlyCore

/// Drives FlatlyCore for the app off the main actor: writes page image files, renders recipes,
/// runs OCR and produces export files. It never touches SwiftData; the main-actor
/// `DocumentAssembler` turns its results into `ScanPage`s.
///
/// Declared as an actor for a single shared identity, but every operation is `nonisolated` and
/// `@concurrent`, so they run on the cooperative pool in parallel: a long export or OCR must not
/// stall thumbnail loads or filter previews. `@concurrent` keeps that true if
/// NonisolatedNonsendingByDefault / Approachable Concurrency (or Swift 7 mode) is ever enabled;
/// without it, those settings would silently move all Vision and Core Image work onto the caller's
/// actor, which is the main actor. The `#if hasAttribute(concurrent)` guard lets pre-6.2 compilers
/// (Xcode 16) build; their default `nonisolated async` semantics already run off the main actor.
/// All stored state is immutable and `Sendable`.
actor ScanProcessor {
    /// A page whose image files are on disk and which is ready to be inserted into a document.
    struct PreparedPage: Sendable, Identifiable {
        let id: UUID
        let recipe: PageRenderRecipe
        let widthPx: Int
        let heightPx: Int
        let hasSource: Bool
        let quad: Quadrilateral?
    }

    /// An imported photo that has been saved and analysed but whose corners the user may still adjust.
    struct StagedImport: Sendable, Identifiable {
        let id: UUID
        /// Downsampled (at most `previewMaxDimension`, by default `reviewMaxDimension`),
        /// orientation-normalised source image for on-screen corner adjustment.
        /// `finishImport` re-reads the stored `source` instead, so confirmed pages waiting to be
        /// corrected don't each keep a decoded photo in memory.
        let image: CGImage
        let detection: DetectedDocument
        /// The 35 mm-equivalent focal length of the full camera frame, if known (EXIF of a camera
        /// photo). Also stored in `source`, where `finishImport` / `readjustCorners` read it.
        let focalLength35mm: Double?
    }

    /// Longest side kept for imported photos (memory + speed; plenty for OCR and print).
    static let importMaxDimension = 3500
    /// Longest side of the image shown in the corner editor (import review, camera review, Adjust
    /// Edges). Quads are normalised, so this only affects on-screen sharpness; detection and
    /// correction use the stored source.
    static let reviewMaxDimension = 2000

    let imageStore: PageImageStore
    private let codec = ImageCodec()
    private let detector = DocumentDetector()
    private let corrector = PerspectiveCorrector()
    private let renderer = PageRenderer()
    private let thumbnails = ThumbnailGenerator()
    private let recognizer = TextRecognizer()
    private let transforms = ImageTransforms()
    private let rasterizer = PDFPageRasterizer()

    init(imageStore: PageImageStore) {
        self.imageStore = imageStore
    }

    // MARK: Camera

    /// Stores a camera-corrected image as a new page's `original` and renders it with `recipe`.
    #if hasAttribute(concurrent)
    @concurrent
    #endif
    nonisolated func preparePage(correctedImage: CGImage, recipe: PageRenderRecipe = .default) async throws -> PreparedPage {
        let id = UUID()
        try imageStore.write(try codec.jpegData(correctedImage, quality: 0.92), for: id, kind: .original)
        let size = try renderProcessed(pageID: id, original: correctedImage, recipe: recipe)
        return PreparedPage(id: id, recipe: recipe, widthPx: size.width, heightPx: size.height, hasSource: false, quad: nil)
    }

    // MARK: Import

    /// Decodes an imported photo, stores it as `source`, detects the document quad on the
    /// full-resolution decode and returns a downsampled copy (≤ `previewMaxDimension`) for the
    /// corner editor; the large decode is released when this returns. `index` picks the image inside
    /// the file (a page of a multi-page TIFF); 0 for photos.
    #if hasAttribute(concurrent)
    @concurrent
    #endif
    nonisolated func stageImport(imageData: Data, index: Int = 0, previewMaxDimension: Int = ScanProcessor.reviewMaxDimension) async throws -> StagedImport {
        let id = UUID()
        // Read before decoding (camera photos only; it describes the first image). Downsampling
        // keeps the frame's aspect, so `source` stays valid for it.
        let focal = index == 0 ? codec.focalLength35mm(of: imageData) : nil
        let image = try codec.decode(imageData, index: index, maxDimension: Self.importMaxDimension)
        // `source` keeps only this one EXIF tag (no GPS etc.), so later edge adjustments can use it.
        try imageStore.write(try codec.jpegData(image, quality: 0.92, focalLength35mm: focal), for: id, kind: .source)
        let detection = try detector.detect(in: image)
        let preview = try transforms.resized(image, maxDimension: previewMaxDimension)
        return StagedImport(id: id, image: preview, detection: detection, focalLength35mm: focal)
    }

    /// Applies the (possibly user-adjusted) quad to the staged import's stored `source` and renders
    /// the page. Needs a few hundred MB at full size, so callers should run one at a time.
    #if hasAttribute(concurrent)
    @concurrent
    #endif
    nonisolated func finishImport(pageID: UUID, quad: Quadrilateral, recipe: PageRenderRecipe = .default) async throws -> PreparedPage {
        let sourceData = try imageStore.read(for: pageID, kind: .source)
        let source = try codec.decode(sourceData)
        let original = try corrector.correct(source, to: quad, focalLength35mm: codec.focalLength35mm(of: sourceData))
        try imageStore.write(try codec.jpegData(original, quality: 0.92), for: pageID, kind: .original)
        let size = try renderProcessed(pageID: pageID, original: original, recipe: recipe)
        return PreparedPage(id: pageID, recipe: recipe, widthPx: size.width, heightPx: size.height, hasSource: true, quad: quad)
    }

    /// Rasterizes page `index` of the PDF at `url` (≤ `importMaxDimension`, on white, upright),
    /// stores it as a new page's `original` and renders it with `recipe`. The page has no `source`:
    /// Adjust Edges promotes `original`, as it does for Apple-scanner pages.
    #if hasAttribute(concurrent)
    @concurrent
    #endif
    nonisolated func preparePDFPage(at url: URL, index: Int, recipe: PageRenderRecipe) async throws -> PreparedPage {
        let id = UUID()
        do {
            let image = try rasterizer.render(pageAt: index, of: url, maxDimension: Self.importMaxDimension)
            try imageStore.write(try codec.jpegData(image, quality: 0.92), for: id, kind: .original)
            let size = try renderProcessed(pageID: id, original: image, recipe: recipe)
            return PreparedPage(id: id, recipe: recipe, widthPx: size.width, heightPx: size.height, hasSource: false, quad: nil)
        } catch {
            try? imageStore.delete(pageID: id)
            throw error
        }
    }

    /// Discards a staged import the user cancelled.
    #if hasAttribute(concurrent)
    @concurrent
    #endif
    nonisolated func discardStagedImport(pageID: UUID) async {
        try? imageStore.delete(pageID: pageID)
    }

    /// Re-runs perspective correction on the stored `source` with a new quad. Pages that have no
    /// source (camera scans, which VisionKit delivers already cropped) get one on first use: the
    /// current `original` is promoted to `source`, so edges can be refined repeatedly without
    /// compounding quality loss.
    #if hasAttribute(concurrent)
    @concurrent
    #endif
    nonisolated func readjustCorners(pageID: UUID, quad: Quadrilateral, recipe: PageRenderRecipe) async throws -> (width: Int, height: Int) {
        try ensureSource(pageID: pageID)
        // A source promoted from `original` has no EXIF, so it falls back to the average edges.
        let sourceData = try imageStore.read(for: pageID, kind: .source)
        let source = try codec.decode(sourceData)
        let original = try corrector.correct(source, to: quad, focalLength35mm: codec.focalLength35mm(of: sourceData))
        // An edit of an existing page: never bring back the folder of a page deleted meanwhile.
        try imageStore.write(try codec.jpegData(original, quality: 0.92), for: pageID, kind: .original, createsPageFolder: false)
        return try renderProcessed(pageID: pageID, original: original, recipe: recipe)
    }

    /// Loads the image corner adjustment should be performed on (`source`, created from
    /// `original` if missing).
    #if hasAttribute(concurrent)
    @concurrent
    #endif
    nonisolated func loadCornerAdjustSource(pageID: UUID, maxDimension: Int? = nil) async throws -> CGImage {
        try ensureSource(pageID: pageID)
        return try codec.decode(try imageStore.read(for: pageID, kind: .source), maxDimension: maxDimension)
    }

    nonisolated private func ensureSource(pageID: UUID) throws {
        guard !imageStore.exists(for: pageID, kind: .source) else { return }
        try imageStore.write(try imageStore.read(for: pageID, kind: .original), for: pageID, kind: .source, createsPageFolder: false)
    }

    // MARK: Editing

    /// Re-renders `processed` + `thumb` from `original` with a new recipe. Returns the processed size.
    #if hasAttribute(concurrent)
    @concurrent
    #endif
    nonisolated func rerender(pageID: UUID, recipe: PageRenderRecipe) async throws -> (width: Int, height: Int) {
        let original = try codec.decode(try imageStore.read(for: pageID, kind: .original))
        return try renderProcessed(pageID: pageID, original: original, recipe: recipe)
    }

    /// Runs OCR on the page's processed image.
    #if hasAttribute(concurrent)
    @concurrent
    #endif
    nonisolated func recognizeText(pageID: UUID) async throws -> OCRResult {
        let processed = try codec.decode(try imageStore.read(for: pageID, kind: .processed))
        return try recognizer.recognize(processed)
    }

    #if hasAttribute(concurrent)
    @concurrent
    #endif
    nonisolated func loadImage(pageID: UUID, kind: PageImageStore.Kind, maxDimension: Int? = nil) async throws -> CGImage {
        try codec.decode(try imageStore.read(for: pageID, kind: kind), maxDimension: maxDimension)
    }

    /// Previews a filter on a downsampled copy of the page (for the filter picker).
    #if hasAttribute(concurrent)
    @concurrent
    #endif
    nonisolated func preview(pageID: UUID, recipe: PageRenderRecipe, maxDimension: Int = 1200) async throws -> CGImage {
        let original = try codec.decode(try imageStore.read(for: pageID, kind: .original), maxDimension: maxDimension)
        return try renderer.render(original, recipe: recipe)
    }

    // MARK: Export

    /// Writes a searchable PDF to a temporary file and returns its URL. Pages are loaded,
    /// downsampled and written one at a time, so memory stays flat for long documents.
    /// A `password` encrypts the PDF (AES-128); it is used for this file only and never stored.
    /// Throws `CancellationError` (checked before every page) when the calling task is cancelled.
    #if hasAttribute(concurrent)
    @concurrent
    #endif
    nonisolated func exportPDF(
        pageIDs: [UUID],
        ocr: [UUID: OCRResult],
        pageSize: PageSizeOption,
        compression: CompressionLevel,
        title: String,
        password: String? = nil
    ) async throws -> URL {
        let directory = try Self.makeExportDirectory()
        let url = directory.appendingPathComponent(DocumentNaming.fileName(for: title, pathExtension: "pdf"))
        do {
            try PDFExporter().writePDF(
                to: url, pageCount: pageIDs.count, pageSize: pageSize, compression: compression,
                title: title, password: password
            ) { index in
                try Task.checkCancellation()
                let id = pageIDs[index]
                let image = try transforms.resized(try codec.decode(try imageStore.read(for: id, kind: .processed)), maxDimension: compression.maxPixelDimension)
                return ExportPage(image: image, ocr: ocr[id])
            }
        } catch {
            // The whole folder: no empty export folder is left behind.
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
        return url
    }

    /// Writes one JPEG per page to temporary files. Throws `CancellationError` (checked before
    /// every page) when the calling task is cancelled. On error or cancellation, nothing is left
    /// behind.
    #if hasAttribute(concurrent)
    @concurrent
    #endif
    nonisolated func exportJPEGs(pageIDs: [UUID], compression: CompressionLevel, title: String) async throws -> [URL] {
        let directory = try Self.makeExportDirectory()
        var urls: [URL] = []
        do {
            for (i, id) in pageIDs.enumerated() {
                try Task.checkCancellation()
                let image = try transforms.resized(try await loadImage(pageID: id, kind: .processed), maxDimension: compression.maxPixelDimension)
                let data = try JPEGExporter().makeJPEG(image, compression: compression)
                let name = DocumentNaming.fileName(for: title, suffix: pageIDs.count == 1 ? "" : " \(i + 1)", pathExtension: "jpg")
                let url = directory.appendingPathComponent(name)
                try data.write(to: url, options: .atomic)
                urls.append(url)
            }
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
        return urls
    }

    // MARK: Private

    /// Writes `processed` and `thumb` into the page's existing folder (every caller wrote the
    /// page's `original` first). The writes never create the folder: an edit render of a page that
    /// was deleted (and trashed) meanwhile fails instead of bringing the deleted scan's images back.
    nonisolated private func renderProcessed(pageID: UUID, original: CGImage, recipe: PageRenderRecipe) throws -> (width: Int, height: Int) {
        let processed = try renderer.render(original, recipe: recipe)
        try imageStore.write(try codec.jpegData(processed, quality: 0.9), for: pageID, kind: .processed, createsPageFolder: false)
        let thumb = try thumbnails.thumbnail(for: processed, maxDimension: 400)
        try imageStore.write(try codec.jpegData(thumb, quality: 0.8), for: pageID, kind: .thumb, createsPageFolder: false)
        return (processed.width, processed.height)
    }

    private static var exportsRoot: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("FlatlyExports", isDirectory: true)
    }

    /// A new, empty folder for one export's files. Files keep the document's name, so exports of
    /// the same document would collide in a shared folder: a cancelled export that is still
    /// finishing could replace the file the share sheet is about to send.
    private static func makeExportDirectory() throws -> URL {
        let directory = exportsRoot.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// Deletes previously exported temporary files.
    nonisolated static func cleanTemporaryExports() {
        try? FileManager.default.removeItem(at: exportsRoot)
    }

    /// Deletes the per-export folder(s) holding `urls` (one export's files). Only removes folders
    /// directly inside the exports root, so it can never touch anything else.
    nonisolated static func removeTemporaryExport(_ urls: [URL]) {
        let root = exportsRoot.standardizedFileURL.path
        for folder in Set(urls.map { $0.deletingLastPathComponent() })
        where folder.deletingLastPathComponent().standardizedFileURL.path == root {
            try? FileManager.default.removeItem(at: folder)
        }
    }
}
