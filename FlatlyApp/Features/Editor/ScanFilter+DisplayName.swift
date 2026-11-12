import Foundation
import FlatlyCore

extension ScanFilter {
    /// Localised name shown in the filter picker.
    var displayName: String {
        switch self {
        case .original: String(localized: "Original", comment: "Scan filter name")
        case .color: String(localized: "Color", comment: "Scan filter name")
        case .grayscale: String(localized: "Grayscale", comment: "Scan filter name")
        case .blackAndWhite: String(localized: "Black & White", comment: "Scan filter name")
        }
    }

    /// One-line description of what the filter gives (filter bar, Settings): the result, not the
    /// algorithm.
    var summary: String {
        switch self {
        case .original: String(localized: "No adjustments", comment: "Description of the Original scan filter")
        case .color: String(localized: "White paper, true colors", comment: "Description of the Color scan filter")
        case .grayscale: String(localized: "White paper, shades of gray", comment: "Description of the Grayscale scan filter")
        case .blackAndWhite: String(localized: "Crisp text, no shadows", comment: "Description of the Black & White scan filter")
        }
    }
}
