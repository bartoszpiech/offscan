import Foundation
import Observation
import FlatlyCore

/// Main-actor glue between `ScanProcessor` results and `DocumentStore`.
///
/// Edit renders of one page (`applyDeferringOCR`, `readjustCornersDeferringOCR`) run one after
/// another, never in parallel: an editor left with Back keeps its render going, and a re-opened
/// editor must not start a second one whose image and recipe writes could interleave with it.
/// `isRendering(pageID:)` (observable) lets that editor show its overlay meanwhile. Their image
/// writes never recreate the folder of a page deleted while it was rendering (`ScanProcessor`).
@MainActor
@Observable
final class DocumentAssembler {
    private let store: DocumentStore
    private let processor: ScanProcessor
    /// Per page, how many times its processed image was replaced this session. A recognition that
    /// started before a re-render read the old image, so its result is dropped (the re-render
    /// schedules its own). In memory only: no recognition survives a relaunch.
    @ObservationIgnored private var renderGeneration: [UUID: Int] = [:]
    /// Per page, the recognition queued by the last edit (see `scheduleOCR(forPageID:)`). In memory only.
    @ObservationIgnored private var scheduledOCR: [UUID: Task<Void, Never>] = [:]
    /// Per page, the newest edit render: the next render of that page waits for it.
    @ObservationIgnored private var lastRender: [UUID: Task<Void, Error>] = [:]
    /// Per page, edit renders waiting or running (see `isRendering(pageID:)`).
    private var renderCounts: [UUID: Int] = [:]
    /// How long an edit waits before its OCR starts, so a quick series of edits runs one recognition.
    static let editOCRDelay: Duration = .milliseconds(1500)

    init(store: DocumentStore, processor: ScanProcessor) {
        self.store = store
        self.processor = processor
    }

    /// True while an edit render of the page is waiting or running, e.g. one started by an editor
    /// the user has since left with Back. Observable, so an editor showing the page can keep its
    /// overlay up (and its tools disabled) until the render is done.
    func isRendering(pageID: UUID) -> Bool {
        renderCounts[pageID, default: 0] > 0
    }

    /// Default title for a new document, e.g. "Scan 2026-10-08 14.32".
    func defaultTitle(for date: Date = .now) -> String {
        DocumentNaming.defaultTitle(prefix: String(localized: "Scan", comment: "Prefix of the default document title"), date: date)
    }

    /// Appends prepared pages to `document`, or creates a new document when nil, titled `title`
    /// (e.g. an imported PDF's file name; blank or nil means `defaultTitle()`).
    /// Returns the document and the inserted pages.
    @discardableResult
    func append(_ prepared: [ScanProcessor.PreparedPage], to document: ScanDocument?, title: String? = nil) -> (document: ScanDocument, pages: [ScanPage]) {
        let trimmedTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let target = document ?? store.createDocument(title: trimmedTitle.isEmpty ? defaultTitle() : trimmedTitle)
        let base = target.pages.count
        let pages = prepared.enumerated().map { offset, p in
            ScanPage(id: p.id, index: base + offset, recipe: p.recipe, hasSource: p.hasSource, quad: p.quad, widthPx: p.widthPx, heightPx: p.heightPx)
        }
        // One insert and one save for the whole batch.
        return (target, store.addPages(pages, to: target))
    }

    /// Runs OCR for each page in the background and stores the results as they arrive.
    func runOCR(for pages: [ScanPage]) async {
        await runOCR(forPageIDs: pages.map(\.id))
    }

    /// Like `runOCR(forPageIDs:)`, but skips pages whose text is already there, checking right
    /// before each page, so two loops over the same pages (e.g. a new scan's OCR and an export
    /// waiting for it) don't recognise a page twice. Returns early when the task is cancelled.
    func recognizePendingText(forPageIDs ids: [UUID]) async {
        for id in ids {
            if Task.isCancelled { return }
            guard store.page(id: id)?.ocrData == nil else { continue }
            await runOCR(forPageIDs: [id])
        }
    }

    /// Recognises a page's text after an edit, coalescing quick successive edits: each call cancels
    /// the page's previous pending recognition and waits `editOCRDelay` first, so comparing filters
    /// or rotating several times recognises only the final image. Runs at utility priority so it
    /// doesn't compete with rendering, and skips the page if its text is already there (e.g. an
    /// export recognised it meanwhile).
    func scheduleOCR(forPageID id: UUID) {
        scheduledOCR[id]?.cancel()
        scheduledOCR[id] = Task(priority: .utility) { [weak self] in
            do { try await Task.sleep(for: Self.editOCRDelay) } catch { return }
            // A newer call cancels this task before replacing its entry: never remove that one.
            guard !Task.isCancelled, let self else { return }
            self.scheduledOCR[id] = nil
            // Not cancelled past this point: Vision can't be interrupted, and a result for a
            // replaced image is dropped by the `renderGeneration` check anyway.
            await self.recognizePendingText(forPageIDs: [id])
        }
    }

    /// Runs OCR for the given page ids. Pages are re-resolved by id before each write so a page
    /// (or its document) deleted while OCR is in flight is simply skipped, and so is a result for
    /// an image that was re-rendered meanwhile (see `renderGeneration`).
    func runOCR(forPageIDs ids: [UUID]) async {
        for id in ids {
            guard store.page(id: id) != nil else { continue }
            let generation = renderGeneration[id, default: 0]
            let result: OCRResult
            do {
                result = try await processor.recognizeText(pageID: id)
            } catch {
                // OCR failure is not fatal: store an empty result so the page is no longer "pending".
                result = .empty
            }
            // Several recognitions of one page can overlap (edits, startup, "Run Text Recognition Again") and they
            // finish in any order: text from a replaced image must never overwrite the current one.
            guard renderGeneration[id, default: 0] == generation, let page = store.page(id: id) else { continue }
            store.updateOCR(page, result: result)
        }
    }

    /// Applies a new recipe: re-renders the page files, stores the recipe, then re-runs OCR.
    func apply(recipe: PageRenderRecipe, to page: ScanPage) async throws {
        let id = page.id
        try await applyDeferringOCR(recipe: recipe, to: page)
        await runOCR(forPageIDs: [id])
    }

    /// Re-adjusts corners of an imported page.
    func readjustCorners(_ page: ScanPage, quad: Quadrilateral) async throws {
        let id = page.id
        try await readjustCornersDeferringOCR(page, quad: quad)
        await runOCR(forPageIDs: [id])
    }

    // MARK: Editor helpers

    /// Like `apply(recipe:to:)` but returns as soon as the page files are re-rendered and the
    /// recipe is stored, without waiting for OCR. Callers should follow up with
    /// `scheduleOCR(forPageID:)` so the text layer matches the new image. Runs after any edit
    /// render of the same page still in progress. Throws (and writes nothing) when the page's
    /// image folder is gone because the page was deleted meanwhile.
    func applyDeferringOCR(recipe: PageRenderRecipe, to page: ScanPage) async throws {
        let id = page.id
        let processor = processor
        try await serialisedRender(of: id) { [self] in
            let size = try await processor.rerender(pageID: id, recipe: recipe)
            // The page may have been deleted while rendering; never write to a stale model object.
            guard let page = store.page(id: id) else { return }
            store.updateRecipe(page, recipe: recipe, widthPx: size.width, heightPx: size.height)
            // Geometry may have changed; the old text layer no longer matches the image.
            didReplaceImage(of: page)
        }
    }

    /// Like `readjustCorners(_:quad:)` but without waiting for OCR (see `applyDeferringOCR`).
    /// New corners change the page's shape, so any crop rectangle and signature placement made for
    /// the old shape are dropped. The recipe is read when the render starts (after any earlier
    /// edit render of the page), so a filter set just before is kept.
    func readjustCornersDeferringOCR(_ page: ScanPage, quad: Quadrilateral) async throws {
        let id = page.id
        let processor = processor
        try await serialisedRender(of: id) { [self] in
            guard let current = store.page(id: id) else { return }
            var recipe = current.recipe
            recipe.cropRect = nil
            recipe.signature = nil
            let size = try await processor.readjustCorners(pageID: id, quad: quad, recipe: recipe)
            guard let page = store.page(id: id) else { return }
            store.updateQuad(page, quad: quad)
            store.updateRecipe(page, recipe: recipe, widthPx: size.width, heightPx: size.height)
            didReplaceImage(of: page)
        }
    }

    /// Runs `work` (one edit render of page `id`) after the page's previous edit render has
    /// finished, successfully or not, and counts it in `renderCounts` while it waits and runs.
    /// The task is registered before anything is awaited, so a render requested right after this
    /// one always queues behind it. The render itself is never cancelled: a caller's cancellation
    /// (Apply to All) takes effect between pages.
    private func serialisedRender(of id: UUID, _ work: @escaping @MainActor @Sendable () async throws -> Void) async throws {
        let previous = lastRender[id]
        renderCounts[id, default: 0] += 1
        let task = Task<Void, Error> {
            _ = await previous?.result
            try await work()
        }
        lastRender[id] = task
        defer {
            let left = renderCounts[id, default: 1] - 1
            renderCounts[id] = left > 0 ? left : nil
            if lastRender[id] == task { lastRender[id] = nil }
        }
        try await task.value
    }

    /// The page's processed image was just replaced: clear its text and invalidate any recognition
    /// still running on the old image.
    private func didReplaceImage(of page: ScanPage) {
        renderGeneration[page.id, default: 0] += 1
        store.clearOCR(page)
    }
}
