import SwiftUI
import FlatlyCore

/// Sequential corner review of pages whose full photo is already stored as `source`
/// (`ScanProcessor.stageImport`), shared by the import flow and Offscan's own camera.
///
/// Shows page after page in `CornerAdjustView` (pre-filled with the detected quad, "Page 2 of 5",
/// a hint when nothing was detected). Pages are staged lazily through `stage` and the next one is
/// prefetched while the user adjusts the current one, so at most two review-size (≤ 2000 px)
/// images are held.
/// Confirmed pages are perspective-corrected in the background one at a time from the stored
/// source (`finishImport`), so confirming quickly queues ids rather than decoded photos.
///
/// Pages `autoAccept` vouches for (camera pages whose sheet was found) are perspective-corrected
/// with their detected edges without being shown. "Use All" reuses a page that was already
/// prefetched instead of staging it again.
///
/// Pages for which `needsReview` returns false (imported PDF pages) skip the corner editor: they are
/// prepared by `prepareUnreviewed` in the same background queue, in order with the confirmed pages,
/// while "Preparing page x of y" is shown.
///
/// Every "Preparing page x of y" screen offers Cancel, including pages that are still waiting to load
/// (e.g. an iCloud photo). Its confirmation lives on the root view, so it stays up when the page
/// finishes staging and the corner editor replaces the progress screen. While the Cancel
/// confirmation is open the review does not advance (no save, no corner editor); it resumes on
/// Continue, and Discard All Pages discards everything.
///
/// When everything is reviewed the corrected pages are appended to `targetDocument` (or a new
/// document titled `newDocumentTitle`), OCR is started in an unstructured task that outlives the view, and `onComplete`
/// reports the document and the 0-based indices of pages that failed. Cancelling discards every
/// staged and corrected page this view knows about and calls `onCancel`; hosts that staged pages
/// themselves discard the rest.
struct StagedPageReview: View {
    /// A staged page's id and detected corners, for "Use All" (no image needed).
    struct DetectedPage: Sendable {
        let id: UUID
        let quad: Quadrilateral
    }

    let pageCount: Int
    let targetDocument: ScanDocument?
    /// Title of the new document when `targetDocument` is nil (nil = the default "Scan …" title).
    let newDocumentTitle: String?
    /// Loads page `index` for review. Called at most once per index, possibly ahead of time.
    /// Throwing marks the page as failed; it is skipped.
    let stage: @MainActor (Int) async throws -> ScanProcessor.StagedImport
    /// When set, the corner editor offers "Use All": the current page is accepted as outlined
    /// and every remaining page with the edges this closure returns, without showing them.
    let detectedPage: (@MainActor (Int) async throws -> DetectedPage)?
    /// When set, consulted before page `index` is staged. Returning a page accepts it with those
    /// edges without showing it. Must not stage or create files; it may be called more than once
    /// for the same index.
    let autoAccept: (@MainActor (Int) async -> DetectedPage?)?
    /// False for pages that skip the corner editor (they are never staged).
    let needsReview: @MainActor (Int) -> Bool
    /// Prepares a page that skips the review. Throwing marks the page as failed.
    let prepareUnreviewed: (@MainActor (Int) async throws -> ScanProcessor.PreparedPage)?
    /// Title of the confirmation shown when cancelling.
    let cancelTitle: Text
    /// Ask before discarding even when there is a single page.
    let alwaysConfirmCancel: Bool
    let onComplete: @MainActor (_ document: ScanDocument?, _ failedIndices: [Int]) -> Void
    let onCancel: @MainActor () -> Void

    @Environment(AppServices.self) private var services
    @AppStorage("defaultFilter") private var defaultFilterRaw: String = ScanFilter.color.rawValue

    @State private var phase: StagedPageReviewPhase = .staging(index: 0)
    @State private var didStart = false
    /// The index `show(index:)` last started on (a prefetch never stages it a second time).
    @State private var currentIndex = -1
    @State private var stagingTasks: [Int: Task<ScanProcessor.StagedImport?, Never>] = [:]
    @State private var finishTasks: [Task<ScanProcessor.PreparedPage?, Never>] = []
    @State private var failedIndices: Set<Int> = []
    @State private var isCancelDialogPresented = false
    /// Cancel was tapped on "Preparing page x of y" (a page being staged or prepared).
    @State private var isStagingCancelDialogPresented = false
    /// `show(index:)` was reached while the staging Cancel confirmation was open; resumed when it closes.
    @State private var heldIndex: Int?
    @State private var isFinished = false

    init(
        pageCount: Int,
        targetDocument: ScanDocument?,
        cancelTitle: Text,
        alwaysConfirmCancel: Bool = false,
        newDocumentTitle: String? = nil,
        stage: @escaping @MainActor (Int) async throws -> ScanProcessor.StagedImport,
        detectedPage: (@MainActor (Int) async throws -> DetectedPage)? = nil,
        autoAccept: (@MainActor (Int) async -> DetectedPage?)? = nil,
        needsReview: @escaping @MainActor (Int) -> Bool = { _ in true },
        prepareUnreviewed: (@MainActor (Int) async throws -> ScanProcessor.PreparedPage)? = nil,
        onComplete: @escaping @MainActor (_ document: ScanDocument?, _ failedIndices: [Int]) -> Void,
        onCancel: @escaping @MainActor () -> Void
    ) {
        self.pageCount = pageCount
        self.targetDocument = targetDocument
        self.cancelTitle = cancelTitle
        self.alwaysConfirmCancel = alwaysConfirmCancel
        self.newDocumentTitle = newDocumentTitle
        self.stage = stage
        self.detectedPage = detectedPage
        self.autoAccept = autoAccept
        self.needsReview = needsReview
        self.prepareUnreviewed = prepareUnreviewed
        self.onComplete = onComplete
        self.onCancel = onCancel
    }

    var body: some View {
        ZStack { content }
            // Same appearance as the corner editor, so the screen doesn't flip to light (white
            // progress screen, dark status bar) between pages while the next one is staged.
            .preferredColorScheme(.dark)
            .onAppear {
                guard !didStart else { return }
                didStart = true
                show(index: 0)
            }
            .onDisappear {
                // Dismissed by the presenter mid-review: clean up and report cancellation.
                guard !isFinished else { return }
                if case .adjusting(_, let staged) = phase { cancelAll(current: staged) } else { cancelAll(current: nil) }
            }
            // On the root, not on the progress screen: staging may finish while it is open, and the
            // phase change must not take the confirmation away.
            .confirmationDialog(cancelTitle, isPresented: $isStagingCancelDialogPresented, titleVisibility: .visible) {
                Button("Discard All Pages", role: .destructive) { discardFromStagingDialog() }
                    .accessibilityIdentifier("import.discardAll")
                Button("Continue", role: .cancel) {}
                    .accessibilityIdentifier("import.continue")
            }
            .onChange(of: isStagingCancelDialogPresented) { _, isPresented in
                // Closed with Continue (or dismissed): resume where the flow stopped. After "Discard
                // All Pages", isFinished is already set (a dialog's action runs before it dismisses),
                // so show(index:) does nothing.
                guard !isPresented, let index = heldIndex else { return }
                heldIndex = nil
                show(index: index)
            }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .staging(let index):
            CaptureProgressView(
                title: Text("Preparing page \(index + 1) of \(pageCount)…"),
                fraction: pageCount == 0 ? nil : Double(index) / Double(pageCount),
                onCancel: index < pageCount ? { requestStagingCancel() } : nil
            )
        case .adjusting(let index, let staged):
            CornerAdjustView(
                image: staged.image,
                quad: staged.detection.quad,
                onConfirm: { quad in confirm(staged, index: index, quad: quad) },
                onCancel: {
                    if pageCount > 1 || alwaysConfirmCancel { isCancelDialogPresented = true } else { cancelAll(current: staged) }
                },
                onConfirmAll: detectedPage == nil || index + 1 >= pageCount
                    ? nil
                    : { quad in useAll(staged, index: index, quad: quad) },
                onDiscard: pageCount > 1 ? { skip(staged, index: index) } : nil
            )
            .cornerAdjustCaption(
                step: pageCount > 1 ? String(localized: "Page \(index + 1) of \(pageCount)") : nil,
                hint: staged.detection.source == .fullFrame
                    ? String(localized: "No document detected — adjust the corners manually")
                    : nil
            )
            .id(staged.id)
            .confirmationDialog(cancelTitle, isPresented: $isCancelDialogPresented, titleVisibility: .visible) {
                Button("Discard All Pages", role: .destructive) { cancelAll(current: staged) }
                    .accessibilityIdentifier("import.discardAll")
                Button("Keep Editing", role: .cancel) {}
                    .accessibilityIdentifier("import.keepEditing")
            }
        case .saving:
            CaptureProgressView(title: Text("Saving pages…"))
        }
    }

    // MARK: Flow

    private var recipe: PageRenderRecipe {
        PageRenderRecipe(filter: ScanFilter(rawValue: defaultFilterRaw) ?? .color)
    }

    /// Stages page `index` (or uses its prefetched result) and shows the corner editor for it.
    private func show(index: Int) {
        guard !isFinished else { return }
        // Don't save or open the corner editor behind the Cancel confirmation: wait for the user's answer.
        if isStagingCancelDialogPresented {
            heldIndex = index
            return
        }
        guard index < pageCount else {
            complete()
            return
        }
        currentIndex = index
        phase = .staging(index: index)
        if !needsReview(index) {
            // Waiting keeps "Preparing page x of y" accurate and prepares one page at a time.
            let task = enqueueUnreviewed(index: index)
            Task {
                _ = await task.value
                show(index: index + 1)
            }
            return
        }
        Task {
            if let page = await autoAccepted(index) {
                guard !isFinished else { return }
                // Corrected with its detected edges, never shown (no image is decoded).
                enqueueFinish(pageID: page.id, index: index, quad: page.quad)
                show(index: index + 1)
                return
            }
            let staged = await stagingTask(for: index).value
            stagingTasks[index] = nil
            guard !isFinished else {
                if let staged { await services.processor.discardStagedImport(pageID: staged.id) }
                return
            }
            prefetch(index + 1)
            if let staged {
                phase = .adjusting(index: index, staged: staged)
            } else {
                show(index: index + 1)
            }
        }
    }

    private func stagingTask(for index: Int) -> Task<ScanProcessor.StagedImport?, Never> {
        if let existing = stagingTasks[index] { return existing }
        let stage = stage
        let task = Task { () -> ScanProcessor.StagedImport? in
            do {
                return try await stage(index)
            } catch {
                failedIndices.insert(index)
                return nil
            }
        }
        stagingTasks[index] = task
        return task
    }

    private func prefetch(_ index: Int) {
        guard index < pageCount, !isFinished, needsReview(index) else { return }
        guard autoAccept != nil else {
            _ = stagingTask(for: index)
            return
        }
        Task {
            // A page that will be auto-accepted is never staged. `currentIndex < index`: a prefetch
            // that resumes after `show(index:)` started on it must not stage it a second time.
            guard await autoAccepted(index) == nil, !isFinished, currentIndex < index else { return }
            _ = stagingTask(for: index)
        }
    }

    private func autoAccepted(_ index: Int) async -> DetectedPage? {
        guard let autoAccept else { return nil }
        return await autoAccept(index)
    }

    private func confirm(_ staged: ScanProcessor.StagedImport, index: Int, quad: Quadrilateral) {
        // Capture only the id: a queued page must not keep its decoded photo alive.
        enqueueFinish(pageID: staged.id, index: index, quad: quad)
        show(index: index + 1)
    }

    /// Queues the perspective correction of one page after the previously queued ones.
    private func enqueueFinish(pageID id: UUID, index: Int, quad: Quadrilateral) {
        let processor = services.processor
        let recipe = recipe
        let previous = finishTasks.last
        let task = Task { () -> ScanProcessor.PreparedPage? in
            // One page at a time: a full-size correction and render needs a few hundred MB.
            _ = await previous?.value
            do {
                try Task.checkCancellation()
                return try await processor.finishImport(pageID: id, quad: quad, recipe: recipe)
            } catch {
                if !(error is CancellationError) { failedIndices.insert(index) }
                await processor.discardStagedImport(pageID: id)
                return nil
            }
        }
        finishTasks.append(task)
    }

    /// Queues the preparation of a page that skips the review, after the previously queued pages
    /// (mirrors `enqueueFinish`). `cancelAll` and `complete` cover it through `finishTasks`.
    private func enqueueUnreviewed(index: Int) -> Task<ScanProcessor.PreparedPage?, Never> {
        let prepare = prepareUnreviewed
        let previous = finishTasks.last
        let task = Task { () -> ScanProcessor.PreparedPage? in
            _ = await previous?.value
            do {
                try Task.checkCancellation()
                guard let prepare else { throw ImportItemError.unreadable }
                return try await prepare(index)
            } catch {
                if !(error is CancellationError) { failedIndices.insert(index) }
                return nil
            }
        }
        finishTasks.append(task)
        return task
    }

    /// Cancel while a page is staged or prepared: confirm when other pages would be lost too.
    private func requestStagingCancel() {
        if pageCount > 1 || alwaysConfirmCancel {
            isStagingCancelDialogPresented = true
        } else {
            cancelAll(current: nil)
        }
    }

    /// "Discard All Pages" from the staging dialog, which stays up if the page finished staging meanwhile.
    private func discardFromStagingDialog() {
        switch phase {
        case .adjusting(_, let staged):
            cancelAll(current: staged)
        case .staging:
            cancelAll(current: nil)
        case .saving:
            // Only if SwiftUI cleared the binding (resuming a held complete()) before running this
            // action: complete() sees isFinished after its queue and deletes the pages it prepared.
            cancelAll(current: nil)
        }
    }

    /// Accepts the current page as outlined and every remaining page with its detected edges.
    private func useAll(_ staged: ScanProcessor.StagedImport, index: Int, quad: Quadrilateral) {
        guard let detectedPage else { return }
        enqueueFinish(pageID: staged.id, index: index, quad: quad)
        phase = .saving
        let processor = services.processor
        Task {
            for next in (index + 1)..<pageCount {
                guard !isFinished else { return }
                if !needsReview(next) {
                    _ = enqueueUnreviewed(index: next)
                    continue
                }
                // A prefetched page is finished from its staged files, never staged again.
                if let task = stagingTasks.removeValue(forKey: next) {
                    let staged = await task.value
                    if isFinished {
                        if let staged { await processor.discardStagedImport(pageID: staged.id) }
                        return
                    }
                    // A nil result is already in `failedIndices`.
                    if let staged { enqueueFinish(pageID: staged.id, index: next, quad: staged.detection.quad) }
                    continue
                }
                do {
                    let page = try await detectedPage(next)
                    if isFinished {
                        await processor.discardStagedImport(pageID: page.id)
                        return
                    }
                    enqueueFinish(pageID: page.id, index: next, quad: page.quad)
                } catch {
                    failedIndices.insert(next)
                }
            }
            complete()
        }
    }

    private func skip(_ staged: ScanProcessor.StagedImport, index: Int) {
        let processor = services.processor
        let id = staged.id
        Task { await processor.discardStagedImport(pageID: id) }
        show(index: index + 1)
    }

    /// Discards every staged and already-corrected page, then calls `onCancel`.
    private func cancelAll(current: ScanProcessor.StagedImport?) {
        guard !isFinished else { return }
        isFinished = true
        heldIndex = nil
        let processor = services.processor
        let imageStore = services.store.imageStore
        let currentID = current?.id
        let pending = Array(stagingTasks.values)
        let finishing = finishTasks
        stagingTasks = [:]
        finishTasks = []
        // Queued corrections that haven't started yet skip their work and discard their files.
        for task in finishing { task.cancel() }
        onCancel()
        Task.detached {
            if let currentID { await processor.discardStagedImport(pageID: currentID) }
            for task in pending {
                if let staged = await task.value { await processor.discardStagedImport(pageID: staged.id) }
            }
            for task in finishing {
                if let page = await task.value { try? imageStore.delete(pageID: page.id) }
            }
        }
    }

    /// Waits for the corrected pages, inserts them, starts OCR and reports the result.
    private func complete() {
        guard !isFinished else { return }
        // Nothing to confirm any more: the import is being saved.
        isStagingCancelDialogPresented = false
        phase = .saving
        let finishing = finishTasks
        finishTasks = []
        let assembler = services.assembler
        let imageStore = services.store.imageStore
        let target = targetDocument
        let title = newDocumentTitle
        Task {
            var prepared: [ScanProcessor.PreparedPage] = []
            for task in finishing {
                if let page = await task.value { prepared.append(page) }
            }
            if isFinished {
                // Cancelled meanwhile: cancelAll already reported it and couldn't see these (the queue was taken).
                let orphaned = prepared
                Task.detached {
                    for page in orphaned { try? imageStore.delete(pageID: page.id) }
                }
                return
            }
            var document: ScanDocument?
            if !prepared.isEmpty {
                let result = assembler.append(prepared, to: target, title: title)
                document = result.document
                let pages = result.pages
                // Unstructured, utility priority: OCR keeps running after this view is dismissed
                // without competing with the UI.
                Task(priority: .utility) { @MainActor in await assembler.recognizePendingText(forPageIDs: pages.map(\.id)) }
            }
            isFinished = true
            onComplete(document, failedIndices.sorted())
        }
    }
}
