import SwiftUI
import FlatlyCore

/// One-tap "Share PDF": when `documentIDs` is set, builds each document's PDF with the last-used
/// export settings (`exportPageSize`, `exportCompression`), one after another behind a cancellable
/// progress overlay ("Exporting 2 of 3…"), then presents one share sheet with all of them. The
/// binding is reset immediately, so it can be set again. A failure aborts the batch.
/// Apply with `.quickPDFShare(documentID: $id)` or `.quickPDFShare(documentIDs: $ids)`.
struct QuickPDFShareModifier: ViewModifier {
    @Binding var documentIDs: [UUID]

    @Environment(AppServices.self) private var services
    @AppStorage("exportPageSize") private var pageSize: PageSizeOption = .regionDefault
    @AppStorage("exportCompression") private var compression: CompressionLevel = .medium

    @State private var exportTask: Task<Void, Never>?
    @State private var exportLabel: LocalizedStringKey = "Exporting…"
    @State private var shareFiles: ExportedFiles?
    @State private var errorMessage: String?

    func body(content: Content) -> some View {
        content
            .progressOverlay(exportTask != nil, label: exportLabel, onCancel: cancelExport)
            // Shared files stay until the next export, a document deletion or the next launch:
            // AirDrop (which can continue after the sheet closes) and Copy may still read them.
            .sheet(item: $shareFiles) { files in
                ShareSheet(items: files.urls, onComplete: { _ in shareFiles = nil })
                    .presentationDetents([.medium, .large])
                    .ignoresSafeArea()
            }
            .alert(
                Text("Export Failed"),
                isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
            ) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
            .onChange(of: documentIDs) { _, ids in
                guard !ids.isEmpty else { return }
                documentIDs = []
                start(documentIDs: ids)
            }
            // Leaving the screen (e.g. the back button, which the overlay doesn't cover) abandons
            // the export: nobody is left to see its share sheet.
            .onDisappear { cancelExport() }
    }

    private func start(documentIDs ids: [UUID]) {
        let services = services
        guard exportTask == nil, ids.contains(where: { services.store.document(id: $0)?.pages.isEmpty == false }) else { return }
        let pageSize = pageSize, compression = compression
        exportLabel = "Exporting…"
        exportTask = Task {
            do {
                var urls: [URL] = []
                var isFirstExport = true
                for (i, id) in ids.enumerated() {
                    let progress: LocalizedStringKey = ids.count > 1 ? "Exporting \(i + 1) of \(ids.count)…" : "Exporting…"
                    exportLabel = progress
                    let prepared = try await ExportService.prepareRequest(
                        documentID: id, format: .pdf, pageSize: pageSize, compression: compression,
                        services: services, onRecognizing: { exportLabel = "Recognizing text…" }
                    )
                    // Gone or empty meanwhile: skip it.
                    guard let request = prepared else { continue }
                    exportLabel = progress
                    // Only the first export clears earlier temp files; the batch's own files stay.
                    urls += try await ExportService.export(request, processor: services.processor, cleanPrevious: isFirstExport)
                    isFirstExport = false
                }
                exportTask = nil
                if !urls.isEmpty { shareFiles = ExportedFiles(urls: urls) }
            } catch {
                // A cancelled export was already cleared by `cancelExport`.
                guard !Task.isCancelled, !(error is CancellationError) else { return }
                exportTask = nil
                errorMessage = error.localizedDescription
            }
        }
    }

    private func cancelExport() {
        exportTask?.cancel()
        exportTask = nil
    }
}

extension View {
    /// Builds and shares a document's PDF whenever `documentID` is set (see `QuickPDFShareModifier`).
    func quickPDFShare(documentID: Binding<UUID?>) -> some View {
        quickPDFShare(documentIDs: Binding(
            get: { documentID.wrappedValue.map { [$0] } ?? [] },
            set: { documentID.wrappedValue = $0.first }
        ))
    }

    /// Builds the PDFs of `documentIDs` and shares them in one share sheet whenever it is set.
    func quickPDFShare(documentIDs: Binding<[UUID]>) -> some View {
        modifier(QuickPDFShareModifier(documentIDs: documentIDs))
    }
}
