import SwiftUI
import FlatlyCore

/// Recently Deleted: the documents the user deleted, most recently deleted first, each with the
/// days left before it is erased (`DeletionRetention.standard`). Tapping a row offers Restore and
/// Delete Now; the bottom bar has Delete All (confirmed) and Restore All. Opened from the last row
/// of the library's Folders section (`RecentlyDeletedRoute`). Expired documents are erased when the
/// screen opens, as well as at launch.
struct RecentlyDeletedView: View {
    @Environment(DocumentStore.self) private var store
    @State private var isConfirmingDeleteAll = false

    var body: some View {
        let documents = store.recentlyDeleted
        content(documents)
            .navigationTitle(Text("Recently Deleted"))
            .toolbar { toolbarContent(count: documents.count) }
            .onAppear { store.purgeExpiredDeletions() }
    }

    @ViewBuilder
    private func content(_ documents: [ScanDocument]) -> some View {
        if documents.isEmpty {
            ContentUnavailableView {
                Label("No Deleted Documents", systemImage: "trash")
            } description: {
                Text("Deleted documents stay here for 30 days.")
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("recentlyDeleted.emptyState")
        } else {
            List {
                Section {
                    ForEach(documents, id: \.id) { document in
                        RecentlyDeletedRow(
                            document: document,
                            onRestore: { restore(id: document.id) },
                            onDeleteNow: { deleteNow(id: document.id) }
                        )
                    }
                } header: {
                    Text("Documents are erased permanently 30 days after you delete them.")
                        .textCase(nil)
                }
            }
            .listStyle(.insetGrouped)
        }
    }

    /// Only while something is listed. Both actions sit in the bottom bar (iOS 26 folds extra
    /// top-bar items into an overflow menu).
    @ToolbarContentBuilder
    private func toolbarContent(count: Int) -> some ToolbarContent {
        if count > 0 {
            ToolbarItemGroup(placement: .bottomBar) {
                Button("Delete All", role: .destructive) {
                    isConfirmingDeleteAll = true
                }
                .tint(.red)
                .accessibilityIdentifier("recentlyDeleted.deleteAll")
                // Attached to the button, so iOS 26 anchors the dialog's popover to it.
                .confirmationDialog(
                    Text("Delete \(count) documents permanently?", comment: "Recently Deleted: title of the Delete All confirmation"),
                    isPresented: $isConfirmingDeleteAll,
                    titleVisibility: .visible
                ) {
                    Button("Delete All", role: .destructive) { deleteAll() }
                        .accessibilityIdentifier("recentlyDeleted.confirmDeleteAll")
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("This cannot be undone.")
                }
                Spacer()
                Button("Restore All") { restoreAll() }
                    .accessibilityIdentifier("recentlyDeleted.restoreAll")
            }
        }
    }

    // MARK: Actions

    /// Actions look the document up again by id: it may have been erased meanwhile (e.g. expired).
    private func trashed(id: UUID) -> ScanDocument? {
        store.recentlyDeleted.first { $0.id == id }
    }

    private func restore(id: UUID) {
        guard let document = trashed(id: id) else { return }
        Haptics.success()
        store.restore([document])
    }

    private func deleteNow(id: UUID) {
        guard let document = trashed(id: id) else { return }
        Haptics.warning()
        store.deletePermanently([document])
    }

    private func restoreAll() {
        Haptics.success()
        store.restore(store.recentlyDeleted)
    }

    private func deleteAll() {
        Haptics.warning()
        store.deletePermanently(store.recentlyDeleted)
    }
}

#if DEBUG
struct RecentlyDeletedView_Previews: PreviewProvider {
    static var previews: some View {
        let services = try! AppServices.makeEphemeral()
        NavigationStack {
            RecentlyDeletedView()
        }
        .environment(services)
        .environment(services.store)
        .environment(ImageCache())
    }
}
#endif
