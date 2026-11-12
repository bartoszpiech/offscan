import Foundation
import FlatlyCore

extension PageSizeOption {
    /// Localised name shown in the export sheet.
    var displayName: String {
        switch self {
        case .a4: String(localized: "A4", comment: "PDF page size")
        case .letter: String(localized: "Letter", comment: "PDF page size")
        case .fitToContent: String(localized: "Fit to Content", comment: "PDF page size")
        }
    }
}
