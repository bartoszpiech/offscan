import Foundation

/// Selected IDs in the order they were selected; the library's Merge appends documents to the
/// first one selected, in this order, and the library numbers the selected cards in this order
/// (`position(of:)`).
public struct OrderedSelection<ID: Hashable & Sendable>: Sendable, Equatable {
    /// The selected IDs, first selected first.
    public private(set) var ids: [ID]

    /// A selection of `ids` (duplicates removed, keeping each first occurrence).
    public init(_ ids: [ID] = []) {
        var seen = Set<ID>()
        self.ids = ids.filter { seen.insert($0).inserted }
    }

    /// Number of selected IDs.
    public var count: Int { ids.count }
    /// True when nothing is selected.
    public var isEmpty: Bool { ids.isEmpty }
    /// The ID selected first.
    public var first: ID? { ids.first }

    /// Whether `id` is selected.
    public func contains(_ id: ID) -> Bool { ids.contains(id) }

    /// 1-based position of `id` in selection order (1 = selected first, the document Merge keeps),
    /// or nil when not selected.
    public func position(of id: ID) -> Int? { ids.firstIndex(of: id).map { $0 + 1 } }

    /// Selects `id` (at the end) or, when it is selected, deselects it.
    public mutating func toggle(_ id: ID) {
        if let index = ids.firstIndex(of: id) {
            ids.remove(at: index)
        } else {
            ids.append(id)
        }
    }

    /// Appends the IDs of `newIDs` not selected yet, in the given order ("Select All").
    public mutating func select(_ newIDs: [ID]) {
        var present = Set(ids)
        for id in newIDs where present.insert(id).inserted { ids.append(id) }
    }

    /// Drops IDs not in `allowed` (e.g. documents no longer visible), keeping the order.
    public mutating func retain(only allowed: Set<ID>) {
        ids.removeAll { !allowed.contains($0) }
    }

    /// Deselects everything.
    public mutating func removeAll() {
        ids.removeAll()
    }
}
