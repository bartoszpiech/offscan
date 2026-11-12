import Foundation

/// Where a search query was found in a document's OCR text, for a result snippet.
public struct SearchMatch: Sendable, Hashable {
    /// Zero-based index of the page whose text contains the hit.
    public let pageIndex: Int
    /// The OCR line with the hit, whitespace collapsed to single spaces. It starts at most about
    /// 20 characters (whole words) before the hit, so the hit is near its start, and is at most the
    /// requested maximum length, with "…" where the line was cut.
    public let snippet: String
    /// Character offsets (Swift `Character`s) of the hit inside `snippet`; nil when the hit can't
    /// be located exactly (the snippet is still valid).
    public let highlight: Range<Int>?

    public init(pageIndex: Int, snippet: String, highlight: Range<Int>?) {
        self.pageIndex = pageIndex
        self.snippet = snippet
        self.highlight = highlight
    }
}
