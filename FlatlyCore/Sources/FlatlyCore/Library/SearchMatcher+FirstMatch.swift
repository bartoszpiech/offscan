import Foundation

extension SearchMatcher {
    /// The first OCR line that contains the query, for a search result snippet: the whole query
    /// when it has several tokens, otherwise (or when no line has the whole phrase) each token in
    /// order. Uses the same folding as `score` (case, diacritics, "ł" → "l").
    ///
    /// Each page is normalised once and only a page that contains the query is split into lines,
    /// so title-only matches and long documents stay cheap. Returns nil for a blank query or when
    /// no single line contains the query (e.g. a title-only match).
    ///
    /// The snippet starts at most about 20 characters before the hit (`min(20, maxLength / 3)`),
    /// at the earliest whole word that fits, so the hit is near the start of the first visible
    /// line; it is at most `maxLength` characters plus "…" where the line was cut.
    /// - Parameters:
    ///   - pages: the OCR text of each page, in page order (lines separated by newlines).
    ///   - maxLength: longest snippet in `Character`s before "…" are added (at least 20).
    public func firstMatch(for query: PreparedQuery, inPages pages: [String], maxLength: Int = 80) -> SearchMatch? {
        firstMatch(for: query, inPages: pages, maxLength: maxLength) { normalize(pages[$0]) }
    }

    /// `firstMatch(for:inPages:maxLength:)` with each page's normalised text supplied by the caller,
    /// so it can be cached across queries (a library search re-runs this on every keystroke).
    ///
    /// `normalizedPage(index)` must return `normalize(pages[index])`. It is called at most once per
    /// page, in page order, and only until a page contains the query.
    public func firstMatch(
        for query: PreparedQuery,
        inPages pages: [String],
        maxLength: Int = 80,
        normalizedPage: (Int) -> String
    ) -> SearchMatch? {
        guard !query.isEmpty else { return nil }
        let maxLength = max(maxLength, 20)
        var needles: [String] = []
        if query.tokens.count > 1 { needles.append(query.normalized) }
        needles += query.tokens
        for (pageIndex, page) in pages.enumerated() {
            let folded = normalizedPage(pageIndex)
            guard needles.contains(where: { Self.contains(folded, $0) }) else { continue }
            let lines = page.split(whereSeparator: \.isNewline).map(String.init)
            let normalizedLines = lines.map(normalize)
            for needle in needles {
                // A phrase broken across a line break matches the page but no line: next needle.
                guard let line = normalizedLines.firstIndex(where: { Self.contains($0, needle) }) else { continue }
                return Self.snippet(of: lines[line], needle: needle, pageIndex: pageIndex, maxLength: maxLength)
            }
        }
        return nil
    }

    /// The line with whitespace collapsed, starting a few words before the hit of `needle` and
    /// shortened to `maxLength` (see `firstMatch(for:inPages:maxLength:)`).
    private static func snippet(of line: String, needle: String, pageIndex: Int, maxLength: Int) -> SearchMatch {
        let display = line.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        // "ł" has no decomposition; replacing it keeps the Character count, so offsets in `probe`
        // are offsets in `display`.
        let probe = display.replacingOccurrences(of: "ł", with: "l").replacingOccurrences(of: "Ł", with: "L")
        var hit: Range<Int>?
        if let range = probe.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive]) {
            let lower = probe.distance(from: probe.startIndex, to: range.lowerBound)
            hit = lower..<(lower + probe.distance(from: range.lowerBound, to: range.upperBound))
        }
        let characters = Array(display)
        // At most `lead` characters before the hit, from the earliest word start in that window
        // (mid-word only when the hit is inside a longer word). Also for short lines: a hit at the
        // end of one must not wrap out of sight.
        let lead = min(20, maxLength / 3)
        var start = 0
        if let hit, hit.lowerBound > lead {
            start = hit.lowerBound - lead
            for i in (hit.lowerBound - lead)...hit.lowerBound where characters[i - 1].isWhitespace {
                start = i
                break
            }
        }
        let end = min(characters.count, start + maxLength)
        guard start > 0 || end < characters.count else {
            return SearchMatch(pageIndex: pageIndex, snippet: display, highlight: hit)
        }
        var lower = start, upper = end
        while lower < upper, characters[lower].isWhitespace { lower += 1 }
        while upper > lower, characters[upper - 1].isWhitespace { upper -= 1 }
        let prefix = start > 0 ? "…" : ""
        let suffix = end < characters.count ? "…" : ""
        let body = String(characters[lower..<upper])
        let shift = prefix.count - lower
        let highlight = hit.flatMap { h -> Range<Int>? in
            let l = max(h.lowerBound + shift, prefix.count)
            let u = min(h.upperBound + shift, prefix.count + body.count)
            return l < u ? l..<u : nil
        }
        return SearchMatch(pageIndex: pageIndex, snippet: prefix + body + suffix, highlight: highlight)
    }
}
