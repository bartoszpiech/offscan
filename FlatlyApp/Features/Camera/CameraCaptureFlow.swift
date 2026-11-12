import SwiftUI
import FlatlyCore

/// Offscan's camera path of `ScanCaptureSheet`: `DocumentCameraScreen` → on Done, pages whose sheet
/// was found by segmentation on the full-resolution still are corrected directly; the others (or
/// all of them with the "Review edges after scanning" setting) are reviewed in `StagedPageReview`
/// (corner editor pre-filled with the detection, "Use All" for long batches) → `finishImport` →
/// appended to `targetDocument` (or a new document), OCR in the background. Edges can still be
/// adjusted later from the document.
///
/// Photos are staged while the user keeps shooting (`CameraPageQueue`): the full photo becomes the
/// page's `source`, so its edges can be re-adjusted later in either direction.
struct CameraCaptureFlow: View {
    let targetDocument: ScanDocument?
    let onFinished: (ScanDocument?) -> Void

    private enum Phase {
        case capturing
        case reviewing(count: Int)
        case done
    }

    @Environment(AppServices.self) private var services
    /// Settings → "Review edges after scanning": show every page in the corner editor.
    @AppStorage("reviewEdgesAfterScan") private var reviewEdgesAfterScan = false
    // Evaluated on every init of this view; CameraController.init is cheap (pipeline is lazy).
    @State private var controller = CameraController()
    @State private var pages = CameraPageQueue()
    @State private var phase: Phase = .capturing
    @State private var alert: CaptureAlert?
    @State private var isFinished = false

    var body: some View {
        ZStack { content }
            .interactiveDismissDisabled()
            .onAppear {
                let pages = pages
                let processor = services.processor
                controller.onPhoto = { data in pages.add(data, processor: processor) }
                controller.onError = { error in
                    alert = CaptureAlert(title: String(localized: "Camera Error"), message: error.localizedDescription, result: nil)
                }
            }
            .onDisappear {
                // Dismissed by the presenter while capturing: drop the staged photos.
                guard !isFinished else { return }
                if case .capturing = phase {
                    // A photo still in flight would be staged after the discard and orphaned.
                    controller.onPhoto = nil
                    pages.discardAll(processor: services.processor)
                }
                finish(nil)
            }
            .alert(
                alert?.title ?? "",
                isPresented: Binding(get: { alert != nil }, set: { if !$0 { dismissAlert() } }),
                presenting: alert
            ) { _ in
                Button("OK") { dismissAlert() }
                    .accessibilityIdentifier("camera.alert.ok")
            } message: { alert in
                Text(alert.message)
            }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .capturing:
            DocumentCameraScreen(
                controller: controller,
                pages: pages,
                isAlertPresented: alert != nil,
                onCancel: {
                    // A photo still in flight would be staged after the discard and orphaned.
                    controller.onPhoto = nil
                    pages.discardAll(processor: services.processor)
                    finish(nil)
                },
                onDone: {
                    guard pages.count > 0 else { return }
                    // A photo arriving after this point would never be reviewed: drop it.
                    controller.onPhoto = nil
                    controller.stop()
                    phase = .reviewing(count: pages.count)
                },
                onDelete: { id in pages.remove(id, processor: services.processor) }
            )
        case .reviewing(let count):
            StagedPageReview(
                pageCount: count,
                targetDocument: targetDocument,
                cancelTitle: Text("Discard Scanned Pages?"),
                alwaysConfirmCancel: true,
                stage: { [pages, processor = services.processor] index in
                    guard let page = await pages.page(at: index) else { throw CameraError.noPhotoData }
                    let image = try await processor.loadImage(pageID: page.id, kind: .source, maxDimension: ScanProcessor.reviewMaxDimension)
                    // finishImport reads the focal length from the stored source itself.
                    return ScanProcessor.StagedImport(id: page.id, image: image, detection: page.detection, focalLength35mm: nil)
                },
                detectedPage: { [pages] index in
                    guard let page = await pages.page(at: index) else { throw CameraError.noPhotoData }
                    return StagedPageReview.DetectedPage(id: page.id, quad: page.detection.quad)
                },
                autoAccept: autoAccept,
                onComplete: { document, failed in complete(document: document, failedCount: failed.count, total: count) },
                onCancel: {
                    // Pages the review never reached are still on disk.
                    pages.discardAll(processor: services.processor)
                    finish(nil)
                }
            )
        case .done:
            CaptureProgressView(title: Text("Saving pages…"))
        }
    }

    /// Pages whose sheet was found by segmentation are saved without the corner review, unless the
    /// user asked to review every page. A failed staging returns nil here, so the stage path still
    /// marks it failed; rectangle-detector and full-frame pages are shown ("No document detected").
    private var autoAccept: (@MainActor (Int) async -> StagedPageReview.DetectedPage?)? {
        guard !reviewEdgesAfterScan else { return nil }
        let pages = pages
        return { @MainActor index in
            guard let page = await pages.page(at: index), page.detection.source == .segmentation else { return nil }
            return StagedPageReview.DetectedPage(id: page.id, quad: page.detection.quad)
        }
    }

    private func complete(document: ScanDocument?, failedCount: Int, total: Int) {
        phase = .done
        guard failedCount > 0 else {
            if document != nil { Haptics.success() }
            finish(document)
            return
        }
        let message = document == nil
            ? String(localized: "The scanned pages could not be saved.")
            : String(localized: "\(failedCount) of \(total) pages could not be saved.")
        alert = CaptureAlert(title: String(localized: "Scan Failed"), message: message, result: document)
    }

    private func dismissAlert() {
        guard let current = alert else { return }
        alert = nil
        // A camera error while capturing keeps the camera open; only end-of-flow alerts finish.
        if case .done = phase { finish(current.result) }
    }

    /// Calls `onFinished` exactly once.
    private func finish(_ document: ScanDocument?) {
        guard !isFinished else { return }
        isFinished = true
        onFinished(document)
    }
}
