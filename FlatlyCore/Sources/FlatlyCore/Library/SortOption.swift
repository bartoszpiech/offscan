import Foundation

/// Library sort orders.
public enum SortOption: String, CaseIterable, Sendable, Codable, Hashable {
    case dateModifiedDescending
    case dateCreatedDescending
    case titleAscending
}
