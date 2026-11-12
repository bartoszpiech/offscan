import AVFoundation
import SwiftUI
import UIKit

/// Hosts an `AVCaptureVideoPreviewLayer` (`.resizeAspectFill`) for `session`, rotated to the
/// interface orientation. Reports orientation changes through `onOrientationChange` so photos and
/// live detection use the same orientation as the preview.
struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession
    /// Changes when the session (re)starts, so the preview connection's rotation is re-applied.
    let isRunning: Bool
    let onOrientationChange: (CameraOrientation) -> Void

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.backgroundColor = .black
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        view.onOrientationChange = onOrientationChange
        return view
    }

    func updateUIView(_ view: PreviewView, context: Context) {
        view.onOrientationChange = onOrientationChange
        view.applyOrientation()
    }

    /// A view whose backing layer is the preview layer, so it always matches the view's bounds.
    final class PreviewView: UIView {
        var onOrientationChange: ((CameraOrientation) -> Void)?
        private var reportedOrientation: CameraOrientation?

        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

        var previewLayer: AVCaptureVideoPreviewLayer {
            // `layerClass` guarantees the type.
            layer as! AVCaptureVideoPreviewLayer
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            applyOrientation()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            applyOrientation()
        }

        /// Rotates the preview to the window scene's interface orientation and reports changes.
        func applyOrientation() {
            guard let interfaceOrientation = window?.windowScene?.interfaceOrientation else { return }
            let orientation = CameraOrientation(interfaceOrientation)
            if let connection = previewLayer.connection,
               connection.isVideoRotationAngleSupported(orientation.rotationAngle),
               connection.videoRotationAngle != orientation.rotationAngle {
                connection.videoRotationAngle = orientation.rotationAngle
            }
            if orientation != reportedOrientation {
                reportedOrientation = orientation
                // Deferred: this can run inside a SwiftUI update, which must not change state.
                let report = onOrientationChange
                Task { @MainActor in report?(orientation) }
            }
        }
    }
}
