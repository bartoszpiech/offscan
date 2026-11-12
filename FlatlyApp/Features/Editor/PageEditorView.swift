import SwiftUI
import CoreGraphics
import FlatlyCore

/// Full-size page editor. Pages of the document are laid out in a horizontal pager (swipe, or the
/// previous/next buttons in the title); the tool bar at the bottom — filter, adjust edges, crop,
/// rotate, sign — and the More menu act on the page currently shown.
///
/// "Adjust Edges" works for every page: imports re-correct from their stored photo, camera scans
/// get their current image promoted to a source on first use (`ScanProcessor.loadCornerAdjustSource`)
/// so the first adjustment starts from the full frame.
///
/// Rotating, cropping or adjusting the edges of a signed page removes the signature (after
/// confirmation): its frame is relative to the page's geometry and would no longer sit where the
/// user placed it. Adjusting the edges also resets the crop, so a cropped page asks first too.
/// Filter changes keep both.
///
/// Edits are rendered with `DocumentAssembler.applyDeferringOCR` / `readjustCornersDeferringOCR`
/// behind a progress overlay; OCR is then re-run in the background, debounced per page at utility
/// priority (`DocumentAssembler.scheduleOCR(forPageID:)`), so the UI is not blocked.
/// Pages are always re-resolved by id (`DocumentStore.page(id:)`) before they are written.
/// A render keeps going when the user leaves with Back; renders of one page are serialised by
/// `DocumentAssembler`, and a re-opened editor shows the "Updating page…" overlay (no tool can
/// start) while one started before Back is still finishing on the shown page
/// (`DocumentAssembler.isRendering(pageID:)`).
///
/// Apply to All (filter bar) re-renders every other page with the shown page's filter, one page at
/// a time behind a cancellable overlay (leaving the editor cancels it too); OCR for the changed
/// pages runs afterwards in the background.
struct PageEditorView: View {
    let document: ScanDocument
    /// Presents the edge adjustment for the initial page as soon as the editor appears.
    private let startsWithEdgeAdjustment: Bool

    init(document: ScanDocument, pageID: UUID, startsWithEdgeAdjustment: Bool = false) {
        self.document = document
        self.startsWithEdgeAdjustment = startsWithEdgeAdjustment
        _selection = State(initialValue: pageID)
    }

    @Environment(AppServices.self) private var services
    @Environment(DocumentStore.self) private var store
    @Environment(ImageCache.self) private var cache
    @Environment(\.dismiss) private var dismiss

    /// Id of the page currently shown.
    @State private var selection: UUID
    @State private var didRunInitialAction = false
    @State private var zoom: CGFloat = 1
    @State private var showFilters = false
    @State private var busyLabel: LocalizedStringKey?
    @State private var loadTask: Task<Void, Never>?
    /// Bumped when a crop / edge-adjustment load starts or is cancelled; a load only touches state
    /// while its generation is current, so a cancelled load that returns late can't clear a newer
    /// load's (or a render's) overlay.
    @State private var loadGeneration = 0
    /// "Apply to All" re-rendering the document's pages.
    @State private var bulkTask: Task<Void, Never>?
    @State private var cropSession: CropSession?
    @State private var cornerSession: CornerSession?
    @State private var signatureTarget: SignatureTarget?
    @State private var pendingChange: PendingChange?
    @State private var confirmDeletePage = false
    @State private var confirmRemoveSignature = false
    @State private var errorMessage: String?

    private struct CropSession: Identifiable {
        let id = UUID()
        let pageID: UUID
        /// Unfiltered original, rotated like the page.
        let image: CGImage
        /// Current crop in the rotated image's space.
        let displayRect: CGRect?
        let rotation: Rotation
    }

    private struct CornerSession: Identifiable {
        let id = UUID()
        let pageID: UUID
        let image: CGImage
        let quad: Quadrilateral
    }

    private struct SignatureTarget: Identifiable {
        /// The page id.
        let id: UUID
        let recipe: PageRenderRecipe
    }

    /// A change that would drop the page's signature (or, for new edges, its crop) and therefore
    /// needs confirmation first.
    private enum PendingChange {
        case recipe(PageRenderRecipe, pageID: UUID)
        case adjustEdges(pageID: UUID, dropsCrop: Bool, dropsSignature: Bool)

        var title: Text {
            switch self {
            case .adjustEdges(_, dropsCrop: true, dropsSignature: true):
                Text("Reset the crop and remove the signature?")
            case .adjustEdges(_, dropsCrop: true, dropsSignature: false):
                Text("Reset the crop?")
            case .recipe, .adjustEdges:
                Text("Remove the signature?")
            }
        }

        var message: Text {
            switch self {
            case .recipe:
                Text("Rotating or cropping removes the signature from this page. You can sign it again afterwards.")
            case .adjustEdges(_, dropsCrop: true, dropsSignature: true):
                Text("Adjusting the edges resets the crop of this page and removes its signature. You can crop and sign it again afterwards.")
            case .adjustEdges(_, dropsCrop: true, dropsSignature: false):
                Text("Adjusting the edges resets the crop of this page. You can crop it again afterwards.")
            case .adjustEdges:
                Text("Adjusting the edges removes the signature from this page. You can sign it again afterwards.")
            }
        }
    }

    var body: some View {
        let pages = document.orderedPages
        if let current = pages.first(where: { $0.id == selection }) ?? pages.first {
            editor(pages: pages, current: current)
        } else {
            // Every page is gone (deleted here or elsewhere): go back to the document.
            Color(.systemGroupedBackground)
                .ignoresSafeArea()
                .onAppear { dismiss() }
        }
    }

    private func editor(pages: [ScanPage], current: ScanPage) -> some View {
        let index = pages.firstIndex { $0.id == current.id } ?? 0
        let canApplyToAll = pages.count > 1 && pages.contains { $0.recipe.filter != current.recipe.filter }
        let content = VStack(spacing: 0) {
            pager(pages, selectedIndex: index)
            if showFilters {
                FilterPickerBar(
                    pageID: current.id,
                    recipe: current.recipe,
                    quad: current.detectedQuad,
                    onSelect: { setFilter($0) },
                    onApplyToAll: canApplyToAll ? { applyCurrentFilterToAllPages() } : nil
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            Divider()
            editTools(current)
        }
        return withDialogs(withPresentations(content))
            .navigationTitle(Text("Page \(index + 1) of \(pages.count)"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    pageSwitcher(pages: pages, index: index)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    moreMenu(current)
                }
            }
            // Also while a render started before Back (by an earlier editor) finishes on this page.
            .progressOverlay(
                busyLabel != nil || services.assembler.isRendering(pageID: current.id),
                label: busyLabel ?? "Updating page…",
                onCancel: cancelAction
            )
            .onChange(of: selection) {
                zoom = 1
            }
            .onChange(of: pages.map(\.id)) { _, ids in
                // The shown page was removed elsewhere: fall back to the first remaining one.
                if !ids.contains(selection), let first = ids.first { selection = first }
            }
            .task {
                guard startsWithEdgeAdjustment, !didRunInitialAction else { return }
                didRunInitialAction = true
                requestEdgeAdjustment()
            }
            // Leaving the editor (Back or swipe-back, which the overlay doesn't cover) stops
            // Apply to All like Cancel does: nobody is left to see its progress or errors, and a
            // reopened editor must not edit a page the loop hasn't reached yet. The page being
            // rendered finishes; a reopened editor shows the overlay on it until then
            // (`DocumentAssembler.isRendering(pageID:)`).
            .onDisappear { cancelBulkApply() }
    }

    /// Horizontally paging pages; only the visible page is zoomable, and zoom resets on page change.
    /// Only the shown page and its two neighbours load the 2000 px image (the neighbours are
    /// preloaded before they are swiped in); every other page holds only its thumbnail.
    private func pager(_ pages: [ScanPage], selectedIndex: Int) -> some View {
        // `editor` is only built when a current page exists, so `pages` is not empty.
        let nearby = Set(pages[max(0, selectedIndex - 1)...min(pages.count - 1, selectedIndex + 1)].map(\.id))
        return TabView(selection: $selection) {
            ForEach(pages, id: \.id) { page in
                ZoomablePageView(page: page, showsFullImage: nearby.contains(page.id), scale: zoomBinding(for: page.id))
                    .tag(page.id)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .background(Color(.systemGroupedBackground))
    }

    private func zoomBinding(for pageID: UUID) -> Binding<CGFloat> {
        Binding(
            get: { pageID == selection ? zoom : 1 },
            set: { if pageID == selection { zoom = $0 } }
        )
    }

    // MARK: Presentations

    private func withPresentations(_ content: some View) -> some View {
        content
            .fullScreenCover(item: $cropSession) { session in
                CropView(image: session.image, cropRect: session.displayRect) { rect in
                    cropSession = nil
                    applyCrop(rect, rotation: session.rotation, pageID: session.pageID)
                } onCancel: {
                    cropSession = nil
                }
            }
            .fullScreenCover(item: $cornerSession) { session in
                CornerAdjustView(image: session.image, quad: session.quad) { quad in
                    cornerSession = nil
                    readjustEdges(quad, pageID: session.pageID)
                } onCancel: {
                    cornerSession = nil
                }
            }
            .sheet(item: $signatureTarget) { target in
                SignatureFlowView(pageID: target.id, recipe: target.recipe) { placement in
                    guard let page = store.page(id: target.id) else { return }
                    var r = page.recipe
                    r.signature = placement
                    apply(r, to: target.id, label: "Placing signature…", feedback: Haptics.success)
                }
            }
    }

    private func withDialogs(_ content: some View) -> some View {
        content
            .confirmationDialog(
                pendingChange?.title ?? Text(verbatim: ""),
                isPresented: Binding(get: { pendingChange != nil }, set: { if !$0 { pendingChange = nil } }),
                titleVisibility: .visible,
                presenting: pendingChange
            ) { change in
                Button("Continue", role: .destructive) {
                    pendingChange = nil
                    perform(change)
                }
                .accessibilityIdentifier("editor.confirmGeometryChangeButton")
                Button("Cancel", role: .cancel) { pendingChange = nil }
            } message: { change in
                change.message
            }
            .confirmationDialog(Text("Delete this page?"), isPresented: $confirmDeletePage, titleVisibility: .visible) {
                Button("Delete Page", role: .destructive) { deleteCurrentPage() }
                    .accessibilityIdentifier("editor.confirmDeletePageButton")
            } message: {
                Text("This cannot be undone.")
            }
            .confirmationDialog(Text("Remove the signature?"), isPresented: $confirmRemoveSignature, titleVisibility: .visible) {
                Button("Remove Signature", role: .destructive) { removeSignature() }
                    .accessibilityIdentifier("editor.confirmRemoveSignatureButton")
            }
            .alert(
                Text("Something went wrong"),
                isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
            ) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
    }

    // MARK: Toolbar

    private func pageSwitcher(pages: [ScanPage], index: Int) -> some View {
        HStack(spacing: 0) {
            Button {
                withAnimation { selection = pages[index - 1].id }
            } label: {
                Image(systemName: "chevron.left")
                    .frame(minWidth: 44, minHeight: 44)
            }
            .disabled(index <= 0)
            .accessibilityLabel(Text("Previous page"))
            .accessibilityIdentifier("editor.previousPageButton")

            Text("Page \(index + 1) of \(pages.count)")
                .font(.headline.monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("editor.pageIndicator")

            Button {
                withAnimation { selection = pages[index + 1].id }
            } label: {
                Image(systemName: "chevron.right")
                    .frame(minWidth: 44, minHeight: 44)
            }
            .disabled(index >= pages.count - 1)
            .accessibilityLabel(Text("Next page"))
            .accessibilityIdentifier("editor.nextPageButton")
        }
    }

    /// The bottom tool bar. Like UIKit tool bars it stops growing at `.xxxLarge`; at accessibility
    /// sizes a long-press shows the tool's icon and title in the Large Content Viewer.
    private func editTools(_ page: ScanPage) -> some View {
        // Top-aligned: a two-line caption must not push its icon out of line.
        HStack(alignment: .top, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.25)) { showFilters.toggle() }
            } label: {
                Label("Filter", systemImage: "camera.filters")
            }
            .accessibilityShowsLargeContentViewer()
            .background(
                showFilters ? Color.accentColor.opacity(0.15) : Color.clear,
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .accessibilityAddTraits(showFilters ? [.isSelected] : [])
            .accessibilityIdentifier("editor.filterButton")

            Button {
                requestEdgeAdjustment()
            } label: {
                Label(adjustEdgesCaption, systemImage: "perspective")
            }
            .accessibilityShowsLargeContentViewer()
            .accessibilityLabel(Text("Adjust Edges"))
            .accessibilityHint(Text("Drag the corners to fit the page"))
            .accessibilityIdentifier("editor.adjustEdgesButton")

            Button {
                openCrop()
            } label: {
                Label("Crop", systemImage: "crop")
            }
            .accessibilityShowsLargeContentViewer()
            .accessibilityHint(Text("Keeps only part of the page"))
            .accessibilityIdentifier("editor.cropButton")

            Button {
                rotate(clockwise: true)
            } label: {
                Label("Rotate", systemImage: "rotate.right")
            }
            .accessibilityShowsLargeContentViewer()
            .accessibilityLabel(Text("Rotate Right"))
            .accessibilityIdentifier("editor.rotateRightButton")

            Button {
                signatureTarget = SignatureTarget(id: page.id, recipe: page.recipe)
            } label: {
                Label("Sign", systemImage: "signature")
            }
            .accessibilityShowsLargeContentViewer()
            .accessibilityIdentifier("editor.signButton")
        }
        .labelStyle(.toolbarCaption)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.bar)
        // Like UIKit tool bars: stops growing at xxxLarge, so the page keeps its room;
        // accessibility sizes get the Large Content Viewer on long-press instead.
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    /// Own key: the tool bar caption must fit one line in a fifth of the screen; the full
    /// "Adjust Edges" key (Polish "Dopasuj krawędzie") stays the screen title and VoiceOver label.
    private var adjustEdgesCaption: String {
        String(localized: "editor.tool.adjustEdges", defaultValue: "Adjust Edges", comment: "Short caption under the perspective icon in the page editor's bottom tool bar")
    }

    private func moreMenu(_ page: ScanPage) -> some View {
        Menu {
            Button {
                rotate(clockwise: false)
            } label: {
                Label("Rotate Left", systemImage: "rotate.left")
            }
            .accessibilityIdentifier("editor.rotateLeftButton")
            if page.recipe.signature != nil {
                Button(role: .destructive) {
                    confirmRemoveSignature = true
                } label: {
                    Label("Remove Signature", systemImage: "signature")
                }
                .accessibilityIdentifier("editor.removeSignatureButton")
            }
            Divider()
            Button(role: .destructive) {
                confirmDeletePage = true
            } label: {
                Label("Delete Page", systemImage: "trash")
            }
            .accessibilityIdentifier("editor.deletePageButton")
        } label: {
            Label("More", systemImage: "ellipsis.circle")
        }
        .accessibilityIdentifier("editor.moreMenu")
    }

    // MARK: Actions

    /// The page currently shown, re-resolved from the document.
    private var currentPage: ScanPage? {
        document.orderedPages.first { $0.id == selection }
    }

    private func setFilter(_ filter: ScanFilter) {
        guard let page = currentPage else { return }
        var r = page.recipe
        guard r.filter != filter else { return }
        r.filter = filter
        apply(r, to: page.id, label: "Applying filter…")
    }

    /// Re-renders every page with the shown page's filter, one page at a time (each render plus
    /// recipe write is atomic and cancellation, by Cancel or leaving the editor, is checked only
    /// between pages, so the document is never half-written), then recognises the changed pages'
    /// text in the background.
    private func applyCurrentFilterToAllPages() {
        guard busyLabel == nil, let current = currentPage, !services.assembler.isRendering(pageID: current.id) else { return }
        let filter = current.recipe.filter
        let ids = document.orderedPages.map(\.id)
        let assembler = services.assembler
        let total = ids.count
        let first: LocalizedStringKey = "Applying filter… \(1) of \(total)"
        busyLabel = first
        bulkTask = Task {
            var changed: [UUID] = []
            var failure: Error?
            for (offset, id) in ids.enumerated() {
                if Task.isCancelled { break }
                let label: LocalizedStringKey = "Applying filter… \(offset + 1) of \(total)"
                busyLabel = label
                guard let page = store.page(id: id), page.recipe.filter != filter else { continue }
                var recipe = page.recipe
                recipe.filter = filter
                do {
                    try await assembler.applyDeferringOCR(recipe: recipe, to: page)
                    cache.invalidate(pageID: id)
                    changed.append(id)
                } catch {
                    failure = error
                    break
                }
            }
            // Every changed page had its text cleared: recognise it also after a cancel or error.
            if !changed.isEmpty {
                let pending = changed
                Task(priority: .utility) { await assembler.recognizePendingText(forPageIDs: pending) }
            }
            if let failure {
                errorMessage = failure.localizedDescription
            } else if !Task.isCancelled {
                Haptics.success()
            }
            bulkTask = nil
            busyLabel = nil
        }
    }

    private func rotate(clockwise: Bool) {
        guard let page = currentPage else { return }
        var r = page.recipe
        r.rotation = clockwise ? r.rotation.rotatedClockwise() : r.rotation.rotatedCounterClockwise()
        applyGeometryChange(r, to: page)
    }

    private func applyCrop(_ displayRect: CGRect?, rotation: Rotation, pageID: UUID) {
        guard let page = store.page(id: pageID) else { return }
        var r = page.recipe
        let newCrop = displayRect.map { CropGeometry.clamped(CropGeometry.unrotate($0, by: rotation)) }
        guard !CropGeometry.approximatelyEqual(newCrop, r.cropRect) else { return }
        r.cropRect = newCrop
        applyGeometryChange(r, to: page)
    }

    /// Rotation/crop invalidate the signature frame: ask before dropping it.
    private func applyGeometryChange(_ recipe: PageRenderRecipe, to page: ScanPage) {
        if page.recipe.signature != nil {
            var r = recipe
            r.signature = nil
            pendingChange = .recipe(r, pageID: page.id)
        } else {
            apply(recipe, to: page.id, label: "Updating page…")
        }
    }

    /// New edges drop the crop and the signature (see `readjustCornersDeferringOCR`): ask first
    /// when the page has either.
    private func requestEdgeAdjustment() {
        guard let page = currentPage else { return }
        let recipe = page.recipe
        if recipe.cropRect != nil || recipe.signature != nil {
            pendingChange = .adjustEdges(pageID: page.id, dropsCrop: recipe.cropRect != nil, dropsSignature: recipe.signature != nil)
        } else {
            openEdgeAdjustment(pageID: page.id)
        }
    }

    private func perform(_ change: PendingChange) {
        switch change {
        case .recipe(let recipe, let pageID): apply(recipe, to: pageID, label: "Updating page…")
        case .adjustEdges(let pageID, _, _): openEdgeAdjustment(pageID: pageID)
        }
    }

    private func removeSignature() {
        guard let page = currentPage else { return }
        var r = page.recipe
        guard r.signature != nil else { return }
        r.signature = nil
        apply(r, to: page.id, label: "Removing signature…")
    }

    private func apply(
        _ recipe: PageRenderRecipe,
        to pageID: UUID,
        label: LocalizedStringKey,
        feedback: @escaping @MainActor () -> Void = Haptics.lightImpact
    ) {
        guard busyLabel == nil, !services.assembler.isRendering(pageID: pageID), let target = store.page(id: pageID) else { return }
        let assembler = services.assembler
        busyLabel = label
        Task {
            do {
                try await assembler.applyDeferringOCR(recipe: recipe, to: target)
                cache.invalidate(pageID: pageID)
                feedback()
                scheduleOCR(for: pageID)
            } catch {
                errorMessage = error.localizedDescription
            }
            busyLabel = nil
        }
    }

    private func readjustEdges(_ quad: Quadrilateral, pageID: UUID) {
        guard busyLabel == nil, !services.assembler.isRendering(pageID: pageID), let target = store.page(id: pageID) else { return }
        let assembler = services.assembler
        busyLabel = "Adjusting edges…"
        Task {
            do {
                try await assembler.readjustCornersDeferringOCR(target, quad: quad)
                cache.invalidate(pageID: pageID)
                Haptics.lightImpact()
                scheduleOCR(for: pageID)
            } catch {
                errorMessage = error.localizedDescription
            }
            busyLabel = nil
        }
    }

    private func scheduleOCR(for pageID: UUID) {
        services.assembler.scheduleOCR(forPageID: pageID)
    }

    private func openCrop() {
        guard busyLabel == nil, let page = currentPage, !services.assembler.isRendering(pageID: page.id) else { return }
        let id = page.id
        let recipe = page.recipe
        let processor = services.processor
        loadGeneration += 1
        let generation = loadGeneration
        busyLabel = "Loading…"
        loadTask = Task {
            do {
                let base = PageRenderRecipe(cropRect: nil, filter: .original, rotation: recipe.rotation, signature: nil)
                let image = try await processor.preview(pageID: id, recipe: base, maxDimension: 2000)
                try Task.checkCancellation()
                cropSession = CropSession(
                    pageID: id,
                    image: image,
                    displayRect: recipe.cropRect.map { CropGeometry.rotate($0, by: recipe.rotation) },
                    rotation: recipe.rotation
                )
            } catch is CancellationError {
            } catch {
                // A cancelled load never shows an alert.
                if generation == loadGeneration { errorMessage = error.localizedDescription }
            }
            finishLoading(generation)
        }
    }

    /// Loads the image to adjust on (imports: the stored photo; camera scans: their current image,
    /// promoted to a source on first use) and presents the corner editor pre-filled with the quad
    /// that produced the current page, or the full frame.
    private func openEdgeAdjustment(pageID: UUID) {
        guard busyLabel == nil, !services.assembler.isRendering(pageID: pageID), let page = store.page(id: pageID) else { return }
        let quad = page.detectedQuad ?? .fullFrame
        let processor = services.processor
        loadGeneration += 1
        let generation = loadGeneration
        busyLabel = "Loading…"
        loadTask = Task {
            do {
                let image = try await processor.loadCornerAdjustSource(pageID: pageID, maxDimension: ScanProcessor.reviewMaxDimension)
                try Task.checkCancellation()
                cornerSession = CornerSession(pageID: pageID, image: image, quad: quad)
            } catch is CancellationError {
            } catch {
                // A cancelled load never shows an alert.
                if generation == loadGeneration { errorMessage = error.localizedDescription }
            }
            finishLoading(generation)
        }
    }

    /// Image loading (before crop / edge adjustment) and Apply to All can be cancelled; single
    /// renders cannot.
    private var cancelAction: (() -> Void)? {
        if bulkTask != nil { return { cancelBulkApply() } }
        guard loadTask != nil else { return nil }
        return { cancelLoading() }
    }

    /// Stops Apply to All after the page being rendered (overlay Cancel, or leaving the editor).
    /// The overlay stays until that render finishes (the task clears it), so no other edit can
    /// start on that page meanwhile; after leaving, a reopened editor gets the same guarantee from
    /// `DocumentAssembler`, which serialises renders of one page. A no-op when Apply to All isn't
    /// running.
    private func cancelBulkApply() {
        bulkTask?.cancel()
        bulkTask = nil
    }

    /// Cancel on the loading overlay: clears the overlay at once. The load keeps running until its
    /// decode returns (it can't be interrupted), so the generation moves on and its late cleanup is
    /// ignored.
    private func cancelLoading() {
        loadTask?.cancel()
        loadTask = nil
        busyLabel = nil
        loadGeneration += 1
    }

    /// Called by a load task as it ends. Only the current load clears the overlay: a cancelled one
    /// changes nothing, because `cancelLoading()` already did and `loadTask` / `busyLabel` may now
    /// belong to a load (or a render) started after the Cancel.
    private func finishLoading(_ generation: Int) {
        guard generation == loadGeneration else { return }   // cancelled, or superseded by a newer load
        loadTask = nil
        busyLabel = nil
    }

    /// Shows a neighbour first (or pops back when this is the only page), then deletes, so no view
    /// renders a deleted model.
    private func deleteCurrentPage() {
        let pages = document.orderedPages
        guard let index = pages.firstIndex(where: { $0.id == selection }) else { return }
        let doomedID = pages[index].id
        let store = store
        Haptics.warning()
        let delay: Duration
        if pages.count > 1 {
            let neighbour = index + 1 < pages.count ? pages[index + 1] : pages[index - 1]
            withAnimation { selection = neighbour.id }
            delay = .milliseconds(350)
        } else {
            dismiss()
            delay = .milliseconds(500)
        }
        Task {
            try? await Task.sleep(for: delay)
            if let doomed = store.page(id: doomedID) { store.deletePage(doomed) }
        }
    }
}
