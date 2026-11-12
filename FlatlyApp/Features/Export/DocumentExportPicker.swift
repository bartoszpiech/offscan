import SwiftUI
import UIKit

/// "Save to Files": `UIDocumentPickerViewController(forExporting:asCopy:)` for one or more files.
/// Keeps the files' names (e.g. "Title.pdf", "Title 1.jpg", "Title 2.jpg").
struct DocumentExportPicker: UIViewControllerRepresentable {
    let urls: [URL]
    /// Called with true when the files were saved, false when cancelled.
    let onCompletion: (Bool) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forExporting: urls, asCopy: true)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ picker: UIDocumentPickerViewController, context: Context) {
        context.coordinator.onCompletion = onCompletion
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onCompletion: onCompletion)
    }

    @MainActor
    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        var onCompletion: (Bool) -> Void

        init(onCompletion: @escaping (Bool) -> Void) {
            self.onCompletion = onCompletion
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            onCompletion(true)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onCompletion(false)
        }
    }
}
