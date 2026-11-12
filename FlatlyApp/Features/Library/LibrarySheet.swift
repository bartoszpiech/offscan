import Foundation

/// Sheets presented from the library.
enum LibrarySheet: Identifiable {
    case settings
    case moveToFolder([ScanDocument])

    var id: String {
        switch self {
        case .settings: "settings"
        case .moveToFolder(let documents): "move-" + documents.map(\.id.uuidString).joined(separator: ",")
        }
    }
}
