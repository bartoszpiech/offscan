import Foundation

/// Diacritic-insensitive, case-insensitive multi-token matching for library search.
///
/// Normalising is the expensive part (a whole document's OCR text per call). To search a library
/// as the user types, prepare each document once (`prepare(title:content:)`, cached until its text
/// changes) and the query once per keystroke, then call `score(_:in:)`.
public struct SearchMatcher: Sendable {
    public init() {}

    /// A query normalised once for scoring many documents.
    public struct PreparedQuery: Sendable, Hashable {
        /// The whole normalised query (tokens joined by single spaces).
        public let normalized: String
        public let tokens: [String]
        /// A blank query matches everything (and scores 0).
        public var isEmpty: Bool { tokens.isEmpty }
    }

    /// A document's normalised title and content; the content also carries words rejoined across
    /// OCR line-break hyphens (see `lineBreakJoins(in:)`).
    public struct PreparedText: Sendable, Hashable {
        public let title: String
        public let content: String
    }

    public func prepare(query: String) -> PreparedQuery {
        let normalized = normalize(query)
        return PreparedQuery(normalized: normalized, tokens: tokens(of: normalized))
    }

    /// Normalises a document once for scoring many queries. Words that OCR split across lines with
    /// a line-end hyphen ("doku-\nmentów") are rejoined and appended to the content, so both the
    /// fragments and the whole word ("dokumentów") match.
    public func prepare(title: String, content: String) -> PreparedText {
        var normalizedContent = normalize(content)
        let joins = Self.lineBreakJoins(in: content)
        if !joins.isEmpty {
            // Query tokens never contain spaces, so no token can match across this boundary.
            normalizedContent += " " + normalize(joins.joined(separator: " "))
        }
        return PreparedText(title: normalize(title), content: normalizedContent)
    }

    /// Hyphens that can end a line split by hyphenation: hyphen-minus, Unicode hyphen (U+2010)
    /// and soft hyphen (U+00AD).
    static let lineEndHyphens: Set<Character> = ["-", "\u{2010}", "\u{AD}"]

    /// Words split across OCR lines by a line-end hyphen, rejoined, so search finds them.
    ///
    /// Only letters on both sides of the break count ("12-\n2026" and "kwota -\nrazem" give
    /// nothing). Each break gives the hyphenated compound ("Bielsko-\nBiałej" → "Bielsko-Białej")
    /// and, when the next line starts lowercase, also the word without the hyphen
    /// ("doku-\nmentów" → "dokumentów"). A hyphen repeated at the start of the next line (the
    /// Polish rule for compounds broken at their own hyphen, "biało-\n-czerwona") is dropped and
    /// only gives the compound.
    static func lineBreakJoins(in content: String) -> [String] {
        // OCR lines are trimmed, so a line-end hyphen always sits right before the newline.
        // Byte search keeps hyphen-free documents (the common case) almost free.
        guard contains(content, "-\n") || contains(content, "\u{2010}\n") || contains(content, "\u{AD}\n") else { return [] }

        func isBlank(_ c: Character) -> Bool { c == " " || c == "\t" }
        var words: [String] = []
        let lines = content.split(separator: "\n", omittingEmptySubsequences: true)
        for (line, next) in zip(lines, lines.dropFirst()) {
            let end = line.reversed().drop(while: isBlank)
            guard let hyphen = end.first, lineEndHyphens.contains(hyphen) else { continue }
            let head = String(end.dropFirst().prefix(while: \.isLetter).reversed())
            guard !head.isEmpty else { continue }

            var start = next.drop(while: isBlank)
            let repeated = start.first.map { lineEndHyphens.contains($0) } ?? false
            if repeated { start = start.dropFirst() }
            let tail = String(start.prefix(while: \.isLetter))
            guard let first = tail.first else { continue }

            if !repeated && first.isLowercase { words.append(head + tail) }
            words.append(head + "-" + tail)
        }
        return words
    }

    /// `score(query:title:content:)` on prepared input; 0 means no match (or a blank query).
    public func score(_ query: PreparedQuery, in text: PreparedText) -> Int {
        guard !query.isEmpty else { return 0 }
        var total = 0
        for token in query.tokens {
            let inTitle = Self.contains(text.title, token)
            let inContent = Self.contains(text.content, token)
            guard inTitle || inContent else { return 0 }
            if inTitle { total += 3 }
            if inContent { total += 1 }
        }
        if Self.contains(text.title, query.normalized) { total += 2 }
        return total
    }

    /// Substring test on the UTF-8 bytes. Both sides are normalised (diacritics and combining marks
    /// folded away), so this finds what `String.contains` finds, about 60× faster on long texts: a
    /// token that occurs nowhere otherwise costs a full Character-by-Character scan of every document.
    static func contains(_ haystack: String, _ needle: String) -> Bool {
        guard !needle.isEmpty else { return false }   // like Foundation's `contains`
        var haystack = haystack, needle = needle   // `withUTF8` is mutating; native strings don't copy
        return haystack.withUTF8 { h in
            needle.withUTF8 { n in
                guard n.count <= h.count, let hb = h.baseAddress, let nb = n.baseAddress else { return false }
                return memmem(hb, h.count, nb, n.count) != nil
            }
        }
    }

    /// Lowercased with diacritics folded ("Łódź" → "lodz") and whitespace collapsed to single spaces.
    public func normalize(_ s: String) -> String {
        let folded = s.folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: nil)
            .lowercased()
            // "ł" has no Unicode decomposition, so diacritic folding leaves it untouched.
            .replacingOccurrences(of: "ł", with: "l")
        return tokens(of: folded).joined(separator: " ")
    }

    /// True when every whitespace-separated token of `query` occurs in the title or the content.
    /// An empty/blank query matches everything.
    public func matches(query: String, title: String, content: String) -> Bool {
        let prepared = prepare(query: query)
        return prepared.isEmpty || score(prepared, in: prepare(title: title, content: content)) > 0
    }

    /// Higher is better: title hits outrank content hits; more token hits outrank fewer.
    ///
    /// Per query token: +3 if found in the title, +1 if found in the content. +2 bonus when the
    /// whole normalised query is a substring of the title. 0 when the document does not match.
    public func score(query: String, title: String, content: String) -> Int {
        score(prepare(query: query), in: prepare(title: title, content: content))
    }

    private func tokens(of s: String) -> [String] {
        s.split(whereSeparator: { $0.isWhitespace }).map(String.init)
    }
}
