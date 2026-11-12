import Foundation

/// Default, date-based document titles, and file names for exported documents.
public enum DocumentNaming {
    /// Longest file name APFS accepts, in UTF-8 bytes.
    static let maximumFileNameBytes = 255
    /// e.g. `defaultTitle(prefix: "Scan", date: d)` → "Scan 2026-10-08 14.32"
    ///
    /// The date part uses a fixed `yyyy-MM-dd HH.mm` format (POSIX digits) in `calendar`'s time
    /// zone, so the title is filename-safe (no colons or slashes).
    public static func defaultTitle(prefix: String, date: Date, calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd HH.mm"
        let stamp = formatter.string(from: date)
        let trimmed = prefix.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? stamp : "\(trimmed) \(stamp)"
    }

    /// Returns `title` unchanged if unused, otherwise "title (2)", "title (3)", …
    public static func uniqueTitle(_ title: String, existing: Set<String>) -> String {
        guard existing.contains(title) else { return title }
        var n = 2
        while existing.contains("\(title) (\(n))") { n += 1 }
        return "\(title) (\(n))"
    }

    /// A file name for exporting a document titled `title`, e.g. `fileName(for: "Faktura",
    /// suffix: " 2", pathExtension: "jpg")` → "Faktura 2.jpg".
    ///
    /// `/` becomes `-`, `:` becomes `.`, control characters become spaces, and leading dots are
    /// dropped (no hidden files). `title` is shortened on a character boundary so the whole name,
    /// including `suffix` and the extension, fits in 255 UTF-8 bytes, the APFS limit. Returns
    /// `fallback` (plus suffix and extension) when nothing usable is left of `title`.
    public static func fileName(for title: String, suffix: String = "", pathExtension: String, fallback: String = "Offscan") -> String {
        func cleaned(_ s: String) -> String {
            // Only category Cc: `CharacterSet.controlCharacters` also holds format characters such
            // as the zero-width joiner that emoji and some scripts need.
            var scalars = String.UnicodeScalarView()
            for scalar in s.unicodeScalars {
                scalars.append(scalar.properties.generalCategory == .control ? " " : scalar)
            }
            var name = String(scalars)
                .replacingOccurrences(of: "/", with: "-")
                .replacingOccurrences(of: ":", with: ".")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            while name.hasPrefix(".") { name.removeFirst() }
            return name.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let ending = pathExtension.isEmpty ? suffix : "\(suffix).\(pathExtension)"
        let budget = maximumFileNameBytes - ending.utf8.count

        var base = cleaned(title)
        if base.utf8.count > budget {
            var shortened = ""
            var bytes = 0
            for character in base {
                bytes += character.utf8.count
                if bytes > budget { break }
                shortened.append(character)
            }
            base = shortened.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if base.isEmpty { base = cleaned(fallback) }
        return base + ending
    }
}
