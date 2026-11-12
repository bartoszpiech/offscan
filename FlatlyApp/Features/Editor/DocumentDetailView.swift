import SwiftUI
import FlatlyCore

/// Shows a document's pages and all editing/export actions: page grid (tap to edit, long-press to
/// adjust edges, reorder and delete in Edit mode), add pages (camera / Photos / Files, from the
/// grid's trailing "Add Pages" tile or the More menu), Move to Folder and Export Options (More),
/// recognized
/// text, Share (one tap shares the PDF with the last export settings; long-press for the options),
/// rename and delete document (moves it to Recently Deleted). The title (tap it for Rename) is
/// the system navigation title; the page count, date and text-recognition progress are shown above
/// the page grid. A freshly scanned document shows a one-off "tap a page" hint.
struct DocumentDetailView: View {
    let document: ScanDocument

    init(document: ScanDocument) { self.document = document }

    @Environment(DocumentStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var isEditingPages = false
    @State private var editorRoute: EditorRoute?
    @State private var showExport = false
    @State private var showMoveToFolder = false
    /// Set to start the one-tap "Share PDF".
    @State private var sharePDFDocumentID: UUID?
    @State private var showText = false
    @State private var addSource: AddPagesSource?
    @State private var showRename = false
    @State private var renameText = ""
    @State private var confirmDeleteDocument = false
    @State private var pagesPendingDeletion: [ScanPage] = []
    @State private var isDeleted = false
    /// Number of times the "tap a page" hint has been shown (it stops after `editHintLimit`).
    @AppStorage("didShowEditHint") private var editHintShownCount = 0
    @State private var showEditHint = false
    @State private var didEvaluateEditHint = false

    private static let editHintLimit = 3
    /// Documents younger than this were just scanned/imported (the app pushes them right away).
    private static let editHintMaxAge: TimeInterval = 30

    var body: some View {
        if isDeleted {
            ContentUnavailableView("Document Deleted", systemImage: "trash")
        } else {
            detail(pages: document.orderedPages)
        }
    }

    private func detail(pages: [ScanPage]) -> some View {
        content(pages: pages)
            .navigationTitle(document.title)
            .navigationBarTitleDisplayMode(.inline)
            // The system truncates the title and adds the rename chevron.
            .toolbarTitleMenu { renameButton }
            .toolbar { toolbarContent(pages: pages) }
            .onAppear { evaluateEditHint(pages: pages) }
            .navigationDestination(item: $editorRoute) { route in
                pageDestination(route)
            }
            .navigationDestination(isPresented: $showText) {
                OCRTextView(document: document)
            }
            .sheet(isPresented: $showExport) {
                ExportSheet(document: document)
            }
            .sheet(isPresented: $showMoveToFolder) {
                MoveToFolderSheet(documents: [document])
            }
            .quickPDFShare(documentID: $sharePDFDocumentID)
            .fullScreenCover(item: cameraSource) { _ in
                ScanCaptureSheet(targetDocument: document) { _ in addSource = nil }
            }
            .sheet(item: importSource) { source in
                ImportFlowView(source: source == .files ? .files : .photos, targetDocument: document) { _ in addSource = nil }
            }
            .alert(Text("Rename Document"), isPresented: $showRename) {
                TextField("Title", text: $renameText)
                    .accessibilityIdentifier("document.renameField")
                Button("Cancel", role: .cancel) {}
                Button("Rename") { store.rename(document, to: renameText) }
                    .accessibilityIdentifier("document.confirmRenameButton")
            }
            .confirmationDialog(Text("Delete this document?"), isPresented: $confirmDeleteDocument, titleVisibility: .visible) {
                Button("Delete Document", role: .destructive) { deleteDocument() }
                    .accessibilityIdentifier("document.confirmDeleteButton")
            } message: {
                Text("It will be moved to Recently Deleted, where you can restore it for 30 days.")
            }
            .confirmationDialog(
                Text("Delete \(pagesPendingDeletion.count) pages?"),
                isPresented: Binding(get: { !pagesPendingDeletion.isEmpty }, set: { if !$0 { pagesPendingDeletion = [] } }),
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) { deletePendingPages() }
                    .accessibilityIdentifier("document.confirmDeletePagesButton")
            } message: {
                Text("This cannot be undone.")
            }
    }

    @ViewBuilder
    private func content(pages: [ScanPage]) -> some View {
        if pages.isEmpty {
            ContentUnavailableView {
                Label("No Pages", systemImage: "doc")
            } description: {
                Text("Scan or import pages to add them to this document.")
            } actions: {
                Menu {
                    addPagesMenuItems
                } label: {
                    Label("Add Pages", systemImage: "plus")
                        .onAccentForeground()
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("document.emptyAddPagesMenu")
            }
        } else if isEditingPages {
            PageReorderList(pages: pages) { source, destination in
                store.movePage(in: document, from: source, to: destination)
            } onDelete: { doomed in
                pagesPendingDeletion = doomed
            }
        } else {
            PageGridView(pages: pages) { page in
                openEditor(page, adjustEdges: false)
            } onAdjustEdges: { page in
                openEditor(page, adjustEdges: true)
            } onDelete: { page in
                pagesPendingDeletion = [page]
            } header: {
                DocumentSummaryHeader(
                    pageCount: pages.count,
                    createdAt: document.createdAt,
                    isRecognizingText: pages.contains { $0.ocrData == nil }
                )
            } addPagesMenuItems: {
                addPagesMenuItems
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                if showEditHint {
                    EditHintBanner {
                        withAnimation { showEditHint = false }
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
        }
    }

    /// Always the editor, even once the route's page is gone: the editor pages through the whole
    /// document, falls back to a remaining page, and pops itself when none are left.
    private func pageDestination(_ route: EditorRoute) -> some View {
        PageEditorView(document: document, pageID: route.pageID, startsWithEdgeAdjustment: route.adjustEdges)
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private func toolbarContent(pages: [ScanPage]) -> some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            if isEditingPages {
                Button("Done") {
                    withAnimation { isEditingPages = false }
                }
                .fontWeight(.semibold)
                .accessibilityIdentifier("document.doneEditingButton")
            } else {
                // A single trailing item: with a long title, iOS 26 folds extra trailing items into
                // an overflow menu, which would bury Share. Share lives in the bottom bar instead.
                Menu {
                    Menu {
                        addPagesMenuItems
                    } label: {
                        Label("Add Pages", systemImage: "plus")
                    }
                    .accessibilityIdentifier("document.addPagesMenu")
                    Divider()
                    renameButton
                    Button {
                        showMoveToFolder = true
                    } label: {
                        Label("Move to Folder…", systemImage: "folder")
                    }
                    .accessibilityIdentifier("document.moveToFolderButton")
                    Button {
                        withAnimation { isEditingPages = true }
                    } label: {
                        Label("Reorder or Delete Pages", systemImage: "arrow.up.arrow.down")
                    }
                    .disabled(pages.isEmpty)
                    .accessibilityIdentifier("document.editPagesMenuItem")
                    Button {
                        showExport = true
                    } label: {
                        Label("Export Options…", systemImage: "slider.horizontal.3")
                    }
                    .disabled(pages.isEmpty)
                    .accessibilityIdentifier("document.moreExportOptions")
                    Divider()
                    Button(role: .destructive) {
                        confirmDeleteDocument = true
                    } label: {
                        Label("Delete Document", systemImage: "trash")
                    }
                    .accessibilityIdentifier("document.deleteButton")
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
                .accessibilityIdentifier("document.moreMenu")
            }
        }
        ToolbarItemGroup(placement: .bottomBar) {
            if !pages.isEmpty && !isEditingPages {
                Button {
                    showText = true
                } label: {
                    // An explicit caption: a Label renders icon-only in the iOS 26 bottom bar.
                    HStack(spacing: 6) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .accessibilityHidden(true)
                        Text("Text")
                    }
                }
                .accessibilityIdentifier("document.textButton")

                Spacer()

                Menu {
                    Button {
                        sharePDFDocumentID = document.id
                    } label: {
                        Label("Share PDF", systemImage: "square.and.arrow.up")
                    }
                    .accessibilityIdentifier("document.sharePDF")
                    Button {
                        showExport = true
                    } label: {
                        Label("Export Options…", systemImage: "slider.horizontal.3")
                    }
                    .accessibilityIdentifier("document.exportOptions")
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "square.and.arrow.up")
                            .accessibilityHidden(true)
                        Text("Share")
                    }
                    .fontWeight(.semibold)
                } primaryAction: {
                    sharePDFDocumentID = document.id
                }
                .accessibilityLabel(Text("Share"))
                .accessibilityHint(Text("Shares a PDF with your last export settings."))
                .accessibilityIdentifier("document.exportButton")

                Spacer()

                Button("Edit") {
                    withAnimation { isEditingPages = true }
                }
                .accessibilityIdentifier("document.editButton")
            }
        }
    }

    private var renameButton: some View {
        Button {
            renameText = document.title
            showRename = true
        } label: {
            Label("Rename", systemImage: "pencil")
        }
        .accessibilityIdentifier("document.renameButton")
    }

    @ViewBuilder
    private var addPagesMenuItems: some View {
        Button {
            addSource = .camera
        } label: {
            Label("Scan with Camera", systemImage: "camera.viewfinder")
        }
        .accessibilityIdentifier("document.addFromCamera")
        Button {
            addSource = .photos
        } label: {
            Label("Import from Photos", systemImage: "photo.on.rectangle")
        }
        .accessibilityIdentifier("document.addFromPhotos")
        Button {
            addSource = .files
        } label: {
            Label("Import from Files", systemImage: "doc.badge.plus")
        }
        .accessibilityIdentifier("document.addFromFiles")
    }

    // MARK: Presentation bindings

    private var cameraSource: Binding<AddPagesSource?> {
        Binding(get: { addSource == .camera ? .camera : nil }, set: { addSource = $0 })
    }

    private var importSource: Binding<AddPagesSource?> {
        Binding(get: { addSource == .camera ? nil : addSource }, set: { addSource = $0 })
    }

    // MARK: Actions

    private func openEditor(_ page: ScanPage, adjustEdges: Bool) {
        showEditHint = false   // the user found out how it works
        editorRoute = EditorRoute(pageID: page.id, adjustEdges: adjustEdges)
    }

    /// Decides once per appearance of this screen whether to show the "tap a page" hint: only for a
    /// document that was just created by a scan or import, and only the first few times overall.
    private func evaluateEditHint(pages: [ScanPage]) {
        guard !didEvaluateEditHint else { return }
        didEvaluateEditHint = true
        let isFresh = Date.now.timeIntervalSince(document.createdAt) < Self.editHintMaxAge
        guard isFresh, !pages.isEmpty, editHintShownCount < Self.editHintLimit else { return }
        editHintShownCount += 1
        showEditHint = true
    }

    private func deletePendingPages() {
        let doomed = pagesPendingDeletion
        pagesPendingDeletion = []
        Haptics.warning()
        store.deletePages(doomed)
        if document.pages.isEmpty { isEditingPages = false }
    }

    /// Pops first, then moves the document to Recently Deleted, so this screen never shows a
    /// document that has left the library.
    private func deleteDocument() {
        let doomed = document
        let store = store
        Haptics.warning()
        // Now, while this screen is front-most and no export can be running: no exported copy of
        // the deleted document may outlive it.
        ExportService.discardTemporaryFiles()
        isDeleted = true
        dismiss()
        Task {
            try? await Task.sleep(for: .milliseconds(500))
            store.moveToRecentlyDeleted([doomed])
        }
    }
}
