import SwiftUI
import UIKit
import FlatlyCore

/// Recognized text of every page, shown as readable paragraphs (wrapped lines joined,
/// `OCRResult.readableText`), pages separated by a divider and a "Page N" header. Text is
/// selectable; the labelled bottom bar copies all text (with a short "Copied" confirmation) or
/// shares it, and the More menu, the only trailing item, re-runs text recognition (cancellable,
/// with progress).
struct OCRTextView: View {
    let document: ScanDocument

    @Environment(AppServices.self) private var services
    @State private var ocrTask: Task<Void, Never>?
    /// Bumped when a re-run starts or is cancelled, so a cancelled run that finishes late (Vision
    /// can't be interrupted) leaves a newer run's progress and task alone.
    @State private var ocrGeneration = 0
    @State private var progress: (done: Int, total: Int)?
    @State private var didCopy = false
    /// Each page's readable text, kept until that page's OCR changes.
    @State private var readableCache = ReadableTextCache()

    var body: some View {
        let pages = document.orderedPages
        // Decoded and re-flowed only when a page's OCR result changes (ReadableTextCache).
        let readable = readableCache.texts(for: pages)
        let text = Self.fullText(readable)
        Group {
            if text.isEmpty && !pages.contains(where: { $0.ocrData == nil }) && progress == nil {
                ContentUnavailableView {
                    Label("No Text Recognized", systemImage: "text.magnifyingglass")
                } description: {
                    Text("No text was found on these pages. Try a different filter or run text recognition again.")
                } actions: {
                    Button {
                        rerunOCR()
                    } label: {
                        Text("Run Text Recognition Again")
                            .onAccentForeground()
                    }
                    .buttonStyle(.borderedProminent)
                        .disabled(pages.isEmpty)
                        .accessibilityIdentifier("ocr.emptyRerunButton")
                }
            } else {
                pageList(pages, readable: readable)
            }
        }
        .navigationTitle(Text("Recognized Text"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // A single trailing item: iOS 26 folds extra trailing items into an overflow menu.
            // Copy and Share live in the bottom bar.
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        rerunOCR()
                    } label: {
                        Label("Run Text Recognition Again", systemImage: "text.viewfinder")
                    }
                    .disabled(pages.isEmpty || progress != nil)
                    .accessibilityIdentifier("ocr.rerunButton")
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
                .accessibilityIdentifier("ocr.moreMenu")
            }
            // Hidden in the empty state, whose "Run Text Recognition Again" is the call to action.
            ToolbarItemGroup(placement: .bottomBar) {
                if !text.isEmpty {
                    Button {
                        copy(text)
                    } label: {
                        // An explicit caption: a Label renders icon-only in the iOS 26 bottom bar.
                        HStack(spacing: 6) {
                            if didCopy {
                                Image(systemName: "checkmark")
                                    .accessibilityHidden(true)
                                Text("Copied")
                            } else {
                                Image(systemName: "doc.on.doc")
                                    .accessibilityHidden(true)
                                Text("Copy All")
                            }
                        }
                        .fontWeight(.semibold)
                    }
                    .accessibilityIdentifier("ocr.copyButton")

                    Spacer()

                    ShareLink(item: text) {
                        HStack(spacing: 6) {
                            Image(systemName: "square.and.arrow.up")
                                .accessibilityHidden(true)
                            Text("Share")
                        }
                    }
                    .accessibilityLabel(Text("Share"))
                    .accessibilityIdentifier("ocr.shareButton")
                }
            }
        }
        .progressOverlay(progress != nil, label: progressLabel, onCancel: cancelOCR)
        .task(id: didCopy) {
            guard didCopy else { return }
            try? await Task.sleep(for: .seconds(1.5))
            didCopy = false
        }
        .onDisappear { cancelOCR() }
    }

    private func pageList(_ pages: [ScanPage], readable: [String]) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                ForEach(Array(pages.enumerated()), id: \.element.id) { offset, page in
                    VStack(alignment: .leading, spacing: 8) {
                        if offset > 0 {
                            Divider()
                                .padding(.bottom, 8)
                        }
                        Text("Page \(offset + 1)")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                            .accessibilityAddTraits(.isHeader)
                        if page.ocrData == nil {
                            HStack(spacing: 8) {
                                ProgressView().controlSize(.small)
                                Text("Recognizing text…")
                                    .foregroundStyle(.secondary)
                            }
                            .accessibilityElement(children: .combine)
                        } else if page.ocrText.isEmpty {
                            Text("No text on this page.")
                                .italic()
                                .foregroundStyle(.secondary)
                        } else {
                            Text(readable[offset])
                                .font(.body)
                                .lineSpacing(4)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .accessibilityIdentifier("ocr.page.\(offset + 1)")
                }
            }
            .padding()
        }
        .accessibilityIdentifier("ocr.textList")
    }

    private var progressLabel: LocalizedStringKey {
        guard let progress else { return "Recognizing text…" }
        return "Recognizing text… \(min(progress.done + 1, progress.total)) of \(progress.total)"
    }

    /// A page's text for reading, copying and sharing: wrapped lines joined into paragraphs.
    static func readableText(of page: ScanPage) -> String {
        (page.ocr?.readableText ?? page.ocrText).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Text of all pages separated by blank lines (no headers), for copy and share.
    static func fullText(_ texts: [String]) -> String {
        texts.filter { !$0.isEmpty }.joined(separator: "\n\n")
    }

    /// Copies all text, confirms with "Copied" on the button (reset after 1.5 s), a haptic and,
    /// for VoiceOver, an announcement.
    private func copy(_ text: String) {
        UIPasteboard.general.string = text
        didCopy = true
        Haptics.success()
        UIAccessibility.post(notification: .announcement, argument: String(localized: "Text copied"))
    }

    private func rerunOCR() {
        let pages = document.orderedPages
        guard !pages.isEmpty, ocrTask == nil else { return }
        let assembler = services.assembler
        ocrGeneration += 1
        let generation = ocrGeneration
        progress = (0, pages.count)
        ocrTask = Task {
            for (i, page) in pages.enumerated() {
                // Checked before writing progress, so a cancelled run never shows its own.
                if Task.isCancelled { break }
                progress = (i, pages.count)
                await assembler.runOCR(for: [page])
            }
            // Cancelled: cancelOCR() already cleared the overlay, and progress / ocrTask may now
            // belong to a re-run started after the Cancel.
            if generation == ocrGeneration {
                progress = nil
                ocrTask = nil
            }
        }
    }

    /// Cancel on the overlay (or leaving the screen): clears the overlay at once; the page being
    /// recognised finishes in the background and its run ends without touching the state.
    private func cancelOCR() {
        ocrTask?.cancel()
        ocrTask = nil
        progress = nil
        ocrGeneration += 1
    }
}
