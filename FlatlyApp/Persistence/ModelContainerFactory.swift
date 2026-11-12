import Foundation
import SwiftData

/// Builds the app's `ModelContainer`. Only `Persistence/` touches SwiftData.
enum ModelContainerFactory {
    static let schema = Schema([Folder.self, ScanDocument.self, ScanPage.self])

    /// Persistent on-disk store in the app's default location.
    static func makePersistent() throws -> ModelContainer {
        let configuration = ModelConfiguration("Flatly", schema: schema, isStoredInMemoryOnly: false, allowsSave: true, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    /// In-memory store for previews and UI tests.
    static func makeInMemory() throws -> ModelContainer {
        let configuration = ModelConfiguration("FlatlyMemory", schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
