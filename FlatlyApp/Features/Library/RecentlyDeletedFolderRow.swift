import SwiftUI

/// The last row of the library's "Folders" section while anything is in Recently Deleted: trash
/// icon, "Recently Deleted" and the number of deleted documents. Tapping it pushes
/// `RecentlyDeletedView` (`NavigationLink(value: RecentlyDeletedRoute())`).
struct RecentlyDeletedFolderRow: View {
    @Environment(DocumentStore.self) private var store

    var body: some View {
        let count = store.recentlyDeleted.count
        NavigationLink(value: RecentlyDeletedRoute()) {
            LibraryFolderRowLabel(systemImage: "trash", title: Text("Recently Deleted"), count: count)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Recently Deleted"))
        .accessibilityValue(Text("\(count) documents", comment: "Number of documents in a folder"))
        .accessibilityIdentifier("library.recentlyDeletedRow")
    }
}
