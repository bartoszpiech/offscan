import Foundation

/// Errors of Offscan's camera.
enum CameraError: Error, LocalizedError {
    /// There is no back wide-angle camera.
    case unavailable
    /// The capture session refused the camera input or an output.
    case configurationFailed
    /// A photo was requested while the session wasn't running.
    case notRunning
    /// The capture finished without image data.
    case noPhotoData

    var errorDescription: String? {
        switch self {
        case .unavailable, .configurationFailed: String(localized: "The camera could not be started.")
        case .notRunning, .noPhotoData: String(localized: "The photo could not be taken.")
        }
    }
}
