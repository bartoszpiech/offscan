import SwiftUI

/// Lets the user move documents to a folder, to "No folder", or to a newly created folder.
/// The current folder is checked when every document is in it.
struct MoveToFolderSheet: View {
    let documents: [ScanDocument]
    /// Called after a move (e.g. to end the library's Select mode).
    var onMoved: () -> Void = {}

    @Environment(DocumentStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var isNamingFolder = false
    @State private var newFolderName = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    destinationRow(isCurrent: isCurrent(nil), systemImage: "tray") {
                        Text("No folder")
                    } action: {
                        move(to: nil)
                    }
                    ForEach(store.folders, id: \.id) { folder in
                        destinationRow(isCurrent: isCurrent(folder), systemImage: "folder") {
                            Text(folder.name)
                        } action: {
                            move(to: folder)
                        }
                    }
                }
                Section {
                    Button {
                        newFolderName = ""
                        isNamingFolder = true
                    } label: {
                        Label("New Folder…", systemImage: "folder.badge.plus")
                    }
                    .accessibilityIdentifier("moveToFolder.newFolder")
                }
            }
            .navigationTitle("Move to Folder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .alert("New Folder", isPresented: $isNamingFolder) {
                TextField("Folder name", text: $newFolderName)
                Button("Cancel", role: .cancel) {}
                Button("Create") { createFolderAndMove() }
            } message: {
                if documents.count == 1 {
                    Text("The document will be moved into the new folder.")
                } else {
                    Text("The selected documents will be moved into the new folder.")
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func destinationRow<Title: View>(isCurrent: Bool, systemImage: String, @ViewBuilder title: () -> Title, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Label {
                    title().foregroundStyle(.primary)
                } icon: {
                    Image(systemName: systemImage)
                }
                Spacer()
                if isCurrent {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.tint)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
        }
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }

    private func isCurrent(_ folder: Folder?) -> Bool {
        !documents.isEmpty && documents.allSatisfy { $0.folder?.id == folder?.id }
    }

    private func move(to folder: Folder?) {
        store.move(documents, to: folder)   // documents already there are left alone
        onMoved()
        dismiss()
    }

    private func createFolderAndMove() {
        let name = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        move(to: store.createFolder(name: name))
    }
}
