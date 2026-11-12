import SwiftUI

/// Root of the window: the library navigation stack plus the app lock.
struct RootView: View {
    @Environment(AppLockManager.self) private var lock
    @Environment(DocumentStore.self) private var store
    @Environment(AppServices.self) private var services
    @Environment(\.scenePhase) private var scenePhase
    @State private var router = AppRouter()

    var body: some View {
        NavigationStack(path: $router.path) {
            LibraryView(folder: nil)
                .navigationDestination(for: UUID.self) { id in
                    documentDestination(id: id)
                }
                .navigationDestination(for: FolderRoute.self) { route in
                    folderDestination(id: route.id)
                }
                .navigationDestination(for: RecentlyDeletedRoute.self) { _ in
                    RecentlyDeletedView()
                }
        }
        .environment(router)
        .blur(radius: lock.isLocked ? 30 : 0)
        .allowsHitTesting(!lock.isLocked)
        .accessibilityHidden(lock.isLocked)
        .background {
            LockWindowPresenter(lock: lock, isPresented: lock.isLocked || lock.isShielded)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        }
        .alert(
            Text("Changes Couldn't Be Saved"),
            isPresented: Binding(get: { store.saveFailureNeedsAttention }, set: { if !$0 { store.acknowledgeSaveFailure() } })
        ) {
            // Deferred: the alert's own dismissal first sets the binding to false.
            Button("Try Again") { Task { store.retryFailedSave() } }
            Button("OK", role: .cancel) {}
        } message: {
            Text("The device may be almost out of storage. Free up some space, then tap Try Again.")
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            handleScenePhase(phase)
        }
        .task {
            // Restarts whenever a full-screen cover closes; the maintenance itself runs once per
            // AppServices (and seeds the DEBUG demo library first).
            await services.runStartupMaintenance()
        }
    }

    @ViewBuilder
    private func documentDestination(id: UUID) -> some View {
        if let document = store.document(id: id) {
            DocumentDetailView(document: document)
        } else {
            ContentUnavailableView("Document not found", systemImage: "doc.questionmark", description: Text("It may have been deleted."))
        }
    }

    @ViewBuilder
    private func folderDestination(id: UUID) -> some View {
        if let folder = store.folder(id: id) {
            LibraryView(folder: folder)
        } else {
            ContentUnavailableView("Folder not found", systemImage: "folder.badge.questionmark", description: Text("It may have been deleted."))
        }
    }

    private func handleScenePhase(_ phase: ScenePhase) {
        // LockWindowPresenter also drives the lock from UIScene notifications, since SwiftUI may not
        // update this view under a full-screen cover; the calls are idempotent.
        switch phase {
        case .inactive:
            // App switcher, Control Center: hide the content behind the opaque privacy shield.
            lock.shieldIfEnabled()
        case .background:
            lock.sceneDidEnterBackground()
            // One more chance for changes a failed save left pending, before suspension.
            store.retryFailedSave()
        case .active:
            lock.sceneDidBecomeActive()
        default:
            break
        }
    }
}

#if DEBUG
struct RootView_Previews: PreviewProvider {
    static var previews: some View {
        let services = try! AppServices.makeEphemeral()
        RootView()
            .environment(services)
            .environment(services.store)
            .environment(ImageCache())
            .environment(AppLockManager())
            .environment(QuickActionInbox.shared)
    }
}
#endif
