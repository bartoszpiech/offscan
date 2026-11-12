import SwiftUI
import FlatlyCore

/// Export options for a document: a header (first page, title, page count), format, page size
/// and compression, with the Share (prominent) / Save to Files actions pinned at the bottom.
/// Files are produced in the background by `ExportService` (via `ScanProcessor`) into a temporary
/// folder. The chosen settings are remembered and reused by the one-tap "Share PDF".
/// An optional password (this sheet only, never stored) encrypts the PDF.
struct ExportSheet: View {
    let document: ScanDocument

    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss

    @AppStorage("exportFormat") private var format: ExportFormat = .pdf
    @AppStorage("exportPageSize") private var pageSize: PageSizeOption = .regionDefault
    @AppStorage("exportCompression") private var compression: CompressionLevel = .medium
    /// Plain view state, deliberately not `@AppStorage`/`@SceneStorage`: the password applies to
    /// this sheet's exports only and is gone when the sheet closes.
    @State private var pdfPassword: String?

    @State private var exportTask: Task<Void, Never>?
    @State private var exportLabel: LocalizedStringKey = "Exporting…"
    @State private var shareFiles: ExportedFiles?
    @State private var saveFiles: ExportedFiles?
    @State private var errorMessage: String?
    @State private var savedMessageVisible = false

    private enum Destination { case share, files }

    var body: some View {
        let pageCount = document.pages.count
        NavigationStack {
            Form {
                Section {
                    ExportDocumentHeader(document: document)
                }

                Section {
                    Picker("Format", selection: $format) {
                        ForEach(ExportFormat.allCases) { format in
                            Text(format.displayName).tag(format)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("export.formatPicker")
                } footer: {
                    switch format {
                    case .pdf: Text("Searchable PDF: recognized text can be selected and searched.")
                    case .jpg: Text("One image per page.")
                    }
                }

                Section {
                    if format == .pdf {
                        Picker("Page Size", selection: $pageSize) {
                            ForEach(PageSizeOption.allCases, id: \.self) { size in
                                Text(size.displayName).tag(size)
                            }
                        }
                        .accessibilityIdentifier("export.pageSizePicker")
                    }
                    Picker("Quality", selection: $compression) {
                        ForEach(CompressionLevel.allCases, id: \.self) { level in
                            Text(level.displayName).tag(level)
                        }
                    }
                    .accessibilityIdentifier("export.compressionPicker")
                }

                if format == .pdf {
                    Section {
                        NavigationLink {
                            PDFPasswordView(password: $pdfPassword)
                        } label: {
                            LabeledContent("Password") {
                                pdfPassword == nil ? Text("Off") : Text("On")
                            }
                        }
                        .accessibilityIdentifier("export.passwordRow")
                    } footer: {
                        if pdfPassword != nil {
                            Text("The exported PDF will ask for this password.")
                        }
                    }
                }
            }
            // Before the title/toolbar/overlay modifiers, so the progress overlay dims them too.
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 10) {
                    Button {
                        export(to: .share)
                    } label: {
                        Label("Share", systemImage: "square.and.arrow.up")
                            .font(.headline)
                            .onAccentForeground()
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("export.shareButton")

                    Button {
                        export(to: .files)
                    } label: {
                        Label("Save to Files", systemImage: "folder")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("export.saveButton")
                }
                .controlSize(.large)
                .disabled(pageCount == 0)
                .padding(.horizontal)
                .padding(.vertical, 8)
                // Matches the Form, so rows scrolling under the buttons at large text stay hidden.
                .background(Color(uiColor: .systemGroupedBackground))
            }
            .navigationTitle(Text("Export"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Like Settings and Move to Folder. Closing still cancels a running export (onDisappear).
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("export.doneButton")
                }
            }
            .progressOverlay(exportTask != nil, label: exportLabel, onCancel: cancelExport)
            // Shared files stay until the next export, a document deletion or the next launch:
            // AirDrop (which can continue after the sheet closes) and Copy may still read them.
            .sheet(item: $shareFiles) { files in
                ShareSheet(items: files.urls, onComplete: { _ in shareFiles = nil })
                    .presentationDetents([.medium, .large])
                    .ignoresSafeArea()
            }
            .sheet(item: $saveFiles) { files in
                DocumentExportPicker(urls: files.urls) { saved in
                    saveFiles = nil
                    if saved { savedMessageVisible = true }
                }
                .ignoresSafeArea()
                .onDisappear {
                    // The picker copies (asCopy) and the copy is complete when it reports back, so
                    // the temp files can go whether the user saved, cancelled or swiped away.
                    let urls = files.urls
                    Task.detached(priority: .utility) { ScanProcessor.removeTemporaryExport(urls) }
                }
            }
            .alert(Text("Saved to Files"), isPresented: $savedMessageVisible) {
                Button("OK", role: .cancel) {}
            }
            .alert(
                Text("Export Failed"),
                isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
            ) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
        .onDisappear { cancelExport() }
    }

    // MARK: Export

    private func export(to destination: Destination) {
        guard exportTask == nil else { return }
        let documentID = document.id
        let format = format, pageSize = pageSize, compression = compression
        let password = format == .pdf ? pdfPassword : nil
        let services = services
        exportLabel = "Exporting…"

        exportTask = Task {
            do {
                let prepared = try await ExportService.prepareRequest(
                    documentID: documentID, format: format, pageSize: pageSize, compression: compression,
                    password: password, services: services, onRecognizing: { exportLabel = "Recognizing text…" }
                )
                guard let request = prepared else {
                    exportTask = nil
                    return
                }
                exportLabel = "Exporting…"
                let urls = try await ExportService.export(request, processor: services.processor)
                exportTask = nil
                switch destination {
                case .share: shareFiles = ExportedFiles(urls: urls)
                case .files: saveFiles = ExportedFiles(urls: urls)
                }
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
