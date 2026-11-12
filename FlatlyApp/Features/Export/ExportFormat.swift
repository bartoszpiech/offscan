import Foundation

/// File format offered by the export sheet.
enum ExportFormat: String, CaseIterable, Identifiable {
    /// Searchable PDF (invisible OCR text layer).
    case pdf
    /// One JPEG per page.
    case jpg

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .pdf: String(localized: "PDF", comment: "Export format")
        case .jpg: String(localized: "JPG", comment: "Export format")
        }
    }
}
