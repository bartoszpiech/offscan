import SwiftUI

/// A folder in the library's "Folders" section: icon, name and number of documents (not counting
/// those in Recently Deleted). Tapping it pushes the folder (`NavigationLink(value: FolderRoute(id:))`).
struct FolderRow: View {
    let folder: Folder

    var body: some View {
        let count = folder.documents.reduce(0) { $0 + ($1.deletedAt == nil ? 1 : 0) }
        NavigationLink(value: FolderRoute(id: folder.id)) {
            LibraryFolderRowLabel(systemImage: "folder.fill", title: Text(verbatim: folder.name), count: count)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(folder.name))
        .accessibilityValue(Text("\(count) documents", comment: "Number of documents in a folder"))
        .accessibilityIdentifier("library.folderRow")
    }
}
