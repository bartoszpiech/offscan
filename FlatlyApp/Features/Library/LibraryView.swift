import SwiftUI
import FlatlyCore

/// The document library: the root view (`folder == nil`: a "Recent" strip across all folders once
/// something is filed, then folders + unfiled documents) or the contents of one folder. Searching
/// looks through the titles and OCR text of all documents. The empty states offer the imports
/// (the root one also states the privacy promise).
///
/// Deleting a document (context menu or Select mode) moves it to Recently Deleted, where it can be
/// restored for 30 days; while anything is there, the root's Folders section ends with a Recently
/// Deleted row (`RecentlyDeletedFolderRow`).
///
/// Select mode (toolbar "Select") turns the cards into toggles and shows a labelled bottom bar
/// (icon over caption): Share (one PDF share sheet with every selected document), Move (to a
/// folder), Merge (from two documents: pages appended to the first selected document, in selection
/// order) and Delete in red at the far end. Selected cards are numbered in selection order; Merge
/// appends in that order. Recent and Folders hide while selecting.
struct LibraryView: View {
    let folder: Folder?

    @Environment(DocumentStore.self) private var store
    @Environment(AppRouter.self) private var router
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var recentCardWidth: CGFloat = 120
    private static let matcher = SearchMatcher()
    @Environment(QuickActionInbox.self) private var quickActions
    @Environment(AppLockManager.self) private var lock
    @AppStorage("librarySort") private var sort: SortOption = .dateModifiedDescending

    @State private var query = ""
    /// The search field is active (focused or showing a query). Observed, never set from code.
    @State private var isSearchPresented = false
    @State private var captureFlow: LibraryCaptureFlow?
    @State private var sheet: LibrarySheet?
    /// Document to open once the capture cover has finished dismissing.
    @State private var pendingDocumentID: UUID?
    @State private var textPrompt: LibraryTextPrompt?
    @State private var promptText = ""
    @State private var documentPendingDeletion: ScanDocument?
    @State private var folderPendingDeletion: Folder?
    /// Set to start the one-tap "Share PDF".
    @State private var sharePDFDocumentID: UUID?
    @State private var isSelecting = false
    /// Selected documents, in the order they were selected (Merge appends in this order).
    @State private var selection = OrderedSelection<UUID>()
    /// Set to share the selected documents' PDFs in one share sheet.
    @State private var shareDocumentIDs: [UUID] = []
    @State private var isConfirmingMerge = false
    @State private var isConfirmingBulkDelete = false

    init(folder: Folder?) {
        self.folder = folder
    }

    var body: some View {
        // Ranked once per pass: both the grid and the selection clean-up need it.
        let documents = visibleDocuments
        withDialogs(base(documents))
            .onChange(of: quickActions.pending, initial: true) { _, _ in handleQuickAction() }
            .onChange(of: lock.isLocked) { _, _ in handleQuickAction() }
            .onChange(of: documents.map(\.id)) { _, ids in
                // A search never leaves hidden documents selected.
                selection.retain(only: Set(ids))
                if ids.isEmpty { endSelection() }
            }
    }

    private func base(_ documents: [ScanDocument]) -> some View {
        content(documents)
            .navigationTitle(isSelecting ? selectionTitle : Text(verbatim: folder?.name ?? "Offscan"))
            .searchable(text: $query, isPresented: $isSearchPresented, prompt: Text("Search titles and text"))
            .task(id: isSearchPresented) {
                // Normalise the library's text in the background as soon as the field opens, so the
                // first keystroke doesn't do it on the main thread.
                if isSearchPresented { await store.warmSearch() }
            }
            .toolbar { toolbarContent(hasDocuments: !documents.isEmpty) }
            // Scanning is irrelevant while searching, and the pill would cover results.
            .safeAreaInset(edge: .bottom) {
                if !(isSearching || isSearchPresented || isSelecting) { scanButton }
            }
            .quickPDFShare(documentID: $sharePDFDocumentID)
            .quickPDFShare(documentIDs: $shareDocumentIDs)
            .fullScreenCover(item: $captureFlow, onDismiss: openPendingDocument) { flow in
                captureView(for: flow)
            }
            .sheet(item: $sheet) { sheet in
                switch sheet {
                case .settings: SettingsView()
                case .moveToFolder(let documents): MoveToFolderSheet(documents: documents, onMoved: { endSelection() })
                }
            }
    }

    private func withDialogs(_ content: some View) -> some View {
        content
            .alert(textPrompt?.title ?? Text(verbatim: ""), isPresented: isPresented($textPrompt)) {
                TextField(textPrompt?.placeholder ?? "", text: $promptText)
                Button("Cancel", role: .cancel) { textPrompt = nil }
                Button(textPrompt?.confirmTitle ?? "OK") { commitTextPrompt() }
            }
            .confirmationDialog(
                deleteDocumentTitle,
                isPresented: isPresented($documentPendingDeletion),
                titleVisibility: .visible,
                presenting: documentPendingDeletion
            ) { document in
                Button("Delete Document", role: .destructive) {
                    Haptics.warning()
                    store.moveToRecentlyDeleted([document])
                    // No exported copy of a deleted document may outlive it in the temporary folder.
                    ExportService.discardTemporaryFiles()
                }
                Button("Cancel", role: .cancel) {}
            } message: { _ in
                Text("It will be moved to Recently Deleted, where you can restore it for 30 days.")
            }
            .confirmationDialog(
                deleteFolderTitle,
                isPresented: isPresented($folderPendingDeletion),
                titleVisibility: .visible,
                presenting: folderPendingDeletion
            ) { folder in
                Button("Delete Folder", role: .destructive) { store.delete(folder) }
                Button("Cancel", role: .cancel) {}
            } message: { _ in
                Text("Documents inside will be kept.")
            }
    }

    // MARK: Content

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var isSearching: Bool { !trimmedQuery.isEmpty }

    private var visibleDocuments: [ScanDocument] {
        // An active search looks through every document, regardless of the current folder.
        store.documents(in: folder, includeAll: isSearching, query: trimmedQuery, sort: sort)
    }

    /// Shown while there are folders or deleted documents (the section's last row opens Recently
    /// Deleted). Hidden while selecting too: folders can't be selected, and the grid should head
    /// the screen.
    private var showsFolders: Bool {
        folder == nil && !isSearching && !isSelecting && (!store.folders.isEmpty || !store.recentlyDeleted.isEmpty)
    }

    private static let recentLimit = 6

    /// Only once something is filed: otherwise the root grid already lists every document.
    private var showsRecent: Bool {
        folder == nil && !isSearching && !isSelecting && store.documents.contains { $0.folder != nil }
    }

    /// The most recently modified documents across all folders (always by modification date,
    /// whatever the sort picker says).
    private var recentDocuments: [ScanDocument] {
        Array(store.documents.sorted { $0.modifiedAt > $1.modifiedAt }.prefix(Self.recentLimit))
    }

    @ViewBuilder
    private func content(_ documents: [ScanDocument]) -> some View {
        if isSearching && documents.isEmpty {
            ContentUnavailableView.search(text: trimmedQuery)
        } else if documents.isEmpty && !showsFolders {
            emptyState
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if isSearching {
                        sectionHeader(Text("\(documents.count) results across all folders", comment: "Library search header: number of matching documents; search always covers every folder"))
                            .accessibilityIdentifier("library.searchScopeCaption")
                    }
                    if showsRecent {
                        recentSection
                    }
                    if showsFolders {
                        foldersSection
                    }
                    if !documents.isEmpty {
                        documentsSection(documents)
                    }
                }
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 16)
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        Group {
            if folder == nil {
                ContentUnavailableView {
                    Label("No scans yet", systemImage: "doc.viewfinder")
                } description: {
                    Text("Scan a document or import a photo to get started.")
                } actions: {
                    emptyStateActions(showsPrivacyNote: true)
                }
            } else {
                ContentUnavailableView {
                    Label("This folder is empty", systemImage: "folder")
                } description: {
                    Text("Scan or import a document here, or move one in from the library.")
                } actions: {
                    // `finishCapture` files the import into this folder.
                    emptyStateActions(showsPrivacyNote: false)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("library.emptyState")
    }

    /// Import buttons under the empty state; the floating Scan pill stays the primary action.
    @ViewBuilder
    private func emptyStateActions(showsPrivacyNote: Bool) -> some View {
        VStack(spacing: 12) {
            Button {
                captureFlow = .photos
            } label: {
                Label("Import from Photos", systemImage: "photo.on.rectangle")
            }
            .accessibilityIdentifier("library.empty.importPhotos")
            Button {
                captureFlow = .files
            } label: {
                Label("Import from Files", systemImage: "doc.badge.plus")
            }
            .accessibilityIdentifier("library.empty.importFiles")
            if showsPrivacyNote {
                Label("Scans are processed and stored on your device. No account, no ads, no tracking.", systemImage: "lock.shield")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)
                    .accessibilityIdentifier("library.empty.privacyNote")
            }
        }
        .buttonStyle(.bordered)
    }

    /// Horizontal strip of the most recently modified documents across all folders, with the
    /// folder each one is in. Cards scroll to the screen edge (shadows aren't clipped). Each card is
    /// laid out at its own height (fixedSize) so the extra folder line never shrinks a thumbnail;
    /// a plain HStack, as there are at most `recentLimit` cards. Recent titles get one more line
    /// than grid titles because the cards are narrower.
    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(Text("Recent"))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 16) {
                    ForEach(recentDocuments, id: \.id) { document in
                        DocumentCard(
                            document: document,
                            date: document.modifiedAt,
                            folderName: document.folder?.name,
                            accessibilityID: "library.recentCard",
                            extraTitleLines: 1
                        )
                        .frame(width: recentCardWidth)
                        .fixedSize(horizontal: false, vertical: true)
                        .contextMenu { documentMenu(for: document) }
                    }
                }
                .padding(.vertical, 4)
            }
            .scrollClipDisabled()
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("library.recentSection")
    }

    private var foldersSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(Text("Folders"))
            VStack(spacing: 0) {
                ForEach(Array(store.folders.enumerated()), id: \.element.id) { offset, folder in
                    if offset > 0 {
                        Divider().padding(.leading, 56)
                    }
                    FolderRow(folder: folder)
                        .contextMenu { folderMenu(for: folder) }
                }
                if !store.recentlyDeleted.isEmpty {
                    if !store.folders.isEmpty {
                        Divider().padding(.leading, 56)
                    }
                    RecentlyDeletedFolderRow()
                }
            }
            .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    /// The grid of document cards, or while searching a list of result rows.
    private func documentsSection(_ documents: [ScanDocument]) -> some View {
        let searchQuery = isSearching ? Self.matcher.prepare(query: trimmedQuery) : nil
        return VStack(alignment: .leading, spacing: 8) {
            if showsFolders {
                sectionHeader(Text("Documents"))
            }
            if let searchQuery {
                searchResults(documents, query: searchQuery)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: minimumCardWidth), spacing: 16, alignment: .top)], spacing: 20) {
                    ForEach(documents, id: \.id) { document in
                        DocumentCard(
                            document: document,
                            date: sort == .dateCreatedDescending ? document.createdAt : document.modifiedAt,
                            selectionState: isSelecting ? selection.contains(document.id) : nil,
                            selectionNumber: isSelecting ? selection.position(of: document.id) : nil,
                            onToggleSelection: { selection.toggle(document.id) }
                        )
                        .contextMenu {
                            if !isSelecting { documentMenu(for: document) }
                        }
                    }
                }
            }
        }
    }

    /// Search results as list rows showing where the query was found. The snippet is computed only
    /// for rows on screen (lazy stack) and cached by the store per query and page text, so body
    /// passes don't re-normalise.
    private func searchResults(_ documents: [ScanDocument], query: SearchMatcher.PreparedQuery) -> some View {
        LazyVStack(spacing: 0) {
            ForEach(Array(documents.enumerated()), id: \.element.id) { offset, document in
                if offset > 0 {
                    Divider().padding(.leading, 16)
                }
                SearchResultRow(
                    document: document,
                    date: sort == .dateCreatedDescending ? document.createdAt : document.modifiedAt,
                    match: store.searchMatch(for: document, query: query),
                    selectionState: isSelecting ? selection.contains(document.id) : nil,
                    selectionNumber: isSelecting ? selection.position(of: document.id) : nil,
                    onToggleSelection: { selection.toggle(document.id) }
                )
                .contextMenu {
                    if !isSelecting { documentMenu(for: document) }
                }
            }
        }
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    /// Titles need the width at accessibility sizes: one column on every iPhone in portrait (like
    /// the page grid), two or more on iPad and in landscape. Unchanged up to xxxLarge.
    private var minimumCardWidth: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? 300 : 150
    }

    private func sectionHeader(_ title: Text) -> some View {
        title
            .font(.headline)
            .accessibilityAddTraits(.isHeader)
    }

    // MARK: Menus

    @ViewBuilder
    private func documentMenu(for document: ScanDocument) -> some View {
        Button {
            showPrompt(.renameDocument(document))
        } label: {
            Label("Rename", systemImage: "pencil")
        }
        Button {
            sheet = .moveToFolder([document])
        } label: {
            Label("Move to Folder…", systemImage: "folder")
        }
        Button {
            sharePDFDocumentID = document.id
        } label: {
            Label("Share PDF", systemImage: "square.and.arrow.up")
        }
        .disabled(document.pages.isEmpty)
        .accessibilityIdentifier("library.sharePDF")
        Divider()
        Button(role: .destructive) {
            documentPendingDeletion = document
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    @ViewBuilder
    private func folderMenu(for folder: Folder) -> some View {
        Button {
            showPrompt(.renameFolder(folder))
        } label: {
            Label("Rename", systemImage: "pencil")
        }
        Button(role: .destructive) {
            folderPendingDeletion = folder
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    /// `hasDocuments`: anything is listed (Select and Sort are disabled on an empty library, an
    /// empty folder or a search without results).
    @ToolbarContentBuilder
    private func toolbarContent(hasDocuments: Bool) -> some ToolbarContent {
        if isSelecting {
            selectionToolbar
        } else {
            browsingToolbar(hasDocuments: hasDocuments)
        }
    }

    @ToolbarContentBuilder
    private var selectionToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button(allVisibleSelected ? "Deselect All" : "Select All") {
                if allVisibleSelected {
                    selection.removeAll()
                } else {
                    selection.select(visibleDocuments.map(\.id))
                }
            }
            .accessibilityIdentifier("library.selectAll")
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button("Done") { endSelection() }
                .fontWeight(.semibold)
                .accessibilityIdentifier("library.selectDone")
        }
        // Icon over caption (`SelectionBarLabel`); the full action names are the VoiceOver labels
        // and, at large text sizes, the Large Content Viewer.
        ToolbarItemGroup(placement: .bottomBar) {
            Button {
                shareDocumentIDs = selection.ids
                endSelection()
            } label: {
                SelectionBarLabel(title: Text("Share"), systemImage: "square.and.arrow.up")
            }
            .accessibilityLabel(Text("Share PDF"))
            .accessibilityShowsLargeContentViewer {
                Label("Share PDF", systemImage: "square.and.arrow.up")
            }
            .disabled(!selectedDocuments.contains { !$0.pages.isEmpty })
            .accessibilityIdentifier("library.bulk.share")
            Spacer()
            Button {
                sheet = .moveToFolder(selectedDocuments)
            } label: {
                SelectionBarLabel(
                    title: Text("Move", comment: "Library Select-mode bottom bar caption: moves the selected documents to a folder"),
                    systemImage: "folder"
                )
            }
            .accessibilityLabel(Text("Move to Folder…"))
            .accessibilityShowsLargeContentViewer {
                Label("Move to Folder…", systemImage: "folder")
            }
            .disabled(selection.isEmpty)
            .accessibilityIdentifier("library.bulk.move")
            Spacer()
            Button {
                isConfirmingMerge = true
            } label: {
                // SF Symbols' merge glyph; the caption explains it.
                SelectionBarLabel(title: Text("Merge"), systemImage: "arrow.triangle.merge")
            }
            .accessibilityShowsLargeContentViewer {
                Label("Merge", systemImage: "arrow.triangle.merge")
            }
            .disabled(selection.count < 2)
            .accessibilityIdentifier("library.bulk.merge")
            // Last, after .disabled (the dialog's buttons must not inherit it). iOS 26 anchors the
            // dialog's popover to the view it is attached to: this button.
            .confirmationDialog(
                Text("Merge \(selection.count) documents?"),
                isPresented: $isConfirmingMerge,
                titleVisibility: .visible
            ) {
                Button("Merge Documents") { mergeSelection() }
                    .accessibilityIdentifier("library.confirmMerge")
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("The pages will be added to “\(selectedDocuments.first?.title ?? "")” in the order you selected the documents, and the other documents will be removed.")
            }
            Spacer()
            Button(role: .destructive) {
                isConfirmingBulkDelete = true
            } label: {
                SelectionBarLabel(title: Text("Delete"), systemImage: "trash")
            }
            .tint(.red)
            .accessibilityShowsLargeContentViewer {
                Label("Delete", systemImage: "trash")
            }
            .disabled(selection.isEmpty)
            .accessibilityIdentifier("library.bulk.delete")
            // Anchored to the trash button, like Merge's.
            .confirmationDialog(
                Text("Delete \(selection.count) documents?"),
                isPresented: $isConfirmingBulkDelete,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) { deleteSelection() }
                    .accessibilityIdentifier("library.confirmBulkDelete")
                Button("Cancel", role: .cancel) {}
            } message: {
                if selection.count == 1 {
                    Text("It will be moved to Recently Deleted, where you can restore it for 30 days.")
                } else {
                    Text("They will be moved to Recently Deleted, where you can restore them for 30 days.")
                }
            }
        }
    }

    @ToolbarContentBuilder
    private func browsingToolbar(hasDocuments: Bool) -> some ToolbarContent {
        if folder == nil {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    sheet = .settings
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
                .accessibilityIdentifier("settings.button")
            }
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button("Select") {
                withAnimation { isSelecting = true }
            }
            .disabled(!hasDocuments)
            .accessibilityIdentifier("library.selectButton")

            Menu {
                Picker(selection: $sort) {
                    Text("Last modified").tag(SortOption.dateModifiedDescending)
                    Text("Date created").tag(SortOption.dateCreatedDescending)
                    Text("Title").tag(SortOption.titleAscending)
                } label: {
                    Text("Sort by")
                }
            } label: {
                Label("Sort", systemImage: "arrow.up.arrow.down")
            }
            .disabled(!hasDocuments)
            .accessibilityIdentifier("library.sortMenu")

            Menu {
                Button {
                    captureFlow = .camera
                } label: {
                    Label("Scan with Camera", systemImage: "camera.viewfinder")
                }
                .accessibilityIdentifier("library.add.scan")
                Button {
                    captureFlow = .photos
                } label: {
                    Label("Import from Photos", systemImage: "photo.on.rectangle")
                }
                .accessibilityIdentifier("library.add.photos")
                Button {
                    captureFlow = .files
                } label: {
                    Label("Import from Files", systemImage: "doc.badge.plus")
                }
                .accessibilityIdentifier("library.add.files")
                if folder == nil {
                    Divider()
                    Button {
                        showPrompt(.newFolder)
                    } label: {
                        Label("New Folder", systemImage: "folder.badge.plus")
                    }
                    .accessibilityIdentifier("library.add.newFolder")
                }
            } label: {
                Label("Add", systemImage: "plus")
            }
            .accessibilityIdentifier("library.addMenu")
        }
    }

    private var scanButton: some View {
        Button {
            captureFlow = .camera
        } label: {
            Label(scanButtonTitle, systemImage: "camera.viewfinder")
                .font(.headline)
                .onAccentForeground()
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
        .controlSize(.large)
        .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
        .padding(.bottom, 8)
        .accessibilityLabel(Text(scanButtonTitle))
        .accessibilityHint(Text("Opens the camera to scan a document"))
        .accessibilityIdentifier("library.scanButton")
    }

    /// Own key: the bare "Scan" key is the default document-title prefix (a noun), which
    /// translates differently from this verb (e.g. Polish "Skan" vs "Skanuj").
    private var scanButtonTitle: String {
        String(localized: "library.scanButton", defaultValue: "Scan", comment: "Primary button that opens the document camera")
    }

    // MARK: Capture

    @ViewBuilder
    private func captureView(for flow: LibraryCaptureFlow) -> some View {
        switch flow {
        case .camera:
            ScanCaptureSheet(targetDocument: nil) { document in finishCapture(document) }
        case .photos:
            ImportFlowView(source: .photos, targetDocument: nil) { document in finishCapture(document) }
        case .files:
            ImportFlowView(source: .files, targetDocument: nil) { document in finishCapture(document) }
        }
    }

    private func finishCapture(_ document: ScanDocument?) {
        if let document {
            if let folder, document.folder?.id != folder.id {
                store.move(document, to: folder)
            }
            pendingDocumentID = document.id
        }
        captureFlow = nil
    }

    private func openPendingDocument() {
        guard let id = pendingDocumentID else { return }
        pendingDocumentID = nil
        router.openDocument(id: id)
    }

    // MARK: Quick actions

    /// Runs a pending Home Screen quick action. Only the root library consumes it, and only while
    /// the app is unlocked: the action stays queued behind the lock screen and runs right after a
    /// successful unlock, so the camera never opens behind the lock.
    private func handleQuickAction() {
        guard folder == nil, !lock.isLocked, let action = quickActions.pending else { return }
        quickActions.pending = nil
        switch action {
        case .scan:
            if isSelecting { endSelection() }
            // Something is already presented here: leave it alone.
            guard captureFlow == nil, sheet == nil, textPrompt == nil,
                  documentPendingDeletion == nil, folderPendingDeletion == nil else { return }
            if !router.path.isEmpty {
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) { router.popToRoot() }
            }
            captureFlow = .camera
        }
    }

    // MARK: Selection

    private var selectedDocuments: [ScanDocument] {
        selection.ids.compactMap { store.document(id: $0) }
    }

    private var allVisibleSelected: Bool {
        let visible = visibleDocuments
        return !visible.isEmpty && visible.allSatisfy { selection.contains($0.id) }
    }

    private var selectionTitle: Text {
        selection.isEmpty ? Text("Select Documents") : Text("\(selection.count) Selected")
    }

    private func endSelection() {
        isSelecting = false
        selection.removeAll()
    }

    /// Appends the other selected documents' pages to the first one selected, then opens it.
    private func mergeSelection() {
        let documents = selectedDocuments
        guard documents.count >= 2 else { return }
        store.merge(Array(documents.dropFirst()), into: documents[0])
        endSelection()
        Haptics.success()
        // Exports of the merged-away documents must not outlive them.
        ExportService.discardTemporaryFiles()
        router.openDocument(id: documents[0].id)
    }

    private func deleteSelection() {
        Haptics.warning()
        store.moveToRecentlyDeleted(selectedDocuments)
        endSelection()
        // No exported copy of a deleted document may outlive it in the temporary folder.
        ExportService.discardTemporaryFiles()
    }

    // MARK: Prompts

    private func showPrompt(_ prompt: LibraryTextPrompt) {
        promptText = prompt.initialText
        textPrompt = prompt
    }

    private func commitTextPrompt() {
        guard let prompt = textPrompt else { return }
        textPrompt = nil
        let text = promptText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        switch prompt {
        case .renameDocument(let document): store.rename(document, to: text)
        case .renameFolder(let folder): store.rename(folder, to: text)
        case .newFolder: store.createFolder(name: text)
        }
    }

    private var deleteDocumentTitle: Text {
        Text("Delete “\(documentPendingDeletion?.title ?? "")”?", comment: "Confirmation title; the placeholder is the document title")
    }

    private var deleteFolderTitle: Text {
        Text("Delete folder “\(folderPendingDeletion?.name ?? "")”?", comment: "Confirmation title; the placeholder is the folder name")
    }

    /// A Bool binding that is true while `item` is non-nil and clears it when set to false.
    private func isPresented<Item>(_ item: Binding<Item?>) -> Binding<Bool> {
        Binding(
            get: { item.wrappedValue != nil },
            set: { if !$0 { item.wrappedValue = nil } }
        )
    }
}

#if DEBUG
struct LibraryView_Previews: PreviewProvider {
    static var previews: some View {
        let services = try! AppServices.makeEphemeral()
        NavigationStack {
            LibraryView(folder: nil)
        }
        .environment(services)
        .environment(services.store)
        .environment(ImageCache())
        .environment(AppRouter())
        .environment(AppLockManager())
        .environment(QuickActionInbox.shared)
    }
}
#endif
