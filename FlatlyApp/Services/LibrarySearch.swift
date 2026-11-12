import Foundation
import FlatlyCore

/// Ranks documents for the library search. Each document's title and OCR text are normalised once
/// and cached until they change, so typing in the search field doesn't re-normalise the whole
/// library on every keystroke (that took about 0.25 s per character for 50 OCR'd documents).
/// `warm(_:)` fills the cache in the background when the search field is activated, so even the
/// first keystroke doesn't normalise the library on the main thread.
///
/// Result snippets (`firstMatch(in:query:)`) reuse each page's normalised text, filled lazily and
/// only for cards on screen, and the last match per document while the query and its pages are
/// unchanged, so re-rendering results normalises nothing. `warm` deliberately doesn't fill that
/// cache: reading every document's pages would fault them all in on the main actor.
@MainActor
final class LibrarySearch {
    private struct Entry {
        let title: String
        let content: String
        let text: SearchMatcher.PreparedText
    }

    /// A document's pages for snippets. `pages` (raw OCR text per page, in page order) is the key:
    /// page order and count matter, and snippets need each page's text separately (the match's
    /// page number), which the joined `ScanDocument.ocrText` loses.
    private struct PageCache {
        let pages: [String]
        /// `normalize(pages[i])`, filled on first use.
        var normalized: [String?]
        var lastQuery: SearchMatcher.PreparedQuery?
        var lastMatch: SearchMatch?
    }

    /// What a background warm-up needs from one document; `ScanDocument` never leaves the main actor.
    private struct Snapshot: Sendable {
        let id: UUID
        let title: String
        let content: String
    }

    private let matcher = SearchMatcher()
    private var entries: [UUID: Entry] = [:]
    private var pageCaches: [UUID: PageCache] = [:]
    /// Documents whose text a warm-up is normalising right now.
    private var warming: Set<UUID> = []

    /// The documents matching `query`, best match first (ties: most recently modified), or nil
    /// when `query` is blank, i.e. there is nothing to search for.
    func ranked(_ documents: [ScanDocument], query: String) -> [ScanDocument]? {
        let prepared = matcher.prepare(query: query)
        guard !prepared.isEmpty else { return nil }
        return documents
            .compactMap { document -> (document: ScanDocument, score: Int)? in
                let score = matcher.score(prepared, in: text(for: document))
                return score > 0 ? (document, score) : nil
            }
            .sorted { a, b in
                if a.score != b.score { return a.score > b.score }
                return a.document.modifiedAt > b.document.modifiedAt
            }
            .map(\.document)
    }

    /// Normalises, off the main actor, every document that has no up-to-date cache entry, so the
    /// first keystroke of a search doesn't do it on the main thread. Call it when the search field
    /// is activated. Lookups still compare title and content, so an entry that went stale in the
    /// meantime is simply recomputed.
    func warm(_ documents: [ScanDocument]) async {
        let snapshots = documents.compactMap { document -> Snapshot? in
            let title = document.title, content = document.ocrText
            if let entry = entries[document.id], entry.title == title, entry.content == content { return nil }
            guard !warming.contains(document.id) else { return nil }
            return Snapshot(id: document.id, title: title, content: content)
        }
        guard !snapshots.isEmpty else { return }
        warming.formUnion(snapshots.map(\.id))
        let matcher = self.matcher
        let prepared = await Task.detached(priority: .userInitiated) {
            snapshots.map { matcher.prepare(title: $0.title, content: $0.content) }
        }.value
        // Only the snapshots are used from here on: a document may have been deleted meanwhile.
        for (snapshot, text) in zip(snapshots, prepared) {
            // No longer in `warming`: the document was deleted (`forget`) while this ran.
            guard warming.remove(snapshot.id) != nil else { continue }
            entries[snapshot.id] = Entry(title: snapshot.title, content: snapshot.content, text: text)
        }
    }

    /// Where `query` was found in the document's OCR text, for a search result card (see
    /// `SearchMatcher.firstMatch`). Each page is normalised at most once until its text changes,
    /// and the result is reused while the query and the pages are unchanged.
    func firstMatch(in document: ScanDocument, query: SearchMatcher.PreparedQuery) -> SearchMatch? {
        guard !query.isEmpty else { return nil }
        let pages = document.orderedPages.map(\.ocrText)
        var cache = pageCaches[document.id].flatMap { $0.pages == pages ? $0 : nil }
            ?? PageCache(pages: pages, normalized: Array(repeating: nil, count: pages.count))
        if cache.lastQuery == query { return cache.lastMatch }
        let matcher = self.matcher
        let match = matcher.firstMatch(for: query, inPages: pages) { index in
            if let text = cache.normalized[index] { return text }
            let text = matcher.normalize(pages[index])
            cache.normalized[index] = text
            return text
        }
        cache.lastQuery = query
        cache.lastMatch = match
        pageCaches[document.id] = cache
        return match
    }

    /// Drops the cached text of a deleted document.
    func forget(_ documentID: UUID) {
        entries[documentID] = nil
        pageCaches[documentID] = nil
        warming.remove(documentID)
    }

    private func text(for document: ScanDocument) -> SearchMatcher.PreparedText {
        let title = document.title
        let content = document.ocrText
        if let entry = entries[document.id], entry.title == title, entry.content == content {
            return entry.text
        }
        let text = matcher.prepare(title: title, content: content)
        entries[document.id] = Entry(title: title, content: content, text: text)
        return text
    }
}
