import SwiftUI
import FlatlyCore

/// Apple's scanner path of `ScanCaptureSheet` (also used when the device has no camera, where it
/// shows `CameraUnavailableView` with the debug sample page).
///
/// Presents the VisionKit document camera, processes the captured pages and appends them to
/// `targetDocument` (or creates a new document when nil). Calls `onFinished` with the resulting
/// document, or nil when cancelled.
///
/// Pages are rendered with the default filter from `@AppStorage("defaultFilter")` (a `ScanFilter`
/// raw value, `.color` when unset). OCR is started afterwards in an unstructured task and keeps
/// running after the sheet is dismissed.
///
/// While pages are processed, Stop keeps the pages finished so far (the page in progress
/// finishes) and drops the rest.
struct VisionKitCaptureFlow: View {
    let targetDocument: ScanDocument?
    let onFinished: (ScanDocument?) -> Void

    @Environment(AppServices.self) private var services
    @AppStorage("defaultFilter") private var defaultFilterRaw: String = ScanFilter.color.rawValue
    /// 1-based index of the page being processed and the page count; nil while capturing.
    @State private var progress: (current: Int, total: Int)?
    /// The batch being processed, so Stop can empty it. Holds only the queue, never the image array.
    @State private var activeQueue: CapturedImageQueue?
    /// Stop was tapped; the current page is finishing.
    @State private var isStopping = false
    @State private var alert: CaptureAlert?
    @State private var isFinished = false

    init(targetDocument: ScanDocument? = nil, onFinished: @escaping (ScanDocument?) -> Void) {
        self.targetDocument = targetDocument
        self.onFinished = onFinished
    }

    var body: some View {
        ZStack { content }
            .interactiveDismissDisabled(progress != nil)
            .onDisappear {
                // Dismissed by the presenter without a result (e.g. swipe-down): report cancellation.
                // Pages still being processed are inserted anyway; their task ignores this.
                finish(nil)
            }
            .alert(
                alert?.title ?? "",
                isPresented: Binding(get: { alert != nil }, set: { if !$0 { dismissAlert() } }),
                presenting: alert
            ) { _ in
                Button("OK") { dismissAlert() }
                    .accessibilityIdentifier("scan.alert.ok")
            } message: { alert in
                Text(alert.message)
            }
    }

    @ViewBuilder
    private var content: some View {
        if let progress {
            CaptureProgressView(
                title: isStopping ? Text("Saving pages…") : Text("Processing page \(progress.current) of \(progress.total)…"),
                fraction: Double(progress.current - 1) / Double(max(progress.total, 1)),
                onStop: progress.total > 1 && !isStopping ? { stopProcessing() } : nil
            )
        } else if DocumentCameraView.isSupported {
            DocumentCameraView(
                onFinish: { images in process(images) },
                onCancel: { finish(nil) },
                onError: { error in
                    alert = CaptureAlert(
                        title: String(localized: "Camera Error"),
                        message: error.localizedDescription,
                        result: nil
                    )
                }
            )
            .ignoresSafeArea()
            .accessibilityIdentifier("scan.camera")
        } else {
            CameraUnavailableView(onClose: { finish(nil) }, onUseSample: sampleAction)
        }
    }

    private var sampleAction: (() -> Void)? {
        #if DEBUG
        guard SampleScanPage.isEnabled else { return nil }
        return {
            if let image = SampleScanPage.make() { process([image]) }
        }
        #else
        return nil
        #endif
    }

    // MARK: Processing

    private func process(_ images: [CGImage]) {
        guard !images.isEmpty else {
            finish(nil)
            return
        }
        // The task below must capture only the queue, never `images`: see `CapturedImageQueue`.
        let queue = CapturedImageQueue(images)
        activeQueue = queue
        let total = queue.count
        let recipe = PageRenderRecipe(filter: ScanFilter(rawValue: defaultFilterRaw) ?? .color)
        let processor = services.processor
        let assembler = services.assembler
        let target = targetDocument
        progress = (1, total)

        Task {
            var prepared: [ScanProcessor.PreparedPage] = []
            var failures = 0
            var lastError: Error?
            var index = 0
            while let image = queue.next() {
                index += 1
                progress = (index, total)
                do {
                    prepared.append(try await processor.preparePage(correctedImage: image, recipe: recipe))
                } catch {
                    failures += 1
                    lastError = error
                }
            }

            activeQueue = nil
            var document: ScanDocument?
            if !prepared.isEmpty {
                let result = assembler.append(prepared, to: target)
                document = result.document
                let pages = result.pages
                // Unstructured, utility priority: OCR keeps running after this sheet is dismissed
                // without competing with the UI.
                Task(priority: .utility) { @MainActor in await assembler.recognizePendingText(forPageIDs: pages.map(\.id)) }
            }

            if failures > 0 {
                progress = nil
                let message = prepared.isEmpty
                    ? (lastError?.localizedDescription ?? String(localized: "The scanned pages could not be saved."))
                    // Only the pages attempted before a Stop count.
                    : String(localized: "\(failures) of \(index) pages could not be saved.")
                alert = CaptureAlert(title: String(localized: "Scan Failed"), message: message, result: document)
            } else {
                if document != nil { Haptics.success() }
                finish(document)
            }
        }
    }

    /// Keeps the pages processed so far: the page in progress finishes, the rest are dropped.
    private func stopProcessing() {
        isStopping = true
        activeQueue?.discardRemaining()
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
        onFinished(document)
    }
}
