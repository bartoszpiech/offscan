import Foundation

/// Where new pages for an existing document come from.
enum AddPagesSource: String, Identifiable, Hashable {
    case camera, photos, files

    var id: String { rawValue }
}
