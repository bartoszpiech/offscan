import Foundation

/// Full-screen capture flows started from the library.
enum LibraryCaptureFlow: String, Identifiable {
    case camera, photos, files

    var id: String { rawValue }
}
