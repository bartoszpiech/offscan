import Foundation
import SwiftData
import Observation
import FlatlyCore

/// The single mutation API for the library. Owns the `ModelContext`; views never touch SwiftData.
/// `documents` / `recentlyDeleted` / `folders` are re-fetched when documents or folders are
/// created or deleted, a document is moved to or restored from Recently Deleted, a folder is
/// renamed or a document moved; other mutations only re-sort `documents` in memory (model objects
/// are observable, so property changes reach views anyway). Multi-page changes go through
/// `addPages` / `deletePages` with a single save; image folders of deleted pages are moved to the
/// image store's trash right after the save and erased off the main actor.
/// `ScanDocument.ocrText` is rebuilt from the pages whenever page text, the set of pages or their
/// order changes.
///
/// Deleting a document moves it to Recently Deleted (`moveToRecentlyDeleted`, sets
/// `ScanDocument.deletedAt`), from where it can be restored for `DeletionRetention.standard`;
/// `deletePermanently` erases it with its pages and images, and `purgeExpiredDeletions` (run at
/// launch) erases the expired ones. Trashed documents are left out of `documents` and of every
/// lookup (`document(id:)`, `page(id:)`), so the editor, export, OCR and search never see them.
@MainActor
@Observable
final class DocumentStore {
    /// Documents in the library (not in Recently Deleted), most recently modified first.
    private(set) var documents: [ScanDocument] = []
    /// Documents in Recently Deleted (`deletedAt` set), most recently deleted first.
    private(set) var recentlyDeleted: [ScanDocument] = []
    private(set) var folders: [Folder] = []
    /// True when a save failed and the user hasn't seen it yet; RootView shows an alert. The unsaved
    /// changes stay in the context and are written by the next successful save. Raised once per run
    /// of failures, and again for every new scan or import (`createDocument`, `addPages`) that can't
    /// be saved, so new pages never look saved after the user dismissed the alert.
    private(set) var saveFailureNeedsAttention = false

    let imageStore: PageImageStore
    private let container: ModelContainer
    private let context: ModelContext
    /// Caches each document's normalised text for `documents(in:…query:…)`.
    private let search = LibrarySearch()
    /// The last save failed (its changes are still pending in the context).
    @ObservationIgnored private var lastSaveFailed = false
    /// Pages whose image folders are removed once their deletion has been saved.
    @ObservationIgnored private var pendingImageDeletions: Set<UUID> = []
    /// Merge sources whose pages were moved to the merge target. They are deleted by the first save
    /// that succeeds, which may come after a failed first save (Try Again, the background retry or
    /// any later edit), and only if they are still empty (see `deleteEmptiedMergeSources`).
    @ObservationIgnored private var pendingMergeSources: Set<UUID> = []

    init(container: ModelContainer, imageStore: PageImageStore) {
        self.container = container
        self.context = ModelContext(container)
        self.context.autosaveEnabled = false
        self.imageStore = imageStore
        refresh()
    }

    // MARK: Queries

    func refresh() {
        let docDescriptor = FetchDescriptor<ScanDocument>(sortBy: [SortDescriptor(\.modifiedAt, order: .reverse)])
        let all = (try? context.fetch(docDescriptor)) ?? []
        // Split in memory (no #Predicate).
        documents = all.filter { $0.deletedAt == nil }
        recentlyDeleted = all
            .filter { $0.deletedAt != nil }
            .sorted { ($0.deletedAt ?? .distantPast) > ($1.deletedAt ?? .distantPast) }
        let folderDescriptor = FetchDescriptor<Folder>(sortBy: [SortDescriptor(\.name)])
        folders = (try? context.fetch(folderDescriptor)) ?? []
    }

    /// A document in the library; nil once it was deleted (also while it is in Recently Deleted).
    func document(id: UUID) -> ScanDocument? { documents.first { $0.id == id } }
    func folder(id: UUID) -> Folder? { folders.first { $0.id == id } }
    /// Looks a page up by id across the library's documents; nil once the page or its document was
    /// deleted (also while the document is in Recently Deleted).
    func page(id: UUID) -> ScanPage? {
        for doc in documents { if let page = doc.pages.first(where: { $0.id == id }) { return page } }
        return nil
    }

    /// Documents in `folder` (nil = unfiled / all when `includeAll`), filtered by `query`, sorted by `sort`.
    /// A non-blank `query` ranks by relevance instead of `sort` (see `LibrarySearch`).
    func documents(in folder: Folder?, includeAll: Bool, query: String, sort: SortOption) -> [ScanDocument] {
        var result = documents.filter { includeAll || $0.folder?.id == folder?.id }
        if let ranked = search.ranked(result, query: query) { return ranked }
        switch sort {
        case .dateModifiedDescending: result.sort { $0.modifiedAt > $1.modifiedAt }
        case .dateCreatedDescending: result.sort { $0.createdAt > $1.createdAt }
        case .titleAscending: result.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        }
        return result
    }

    var allTitles: Set<String> { Set(documents.map(\.title)) }

    /// Normalises every document's search text in the background (see `LibrarySearch.warm`).
    /// Call when the search field is activated. All documents: an active search spans every folder.
    func warmSearch() async {
        await search.warm(documents)
    }

    /// Where `query` was found in `document`'s OCR text, for a search result card (cached, see
    /// `LibrarySearch.firstMatch(in:query:)`).
    func searchMatch(for document: ScanDocument, query: SearchMatcher.PreparedQuery) -> SearchMatch? {
        search.firstMatch(in: document, query: query)
    }

    /// Page ids for startup maintenance: `known` holds every page row in the store (also pages
    /// whose document link is missing, so their images are never swept), `pending` the pages of
    /// documents whose text is still pending (`ocrData == nil`), in library order (most recently
    /// modified document first, then page order).
    ///
    /// Read on a short-lived background context, so the main actor never faults in every page and
    /// its OCR JSON at launch. Nil when the fetch fails, so callers never mistake an unreadable
    /// library for an empty one (the orphan sweep must then be skipped).
    func pageMaintenanceSnapshot() async -> (known: Set<UUID>, pending: [UUID])? {
        let container = self.container
        return await Task.detached(priority: .utility) { () -> (known: Set<UUID>, pending: [UUID])? in
            let context = ModelContext(container)
            var descriptor = FetchDescriptor<ScanPage>()
            descriptor.relationshipKeyPathsForPrefetching = [\.document]
            guard let pages = try? context.fetch(descriptor) else { return nil }
            var known = Set<UUID>()
            var pending: [(modifiedAt: Date, documentID: String, index: Int, id: UUID)] = []
            for page in pages {
                known.insert(page.id)
                guard let document = page.document, page.ocrData == nil else { continue }
                pending.append((document.modifiedAt, document.id.uuidString, page.index, page.id))
            }
            pending.sort { a, b in
                if a.modifiedAt != b.modifiedAt { return a.modifiedAt > b.modifiedAt }
                if a.documentID != b.documentID { return a.documentID < b.documentID }
                return a.index < b.index
            }
            return (known, pending.map(\.id))
        }.value
    }

    /// True while the context holds changes not yet written, e.g. after a failed save (its changes
    /// stay pending until the next successful save). The startup orphan sweep must then be skipped:
    /// `pageMaintenanceSnapshot()` sees only saved rows, so unsaved pages would look like orphans.
    var hasUnsavedChanges: Bool { lastSaveFailed || context.hasChanges }

    // MARK: Documents

    @discardableResult
    func createDocument(title: String, folder: Folder? = nil) -> ScanDocument {
        let doc = ScanDocument(title: DocumentNaming.uniqueTitle(title, existing: allTitles), folder: folder)
        context.insert(doc)
        save(refetch: true, alertAgain: true)
        return doc
    }

    func rename(_ document: ScanDocument, to title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        document.title = trimmed
        touch(document)
        save()
    }

    func move(_ document: ScanDocument, to folder: Folder?) {
        move([document], to: folder)
    }

    /// Moves documents into `folder` (nil = unfiled) with one save.
    func move(_ documents: [ScanDocument], to folder: Folder?) {
        var changed = false
        for document in documents where document.folder?.id != folder?.id {
            document.folder = folder
            touch(document)
            changed = true
        }
        guard changed else { return }
        save(refetch: true)
    }

    /// Appends the pages of `sources`, in order, to `target` and deletes the emptied sources once
    /// the re-parenting is saved (after a failed save, with the next save that succeeds). Pages keep
    /// their ids, so image files and OCR stay in place.
    func merge(_ sources: [ScanDocument], into target: ScanDocument) {
        let sources = sources.filter { $0.id != target.id }
        guard !sources.isEmpty else { return }
        var ordered = target.orderedPages
        for source in sources {
            // `orderedPages` is a snapshot, so re-parenting while iterating is safe.
            for page in source.orderedPages {
                page.document = target   // SwiftData removes it from `source.pages`
                ordered.append(page)
            }
        }
        for (i, page) in ordered.enumerated() { page.index = i }
        target.ocrText = ordered.map(\.ocrText).joined(separator: "\n")
        touch(target)
        // Save the re-parenting before deleting anything: deleting a source whose pages aren't
        // saved under the target yet could cascade to them. The emptied sources are deleted by the
        // first save that succeeds (this one, or a retry after a failure; see
        // deleteEmptiedMergeSources).
        pendingMergeSources.formUnion(sources.map(\.id))
        save()
        assertContiguousIndexes(target)
    }

    #if DEBUG
    /// Demo library only (`DemoLibrarySeeder`): gives a seeded document a past creation and
    /// modification date, so the library looks like it has a history (and sorts accordingly).
    func backdate(_ document: ScanDocument, createdAt: Date, modifiedAt: Date) {
        document.createdAt = createdAt
        document.modifiedAt = modifiedAt
        save()
    }
    #endif

    // MARK: Recently Deleted

    /// Moves documents to Recently Deleted with one save: they leave `documents` (and search) and
    /// are listed in `recentlyDeleted` until restored, erased, or `DeletionRetention.standard`
    /// expires. Folder, pages, images and dates are kept, so a restored document returns as it was.
    func moveToRecentlyDeleted(_ documents: [ScanDocument]) {
        let now = Date.now
        var changed = false
        for document in documents where document.deletedAt == nil {
            document.deletedAt = now
            search.forget(document.id)
            changed = true
        }
        guard changed else { return }
        save(refetch: true)
    }

    /// Puts documents from Recently Deleted back into the library, with one save. A document whose
    /// folder was deleted meanwhile returns unfiled.
    func restore(_ documents: [ScanDocument]) {
        var changed = false
        for document in documents where document.deletedAt != nil {
            document.deletedAt = nil
            changed = true
        }
        guard changed else { return }
        save(refetch: true)
    }

    /// Erases documents with their pages, with one save. Their image folders are removed once
    /// the deletion has been saved.
    func deletePermanently(_ documents: [ScanDocument]) {
        guard !documents.isEmpty else { return }
        for document in documents {
            // Read the ids first: a deleted model must not be read after the save.
            pendingImageDeletions.formUnion(document.pages.map(\.id))
            search.forget(document.id)
            context.delete(document)
        }
        save(refetch: true)
    }

    /// Erases the documents that have been in Recently Deleted for longer than `retention`.
    /// Runs at launch (`AppServices.runStartupMaintenance`) and when Recently Deleted opens.
    func purgeExpiredDeletions(now: Date = .now, retention: DeletionRetention = .standard) {
        let expired = recentlyDeleted.filter { document in
            retention.isExpired(deletedAt: document.deletedAt ?? now, now: now)
        }
        guard !expired.isEmpty else { return }
        deletePermanently(expired)
    }

    // MARK: Pages

    /// Appends a page whose image files have already been written to `imageStore`.
    @discardableResult
    func addPage(to document: ScanDocument, page: ScanPage) -> ScanPage {
        addPages([page], to: document)
        return page
    }

    /// Appends pages whose image files are already in `imageStore`, in the given order, with one save.
    @discardableResult
    func addPages(_ pages: [ScanPage], to document: ScanDocument) -> [ScanPage] {
        guard !pages.isEmpty else { return [] }
        let base = document.pages.count
        for (offset, page) in pages.enumerated() {
            page.index = base + offset          // explicit: never read pages.count mid-batch
            context.insert(page)
            page.document = document            // SwiftData maintains the inverse `pages`
        }
        reindex(document)
        touch(document)
        save(alertAgain: true)
        assertContiguousIndexes(document)
        return pages
    }

    func deletePage(_ page: ScanPage) {
        deletePages([page])
    }

    /// Deletes pages (from any documents) with one save. Image files are trashed once the deletion
    /// has been saved and erased in the background.
    func deletePages(_ pages: [ScanPage]) {
        var seen = Set<UUID>()
        let doomed = pages.filter { $0.document != nil && seen.insert($0.id).inserted }
        guard !doomed.isEmpty else { return }
        // Collect the owners first: removing a page from `pages` clears its inverse `document`.
        var owners: [ScanDocument] = []
        for page in doomed {
            if let owner = page.document, !owners.contains(where: { $0 === owner }) { owners.append(owner) }
        }
        let ids = Set(doomed.map(\.id))
        pendingImageDeletions.formUnion(ids)
        for owner in owners { owner.pages.removeAll { ids.contains($0.id) } }
        for page in doomed { context.delete(page) }
        for owner in owners {
            reindex(owner)
            rebuildText(owner)
            touch(owner)
        }
        save()
        for owner in owners { assertContiguousIndexes(owner) }
    }

    func movePage(in document: ScanDocument, from source: IndexSet, to destination: Int) {
        var ordered = document.orderedPages
        ordered.move(fromOffsets: source, toOffset: destination)
        for (i, page) in ordered.enumerated() { page.index = i }
        rebuildText(document)
        touch(document)
        save()
    }

    func updateRecipe(_ page: ScanPage, recipe: PageRenderRecipe, widthPx: Int, heightPx: Int) {
        page.recipe = recipe
        page.widthPx = widthPx
        page.heightPx = heightPx
        if let document = page.document { touch(document) }
        save()
    }

    func updateOCR(_ page: ScanPage, result: OCRResult) {
        page.ocr = result
        if let document = page.document {
            rebuildText(document)
            touch(document)
        }
        save()
    }

    /// Marks the page's text as pending (e.g. after a re-render) so stale text is never exported
    /// and the "recognizing" indicator shows until `updateOCR` is called again.
    func clearOCR(_ page: ScanPage) {
        page.ocr = nil
        if let document = page.document {
            rebuildText(document)
        }
        save()
    }

    /// Records the quad used for the current `original`; the page now has a `source` on disk.
    func updateQuad(_ page: ScanPage, quad: Quadrilateral) {
        page.detectedQuad = quad
        page.hasSource = true
        if let document = page.document { touch(document) }
        save()
    }

    // MARK: Folders

    @discardableResult
    func createFolder(name: String) -> Folder {
        let folder = Folder(name: name.trimmingCharacters(in: .whitespacesAndNewlines))
        context.insert(folder)
        save(refetch: true)
        return folder
    }

    func rename(_ folder: Folder, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        folder.name = trimmed
        save(refetch: true)
    }

    /// Deletes the folder; its documents become unfiled.
    func delete(_ folder: Folder) {
        for doc in folder.documents { doc.folder = nil }
        context.delete(folder)
        save(refetch: true)
    }

    // MARK: Save failures

    /// Retries writing the changes a failed save left in the context; no-op when nothing failed.
    func retryFailedSave() {
        guard lastSaveFailed else { return }
        lastSaveFailed = false   // a new failure shows the alert again
        save(refetch: true)
    }

    /// Hides the save-failure alert; the changes are retried with the next save. The next scan or
    /// import that can't be saved shows the alert again.
    func acknowledgeSaveFailure() {
        saveFailureNeedsAttention = false
    }

    // MARK: Private

    private func reindex(_ document: ScanDocument) {
        for (i, page) in document.orderedPages.enumerated() { page.index = i }
    }

    /// Rebuilds the document's search text (`ocrText`) from its pages in display order. Call it
    /// whenever a page's text, the set of pages or their order changes, so search never finds text
    /// that is no longer in the document (and deleted text doesn't stay in the store).
    private func rebuildText(_ document: ScanDocument) {
        document.ocrText = document.orderedPages.map(\.ocrText).joined(separator: "\n")
    }

    private func touch(_ document: ScanDocument) {
        document.modifiedAt = .now
    }

    /// Saves the context. `refetch` re-runs the fetches; use it only when documents or folders were
    /// inserted or deleted, a document was moved to or restored from Recently Deleted, a folder was
    /// renamed, or a document moved. Otherwise `documents` is
    /// re-sorted in memory, which still notifies every observer of `documents` (same view updates
    /// as a re-fetch) without hitting SQLite.
    ///
    /// A failure is not rolled back: the changes stay in the context (and on screen) and are
    /// written by the next successful save; `saveFailureNeedsAttention` asks RootView to tell the
    /// user (once per run of failures, and again for each failed `createDocument`/`addPages`:
    /// `alertAgain`, so background saves such as OCR never repeat it). Image folders of deleted
    /// pages are moved to the image store's trash only after the deletion has been saved, so a
    /// failed save never leaves rows pointing at deleted files; the trash is erased off the main
    /// actor.
    @discardableResult
    private func save(refetch: Bool = false, alertAgain: Bool = false) -> Bool {
        let saved: Bool
        do {
            try context.save()
            saved = true
            lastSaveFailed = false
            saveFailureNeedsAttention = false
            trashDeletedPageImages(pendingImageDeletions)
            pendingImageDeletions.removeAll()
        } catch {
            if !lastSaveFailed || alertAgain { saveFailureNeedsAttention = true }
            lastSaveFailed = true
            saved = false
        }
        if refetch { refresh() } else { documents.sort { $0.modifiedAt > $1.modifiedAt } }
        if saved && !pendingMergeSources.isEmpty { deleteEmptiedMergeSources() }
        return saved
    }

    /// Deletes the merge sources whose pages are now saved under the merge target. Call it only
    /// after a successful save: the re-parenting is then on disk, so deleting a source can't
    /// cascade to a moved page. A source that got pages again in the meantime is kept (never
    /// cascade to a page that did not move). Uses a fresh fetch, so a document deleted in the
    /// meantime is never read. If the save below fails, the deletions stay pending in the context
    /// and the next successful save writes them, like any other failed save.
    private func deleteEmptiedMergeSources() {
        let ids = pendingMergeSources
        pendingMergeSources.removeAll()   // before the nested save, so it can't recurse
        let all = (try? context.fetch(FetchDescriptor<ScanDocument>())) ?? []
        let emptied = all.filter { ids.contains($0.id) && $0.pages.isEmpty }
        guard !emptied.isEmpty else { return }
        for source in emptied {
            search.forget(source.id)
            context.delete(source)
        }
        save(refetch: true)
    }

    /// Moves the image folders of deleted pages to the image store's trash, then erases the trash
    /// off the main actor. Call it only after the rows are saved. The renames run here because
    /// they are cheap (one per page), so a kill right after the save can no longer leave deleted
    /// scans among the page folders, where the orphan sweep skips them while the library is
    /// empty; whatever is still in the trash is erased at the next launch
    /// (`runStartupMaintenance`). A folder that can't be moved is deleted in the background.
    private func trashDeletedPageImages(_ pageIDs: Set<UUID>) {
        guard !pageIDs.isEmpty else { return }
        let imageStore = imageStore
        var unmoved: [UUID] = []
        for id in pageIDs where (try? imageStore.moveToTrash(pageID: id)) == nil {
            unmoved.append(id)
        }
        let leftovers = unmoved
        Task.detached(priority: .utility) {
            imageStore.emptyTrash()
            for id in leftovers { try? imageStore.delete(pageID: id) }
        }
    }

    /// DEBUG check that a document's page indexes are 0..<count (runs in the CI screenshot job).
    private func assertContiguousIndexes(_ document: ScanDocument) {
        #if DEBUG
        assert(document.orderedPages.map(\.index) == Array(0..<document.pages.count), "Page indexes of \(document.id) are not 0..<count")
        #endif
    }
}
