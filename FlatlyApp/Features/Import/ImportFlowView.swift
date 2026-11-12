import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import FlatlyCore

/// Picks photos (`.photos`) or files (`.files`: images or PDFs), detects the document, lets the
/// user adjust the corners, and appends the pages to `targetDocument` (or a new document when nil).
///
/// Picked PDFs are copied to a temporary folder and expanded into pages (`FileImportSelection`);
/// their pages skip the corner review and are rasterized in the background in page order
/// (filter `.original`: the scan filters would wash out digital pages). A new document created
/// from a picked PDF is named after the file.
///
/// The review itself is `StagedPageReview`: items are loaded and staged lazily (the next one is
/// prefetched while the user adjusts the current one) so at most two review-size (≤ 2000 px,
/// `ScanProcessor.reviewMaxDimension`) images are held in memory, and confirmed pages are corrected in the background one at a time. OCR starts after
/// insertion and outlives the view.
struct ImportFlowView: View {
    enum Source: Sendable { case photos, files }

    let source: Source
    let targetDocument: ScanDocument?
    let onFinished: (ScanDocument?) -> Void

    @Environment(AppServices.self) private var services

    @State private var phase: ImportPhase = .picking
    @State private var items: [ImportItem] = []
    /// Opened files (PDF copies, unreadable names), for `.files` imports that needed opening.
    @State private var selection: FileImportSelection?
    @State private var photoSelection: [PhotosPickerItem] = []
    @State private var isFileImporterPresented = false
    @State private var alert: CaptureAlert?
    @State private var isFinished = false

    init(source: Source, targetDocument: ScanDocument? = nil, onFinished: @escaping (ScanDocument?) -> Void) {
        self.source = source
        self.targetDocument = targetDocument
        self.onFinished = onFinished
    }

    var body: some View {
        ZStack { content }
            .interactiveDismissDisabled(!phase.allowsInteractiveDismiss)
            .onDisappear {
                // Dismissed by the presenter (e.g. swipe-down on the picker). A review in progress
                // discards its own pages when it disappears.
                finish(nil)
            }
            .alert(
                alert?.title ?? "",
                isPresented: Binding(get: { alert != nil }, set: { if !$0 { dismissAlert() } }),
                presenting: alert
            ) { _ in
                Button("OK") { dismissAlert() }
                    .accessibilityIdentifier("import.alert.ok")
            } message: { alert in
                Text(alert.message)
            }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .picking:
            picker
        case .opening:
            // Nothing is staged yet, so Cancel needs no confirmation; `open(_:)` deletes the copies
            // when the (possibly slow iCloud or File Provider) read returns.
            CaptureProgressView(title: Text("Opening files…"), onCancel: { finish(nil) })
        case .reviewing:
            StagedPageReview(
                pageCount: items.count,
                targetDocument: targetDocument,
                cancelTitle: Text("Cancel Import?"),
                newDocumentTitle: selection?.suggestedTitle,
                stage: { [items, processor = services.processor] index in
                    let item = items[index]
                    let data = try await item.loadData()
                    return try await processor.stageImport(imageData: data, index: item.imageIndex)
                },
                // "Use All": stage the item, keep id + quad, drop the image. Never called for PDF
                // pages, which skip the review.
                detectedPage: { [items, processor = services.processor] index in
                    let item = items[index]
                    let data = try await item.loadData()
                    let staged = try await processor.stageImport(imageData: data, index: item.imageIndex)
                    return StagedPageReview.DetectedPage(id: staged.id, quad: staged.detection.quad)
                },
                needsReview: { [items] index in items[index].needsReview },
                prepareUnreviewed: { [items, processor = services.processor] index in
                    guard case .pdfPage(let url, let page, _) = items[index] else { throw ImportItemError.unreadable }
                    // `.original`: the color, grayscale and B&W filters would wash out digital pages.
                    return try await processor.preparePDFPage(at: url, index: page, recipe: PageRenderRecipe(filter: .original))
                },
                onComplete: { document, failed in complete(document: document, failedIndices: failed) },
                onCancel: { finish(nil) }
            )
        case .done:
            CaptureProgressView(title: Text("Saving pages…"))
        }
    }

    // MARK: Picking

    @ViewBuilder
    private var picker: some View {
        switch source {
        case .photos:
            PhotoSelectionView(
                selection: $photoSelection,
                onCancel: { finish(nil) },
                onAdd: {
                    start(photoSelection.enumerated().map { ImportItem.photo($1, ordinal: $0 + 1) })
                }
            )
        case .files:
            // Fallback content behind the document picker (visible only if it was dismissed oddly).
            ContentUnavailableView {
                Label("Import Files", systemImage: "doc.badge.plus")
            } description: {
                Text("Choose images or PDFs to add as pages.")
            } actions: {
                Button {
                    isFileImporterPresented = true
                } label: {
                    Text("Choose Files")
                        .onAccentForeground()
                }
                .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("import.chooseFiles")
                Button("Cancel") { finish(nil) }
                    .accessibilityIdentifier("import.cancel")
            }
            .fileImporter(
                isPresented: $isFileImporterPresented,
                allowedContentTypes: [.image, .pdf],
                allowsMultipleSelection: true,
                onCompletion: { result in
                    switch result {
                    case .success(let urls):
                        if urls.isEmpty { finish(nil) } else { open(urls) }
                    case .failure(let error):
                        alert = CaptureAlert(title: String(localized: "Import Failed"), message: error.localizedDescription, result: nil)
                    }
                },
                onCancellation: { finish(nil) }
            )
            .onAppear { isFileImporterPresented = true }
        }
    }

    // MARK: Flow

    /// Opens picked PDFs and multi-page TIFFs first (copying and counting pages, behind a progress
    /// screen with Cancel); plain images start the review right away.
    private func open(_ urls: [URL]) {
        guard FileImportSelection.needsOpening(urls) else {
            start(urls.map { .file($0, page: 0, pageCount: 1) })
            return
        }
        phase = .opening
        Task {
            let opened = await FileImportSelection.prepare(urls)
            // Dismissed or cancelled while the files were being opened.
            guard !isFinished else {
                opened.removeTemporaryFiles()
                return
            }
            selection = opened
            let picked: [ImportItem] = opened.items.map { item in
                switch item {
                case .image(let url, let page, let pageCount): .file(url, page: page, pageCount: pageCount)
                case .pdfPage(let url, let index, let fileName): .pdfPage(url, index: index, fileName: fileName)
                }
            }
            if picked.isEmpty {
                phase = .done
                alert = CaptureAlert(
                    title: String(localized: "Some Items Couldn't Be Imported"),
                    message: Self.failureMessage(opened.unreadableNames),
                    result: nil
                )
            } else {
                start(picked)
            }
        }
    }

    private func start(_ picked: [ImportItem]) {
        // The sheet may have been dismissed while the files were being opened.
        guard !isFinished else { return }
        guard !picked.isEmpty else {
            finish(nil)
            return
        }
        items = picked
        phase = .reviewing
    }

    /// Reports the reviewed pages, listing any items that couldn't be imported.
    private func complete(document: ScanDocument?, failedIndices: [Int]) {
        phase = .done
        let failedNames = (selection?.unreadableNames ?? []) + failedIndices.map { items[$0].displayName }
        if failedNames.isEmpty {
            if document != nil { Haptics.success() }
            finish(document)
        } else {
            alert = CaptureAlert(
                title: String(localized: "Some Items Couldn't Be Imported"),
                message: Self.failureMessage(failedNames),
                result: document
            )
        }
    }

    private static func failureMessage(_ names: [String]) -> String {
        let list = names.joined(separator: "\n")
        return String(localized: "These items couldn't be read or processed:\n\(list)")
    }

    private func dismissAlert() {
        guard let current = alert else { return }
        alert = nil
        finish(current.result)
    }

    /// Calls `onFinished` exactly once.
    private func finish(_ document: ScanDocument?) {
        guard !isFinished else { return }
        isFinished = true
        // Safe even when cancelling: queued PDF pages are cancelled, and a render in progress
        // keeps its open file.
        selection?.removeTemporaryFiles()
        onFinished(document)
    }
}
