import Foundation

/// A batch of exported temporary files to hand to the share sheet or the document picker.
struct ExportedFiles: Identifiable {
    let id = UUID()
    let urls: [URL]
}
