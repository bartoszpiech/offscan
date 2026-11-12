import Foundation
import FlatlyCore

/// Memoises each page's readable text for `OCRTextView`, so a page's OCR JSON is decoded and
/// re-flowed (`OCRResult.readableText`) once per OCR result instead of on every body pass
/// (progress updates, Copy feedback, re-recognition of other pages).
///
/// Deliberately not `@Observable`: it is filled while `body` runs and must not invalidate it.
@MainActor
final class ReadableTextCache {
    private struct Entry {
        let ocrData: Data?
        let ocrText: String
        let text: String
    }

    private var entries: [UUID: Entry] = [:]

    /// The pages' texts for reading, copying and sharing, in the given order. A page's text is
    /// recomputed only when its `ocrData` or `ocrText` changed since the last call (the full data
    /// is compared: a hash or byte count could miss a change). Entries of pages no longer passed
    /// in (deleted or moved to another document) are dropped.
    func texts(for pages: [ScanPage]) -> [String] {
        var kept: [UUID: Entry] = [:]
        let texts = pages.map { page -> String in
            let data = page.ocrData, plain = page.ocrText
            if let entry = entries[page.id], entry.ocrData == data, entry.ocrText == plain {
                kept[page.id] = entry
                return entry.text
            }
            // `ocrText` is the fallback when the data is missing or doesn't decode.
            let text = OCRTextView.readableText(of: page)
            kept[page.id] = Entry(ocrData: data, ocrText: plain, text: text)
            return text
        }
        entries = kept
        return texts
    }
}
