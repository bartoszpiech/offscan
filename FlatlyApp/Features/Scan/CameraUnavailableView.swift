import SwiftUI

/// Shown instead of the document camera on devices without one (e.g. the simulator).
/// `onUseSample`, when set, offers a synthetic page so UI tests can exercise the scan pipeline.
struct CameraUnavailableView: View {
    let onClose: () -> Void
    var onUseSample: (() -> Void)?

    var body: some View {
        ContentUnavailableView {
            Label("Camera Not Available", systemImage: "camera.badge.ellipsis")
                // On the title, not the container: a container identifier would replace the
                // buttons' own identifiers.
                .accessibilityIdentifier("scan.unavailable")
        } description: {
            Text("This device can't scan documents with the camera. You can import photos or files instead.")
        } actions: {
            Button(action: onClose) {
                Text("Close")
                    .onAccentForeground()
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("scan.close")
            if let onUseSample {
                Button("Use Sample Page", action: onUseSample)
                    .accessibilityIdentifier("scan.useSample")
            }
        }
    }
}
