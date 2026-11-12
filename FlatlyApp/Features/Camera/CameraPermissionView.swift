import SwiftUI
import UIKit

/// Shown when camera access was denied or is restricted: explains why it's needed and links to
/// Offscan's page in the Settings app.
struct CameraPermissionView: View {
    let onClose: () -> Void

    @Environment(\.openURL) private var openURL

    var body: some View {
        ContentUnavailableView {
            Label("Camera Access Needed", systemImage: "camera.fill")
        } description: {
            Text("Offscan needs the camera to scan documents. Allow camera access for Offscan in Settings. Photos never leave your device.")
        } actions: {
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            } label: {
                Text("Open Settings")
                    .onAccentForeground()
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("camera.openSettings")
            Button("Close", action: onClose)
                .accessibilityIdentifier("scan.close")
        }
        .accessibilityIdentifier("camera.permissionDenied")
    }
}
