import Foundation
import FlatlyCore

extension CompressionLevel {
    /// Localised name shown in the export sheet (`.low` compression = best quality).
    var displayName: String {
        switch self {
        case .low: String(localized: "Best Quality", comment: "Export compression level")
        case .medium: String(localized: "Balanced", comment: "Export compression level")
        case .high: String(localized: "Smallest File", comment: "Export compression level")
        }
    }
}
