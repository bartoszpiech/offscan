import SwiftUI
import UIKit

/// `UIActivityViewController` wrapper for sharing exported files.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [URL]
    var onComplete: (Bool) -> Void = { _ in }

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        let onComplete = onComplete
        controller.completionWithItemsHandler = { _, completed, _, _ in
            onComplete(completed)
        }
        return controller
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
