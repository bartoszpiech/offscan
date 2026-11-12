import Foundation
import CoreGraphics

extension OCRResult {
    /// Text for reading, copying and sharing. Lines that Vision split only because a printed
    /// paragraph wrapped are joined with a space, and a line-end hyphen is removed when the word
    /// continues in lowercase. Other line breaks are kept, and a visible blank gap on the page
    /// becomes an empty line. `text` stays one line per observation (search, PDF text layer).
    ///
    /// A line continues the previous one only when it starts right below it (gap under 0.8 line
    /// heights), at a similar height and left edge (a hanging indent is fine), the previous line
    /// reaches the right side of the text block, has at least three words and doesn't end a
    /// sentence or with a number, the new line doesn't start a list item, number or heading, and
    /// they aren't two receipt rows with amounts.
    public var readableText: String {
        let items = lines.compactMap { line -> (text: String, box: CGRect)? in
            let text = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : (text, line.boundingBox.standardized)
        }
        guard let first = items.first else { return "" }
        guard items.count > 1 else { return first.text }
        let right = items.map(\.box.maxX).max() ?? 1
        let left = items.map(\.box.minX).min() ?? 0
        let blockWidth = max(right - left, 0.0001)

        var out = first.text
        for (a, b) in zip(items, items.dropFirst()) {
            let gap = a.box.minY - b.box.maxY   // Vision boxes: bottom-left origin
            let tallest = max(a.box.height, b.box.height)
            if Self.continues(a, b, gap: gap, right: right, blockWidth: blockWidth) {
                if Self.endsWithWordHyphen(a.text) {
                    // "agree-" + "ment" → "agreement"; "Kraków-" + "Nowa Huta" keeps the hyphen.
                    if b.text.first?.isLowercase == true { out.removeLast() }
                    out += b.text
                } else {
                    out += " " + b.text
                }
            } else {
                out += (gap >= tallest ? "\n\n" : "\n") + b.text
            }
        }
        return out
    }

    private static func continues(_ a: (text: String, box: CGRect), _ b: (text: String, box: CGRect), gap: CGFloat, right: CGFloat, blockWidth: CGFloat) -> Bool {
        let hA = a.box.height, hB = b.box.height
        guard hA > 0, hB > 0 else { return false }
        // Directly below (not on the same row, not after a blank gap).
        guard gap >= -0.1 * hA, gap < 0.8 * hA else { return false }
        // Same text size (a heading above body text stays apart).
        guard min(hA, hB) / max(hA, hB) >= 0.7 else { return false }
        // The previous line doesn't end a sentence or with a number (e.g. "…w miesiącu: 45").
        guard let last = a.text.last, !".:;!?".contains(last), !last.isNumber else { return false }
        // The new line doesn't start a number, list item or heading marker.
        guard let firstCharacter = b.text.first, !firstCharacter.isNumber,
              b.text.range(of: #"^([A-Za-z][.)]\s|§|[•·▪◦*\-–—])"#, options: .regularExpression) == nil else { return false }
        // Same left edge, or a hanging indent.
        guard b.box.minX >= a.box.minX - 0.02, b.box.minX <= a.box.minX + 0.1 else { return false }
        // The previous line was wrapped: it reaches the right side of the text block…
        guard a.box.maxX >= right - 0.2 * blockWidth else { return false }
        // …and is prose, not a short label or address line.
        guard a.text.split(whereSeparator: \.isWhitespace).count >= 3 else { return false }
        // Two receipt rows with amounts stay apart.
        let amount = #"\d[.,]\d{2}(?!\d)"#
        if a.text.range(of: amount, options: .regularExpression) != nil,
           b.text.range(of: amount, options: .regularExpression) != nil { return false }
        return true
    }

    /// "agree-" (a letter followed by "-" or U+2010 at the end).
    private static func endsWithWordHyphen(_ text: String) -> Bool {
        guard let last = text.last, last == "-" || last == "\u{2010}" else { return false }
        let beforeLast = text.dropLast().last
        return beforeLast?.isLetter == true
    }
}
