import Foundation
import Observation
import FlatlyCore

/// Dependency container injected into the view hierarchy with `.environment(services)`.
/// Read it with `@Environment(AppServices.self) private var services`.
@MainActor
@Observable
final class AppServices {
    let store: DocumentStore
    let processor: ScanProcessor
    let assembler: DocumentAssembler
    /// Set by the first `runStartupMaintenance()` call, before its first `await`; every later call
    /// returns at once (see there).
    @ObservationIgnored private var didRunStartupMaintenance = false

    init(store: DocumentStore, processor: ScanProcessor) {
        self.store = store
        self.processor = processor
        self.assembler = DocumentAssembler(store: store, processor: processor)
        // Exports and PDF import copies left by a previous run (e.g. an import interrupted by a
        // kill). Done here, before any view exists, so it can never race an export or an import
        // (removing small tmp folders is cheap).
        ScanProcessor.cleanTemporaryExports()
        FileImportSelection.removeLeftovers()
    }

    /// Runs once per `AppServices` (i.e. once per launch, and once more after
    /// `FlatlyApp.retryStartup()` builds a new instance): in DEBUG demo mode it first seeds the demo
    /// library, then erases documents whose time in Recently Deleted has expired
    /// (`DocumentStore.purgeExpiredDeletions`, whose save moves their image folders to the image
    /// store's trash), then erases that trash, finishes OCR that was interrupted by a kill and
    /// removes page image folders that no longer belong to any page (e.g. a scan interrupted between
    /// writing files and inserting the page). Folders younger than ten minutes are kept in case a
    /// capture is in flight.
    ///
    /// RootView calls it from its `.task`, which SwiftUI restarts whenever the root view reappears,
    /// i.e. after every full-screen cover (camera, import, Crop, Adjust Edges). Later calls return
    /// immediately: a re-run would start a second OCR loop over the pages of a new scan while they
    /// are still being recognised. The flag is set before the first `await`, so a call that starts
    /// while the first one is suspended also returns at once.
    ///
    /// The trash holds only folders of pages whose deletion was saved (e.g. left by a kill right
    /// after a delete), so it is always emptied, even when the library is empty or unreadable.
    /// Page ids are read off the main actor (`DocumentStore.pageMaintenanceSnapshot`), which sees
    /// only saved rows. So nothing is swept while the store has unsaved changes
    /// (`DocumentStore.hasUnsavedChanges`): pages a failed save left in the context would look like
    /// orphans. If the library can't be read, nothing is swept either: a failed fetch must never
    /// look like an empty library and delete every scan's images. Nothing is swept while the store
    /// has no pages. OCR resumes in the background at utility priority.
    func runStartupMaintenance() async {
        guard !didRunStartupMaintenance else { return }
        didRunStartupMaintenance = true
        #if DEBUG
        await DemoLibrarySeeder.seedIfRequested(services: self)
        #endif
        // Before the snapshot, so the erased pages are no longer among the known ones.
        store.purgeExpiredDeletions()
        let imageStore = store.imageStore
        let snapshot = await store.pageMaintenanceSnapshot()
        let knownIDs = store.hasUnsavedChanges ? nil : snapshot?.known
        let cutoff = Date().addingTimeInterval(-10 * 60)
        await Task.detached(priority: .utility) {
            imageStore.emptyTrash()
            if let knownIDs {
                _ = try? imageStore.removeOrphanedPages(keeping: knownIDs, modifiedBefore: cutoff)
            }
        }.value
        guard let snapshot else { return }
        let assembler = assembler
        let pending = snapshot.pending
        // Not awaited: awaiting `.value` would raise it back to the caller's (user-initiated) priority.
        Task(priority: .utility) { await assembler.recognizePendingText(forPageIDs: pending) }
    }

    /// Production wiring: persistent SwiftData store + Application Support image files.
    static func makeDefault() throws -> AppServices {
        let container = try ModelContainerFactory.makePersistent()
        let imageStore = PageImageStore(rootDirectory: try PageImageStore.defaultRoot())
        let store = DocumentStore(container: container, imageStore: imageStore)
        return AppServices(store: store, processor: ScanProcessor(imageStore: imageStore))
    }

    /// In-memory wiring for previews and UI tests (set FLATLY_UI_TESTING=1).
    static func makeEphemeral() throws -> AppServices {
        let container = try ModelContainerFactory.makeInMemory()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("FlatlyEphemeral-\(UUID().uuidString)", isDirectory: true)
        let imageStore = PageImageStore(rootDirectory: root)
        let store = DocumentStore(container: container, imageStore: imageStore)
        return AppServices(store: store, processor: ScanProcessor(imageStore: imageStore))
    }
}
