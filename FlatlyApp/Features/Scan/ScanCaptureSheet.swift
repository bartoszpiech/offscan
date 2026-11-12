import SwiftUI

/// The "Scan" entry point: opens the camera chosen in Settings (`@AppStorage("cameraMode")`) and
/// appends the scanned pages to `targetDocument` (or a new document when nil). Calls `onFinished`
/// with the resulting document, or nil when cancelled.
///
/// - `flatly` (default): `CameraCaptureFlow`, which keeps each full photo as the page's source.
/// - `apple`: `VisionKitCaptureFlow`, Apple's document scanner.
/// Devices without a camera (the simulator) always get the VisionKit flow, which shows
/// `CameraUnavailableView` and the debug "Use Sample Page" path used by UI tests. In DEBUG builds
/// with the demo library (`FLATLY_DEMO_DATA=1`) the Offscan camera runs on a demo still instead
/// (`DemoCameraFeed`; `CameraController.isCameraAvailable` is then true).
struct ScanCaptureSheet: View {
    let targetDocument: ScanDocument?
    let onFinished: (ScanDocument?) -> Void

    @AppStorage("cameraMode") private var cameraMode: CameraMode = .flatly
    /// Chosen once, so changing the setting mid-scan can't swap the flow.
    @State private var mode: CameraMode?

    init(targetDocument: ScanDocument? = nil, onFinished: @escaping (ScanDocument?) -> Void) {
        self.targetDocument = targetDocument
        self.onFinished = onFinished
    }

    var body: some View {
        switch mode ?? cameraMode {
        case .flatly where CameraController.isCameraAvailable:
            CameraCaptureFlow(targetDocument: targetDocument, onFinished: onFinished)
                .onAppear { mode = .flatly }
        default:
            VisionKitCaptureFlow(targetDocument: targetDocument, onFinished: onFinished)
                .onAppear { mode = .apple }
        }
    }
}
