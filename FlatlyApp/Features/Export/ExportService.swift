import Foundation
import FlatlyCore

/// Builds a document's export files. Shared by `ExportSheet` and the one-tap "Share PDF" actions
/// (`quickPDFShare`) so every path produces identical files.
///
/// `prepareRequest(documentID:…)` waits for pending text recognition (PDF only) and then snapshots
/// what is needed from the main-actor models (`request(for:…)`); `export` then renders through
/// `ScanProcessor` off the main actor and never touches SwiftData.
///
/// Only `ExportSheet` passes a PDF password; the one-tap Share PDF and batch exports never do.
@MainActor
enum ExportService {
    /// Everything needed to export a document, detached from its model objects.
    struct Request: Sendable {
        let pageIDs: [UUID]
        let ocr: [UUID: OCRResult]
        let title: String
        let format: ExportFormat
        let pageSize: PageSizeOption
        let compression: CompressionLevel
        /// Encrypts the PDF when set; always nil for JPG. Lives only as long as the request.
        let password: String?
    }

    /// Snapshots the request for `documentID`. For a PDF it first recognises the text of any page
    /// still pending (e.g. a scan made seconds ago), so the text layer is complete; `onRecognizing`
    /// is called before that wait so the caller can say so in its progress overlay. Returns nil
    /// when the document is gone or has no pages. Throws `CancellationError` if cancelled meanwhile.
    /// `password` (PDF only, ignored for JPG) encrypts the exported PDF.
    static func prepareRequest(
        documentID: UUID,
        format: ExportFormat,
        pageSize: PageSizeOption,
        compression: CompressionLevel,
        password: String? = nil,
        services: AppServices,
        onRecognizing: () -> Void
    ) async throws -> Request? {
        guard let document = services.store.document(id: documentID), !document.pages.isEmpty else { return nil }
        if format == .pdf {
            let pending = document.orderedPages.filter { $0.ocrData == nil }.map(\.id)
            if !pending.isEmpty {
                onRecognizing()
                // Backwards: the scan's own OCR works forwards, so the two meet in the middle.
                await services.assembler.recognizePendingText(forPageIDs: pending.reversed())
                try Task.checkCancellation()
            }
        }
        // Re-resolve after the await: never hold a model object across background work.
        guard let current = services.store.document(id: documentID), !current.pages.isEmpty else { return nil }
        return request(for: current, format: format, pageSize: pageSize, compression: compression, password: password)
    }

    static func request(
        for document: ScanDocument,
        format: ExportFormat,
        pageSize: PageSizeOption,
        compression: CompressionLevel,
        password: String? = nil
    ) -> Request {
        let pages = document.orderedPages
        var ocr: [UUID: OCRResult] = [:]
        for page in pages {
            if let result = page.ocr { ocr[page.id] = result }
        }
        return Request(
            pageIDs: pages.map(\.id),
            ocr: ocr,
            title: document.title,
            format: format,
            pageSize: pageSize,
            compression: compression,
            password: format == .pdf ? password : nil
        )
    }

    /// Removes earlier temporary exports (unless `cleanPrevious` is false: a batch passes false
    /// after its first export, so the earlier documents' files survive) and writes the new
    /// file(s). Throws `CancellationError` when the calling task was cancelled meanwhile (the new
    /// files are then deleted too).
    ///
    /// Temporary exports are removed at the next export, after Save to Files completes, when a
    /// document is deleted, and at launch. Files handed to the share sheet are kept until then:
    /// AirDrop (which can continue after the sheet closes) and Copy may still read them.
    static func export(_ request: Request, processor: ScanProcessor, cleanPrevious: Bool = true) async throws -> [URL] {
        if cleanPrevious { ScanProcessor.cleanTemporaryExports() }
        let urls: [URL]
        switch request.format {
        case .pdf:
            urls = [try await processor.exportPDF(
                pageIDs: request.pageIDs,
                ocr: request.ocr,
                pageSize: request.pageSize,
                compression: request.compression,
                title: request.title,
                password: request.password
            )]
        case .jpg:
            urls = try await processor.exportJPEGs(pageIDs: request.pageIDs, compression: request.compression, title: request.title)
        }
        if Task.isCancelled {
            ScanProcessor.removeTemporaryExport(urls)
            throw CancellationError()
        }
        return urls
    }

    /// Deletes every temporary export in the background, e.g. after a document is deleted, so no
    /// exported copy of it outlives it.
    static func discardTemporaryFiles() {
        Task.detached(priority: .utility) { ScanProcessor.cleanTemporaryExports() }
    }
}
