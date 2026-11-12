import Foundation

/// Errors while reading an item picked for import.
enum ImportItemError: Error, LocalizedError {
    /// The item has no image data (e.g. an unsupported or unavailable asset).
    case unreadable

    var errorDescription: String? {
        switch self {
        case .unreadable: String(localized: "The item could not be read.")
        }
    }
}
