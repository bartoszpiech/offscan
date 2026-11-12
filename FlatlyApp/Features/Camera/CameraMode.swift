import Foundation

/// Which camera "Scan" opens (`@AppStorage("cameraMode")`).
enum CameraMode: String, CaseIterable, Sendable {
    /// Offscan's own camera: keeps the full photo as the page's source, so edges can be re-adjusted
    /// any number of times, inward or outward.
    case flatly
    /// Apple's VisionKit document scanner: delivers pages already cropped.
    case apple

    var displayName: String {
        switch self {
        case .flatly: String(localized: "Offscan Camera")
        case .apple: String(localized: "Apple Document Scanner")
        }
    }

    /// One line on what the option means for the user, shown as the row's subtitle in Settings'
    /// Advanced section.
    var summary: String {
        switch self {
        case .flatly: String(localized: "Recommended. Keeps the whole photo, so you can adjust the edges again any time.")
        case .apple: String(localized: "Crops each page right away. Later you can only crop it smaller, not wider.")
        }
    }
}
