import SwiftUI
import UIKit
import VisionKit

/// SwiftUI wrapper of VisionKit's `VNDocumentCameraViewController`. Delivers the captured,
/// already perspective-corrected pages as upright `CGImage`s. Check `isSupported` first (the
/// simulator has no document camera).
struct DocumentCameraView: UIViewControllerRepresentable {
    let onFinish: ([CGImage]) -> Void
    let onCancel: () -> Void
    let onError: (Error) -> Void

    static var isSupported: Bool { VNDocumentCameraViewController.isSupported }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: VNDocumentCameraViewController, context: Context) {
        context.coordinator.parent = self
    }

    /// VisionKit calls the delegate on the main thread; `@preconcurrency` asserts that at runtime.
    @MainActor
    final class Coordinator: NSObject, @preconcurrency VNDocumentCameraViewControllerDelegate {
        var parent: DocumentCameraView

        init(parent: DocumentCameraView) {
            self.parent = parent
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            var images: [CGImage] = []
            images.reserveCapacity(scan.pageCount)
            for index in 0..<scan.pageCount {
                autoreleasepool {
                    if let image = scan.imageOfPage(at: index).uprightCGImage() {
                        images.append(image)
                    }
                }
            }
            parent.onFinish(images)
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            parent.onCancel()
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
            parent.onError(error)
        }
    }
}
