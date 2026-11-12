import SwiftUI
import Observation

/// Navigation state of the main `NavigationStack`. Injected with `.environment(router)`.
///
/// Values on the path: a document's `UUID` (→ `DocumentDetailView`), a `FolderRoute`
/// (→ `LibraryView(folder:)`) or a `RecentlyDeletedRoute` (→ `RecentlyDeletedView`). Any view in
/// the stack may push a document with `NavigationLink(value: document.id)`.
@MainActor
@Observable
final class AppRouter {
    var path = NavigationPath()

    func openDocument(id: UUID) {
        path.append(id)
    }

    func openFolder(id: UUID) {
        path.append(FolderRoute(id: id))
    }

    /// Back to the library root (e.g. for a Home Screen quick action).
    func popToRoot() {
        path = NavigationPath()
    }
}
