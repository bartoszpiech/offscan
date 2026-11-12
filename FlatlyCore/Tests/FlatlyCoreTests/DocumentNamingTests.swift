import Testing
import Foundation
@testable import FlatlyCore

struct DocumentNamingTests {
    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    @Test func defaultTitleUsesFixedFormat() {
        // 2026-10-08 14:32:59 UTC
        let date = Date(timeIntervalSince1970: 1_791_469_979)
        #expect(DocumentNaming.defaultTitle(prefix: "Scan", date: date, calendar: utc) == "Scan 2026-10-08 14.32")
    }

    @Test func defaultTitleHonoursCalendarTimeZone() {
        var warsaw = Calendar(identifier: .gregorian)
        warsaw.timeZone = TimeZone(identifier: "Europe/Warsaw")!
        let date = Date(timeIntervalSince1970: 1_791_469_979)   // 16:32 in Warsaw (CEST)
        #expect(DocumentNaming.defaultTitle(prefix: "Skan", date: date, calendar: warsaw) == "Skan 2026-10-08 16.32")
    }

    @Test func defaultTitleIsFilenameSafe() {
        let title = DocumentNaming.defaultTitle(prefix: "Scan", date: .now)
        #expect(!title.contains(":"))
        #expect(!title.contains("/"))
    }

    @Test func uniqueTitleReturnsUnusedTitleUnchanged() {
        #expect(DocumentNaming.uniqueTitle("Invoice", existing: ["Other"]) == "Invoice")
    }

    @Test func uniqueTitleAppendsFirstFreeCounter() {
        #expect(DocumentNaming.uniqueTitle("Invoice", existing: ["Invoice"]) == "Invoice (2)")
        #expect(DocumentNaming.uniqueTitle("Invoice", existing: ["Invoice", "Invoice (2)", "Invoice (3)"]) == "Invoice (4)")
        #expect(DocumentNaming.uniqueTitle("Invoice", existing: ["Invoice", "Invoice (3)"]) == "Invoice (2)")
    }

    // MARK: File names

    @Test func fileNameKeepsOrdinaryTitles() {
        #expect(DocumentNaming.fileName(for: "Faktura Łódź 2026", pathExtension: "pdf") == "Faktura Łódź 2026.pdf")
        #expect(DocumentNaming.fileName(for: "Faktura", suffix: " 2", pathExtension: "jpg") == "Faktura 2.jpg")
    }

    @Test func fileNameReplacesPathSeparatorsAndControlCharacters() {
        #expect(DocumentNaming.fileName(for: "12/2026: umowa", pathExtension: "pdf") == "12-2026. umowa.pdf")
        #expect(DocumentNaming.fileName(for: "a\nb\tc", pathExtension: "pdf") == "a b c.pdf")
    }

    @Test func fileNameNeverStartsWithADot() {
        #expect(DocumentNaming.fileName(for: ".hidden", pathExtension: "pdf") == "hidden.pdf")
        #expect(DocumentNaming.fileName(for: " .. notes", pathExtension: "pdf") == "notes.pdf")
    }

    @Test func fileNameFallsBackWhenNothingIsLeft() {
        #expect(DocumentNaming.fileName(for: "", pathExtension: "pdf") == "Offscan.pdf")
        #expect(DocumentNaming.fileName(for: " ... ", suffix: " 3", pathExtension: "jpg") == "Offscan 3.jpg")
        #expect(DocumentNaming.fileName(for: "...", pathExtension: "pdf", fallback: "Skan") == "Skan.pdf")
    }

    @Test func fileNameFitsTheAPFSLimitWithMultibyteTitles() {
        // "ż" is 2 bytes in UTF-8: 150 of them (300 bytes) plus ".pdf" would not fit in 255 bytes.
        let name = DocumentNaming.fileName(for: String(repeating: "ż", count: 150), pathExtension: "pdf")
        #expect(name.utf8.count <= 255)
        #expect(name == String(repeating: "ż", count: 125) + ".pdf")
    }

    @Test func fileNameKeepsTheSuffixWhenShortening() {
        let name = DocumentNaming.fileName(for: String(repeating: "a", count: 300), suffix: " 12", pathExtension: "jpg")
        #expect(name.utf8.count == 255)
        #expect(name.hasSuffix("a 12.jpg"))
    }

    @Test func fileNameNeverSplitsACharacter() {
        let family = "👨‍👩‍👧"   // one Character, 18 UTF-8 bytes
        let name = DocumentNaming.fileName(for: String(repeating: family, count: 20), pathExtension: "pdf")
        #expect(name.utf8.count <= 255)
        #expect(name.dropLast(4).allSatisfy { $0 == Character(family) })
    }
}
