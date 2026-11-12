import Testing
import Foundation
@testable import FlatlyCore

/// `SearchMatcher.firstMatch(for:inPages:maxLength:)`: where a library search hit is, for snippets.
struct SearchMatchTests {
    let matcher = SearchMatcher()

    /// Also checks that the overload taking cached normalised pages gives the same result, so
    /// every case below covers both.
    private func match(_ query: String, _ pages: [String], maxLength: Int = 80) -> SearchMatch? {
        let prepared = matcher.prepare(query: query)
        let result = matcher.firstMatch(for: prepared, inPages: pages, maxLength: maxLength)
        let supplied = matcher.firstMatch(for: prepared, inPages: pages, maxLength: maxLength) { matcher.normalize(pages[$0]) }
        #expect(supplied == result)
        return result
    }

    /// The highlighted part of the snippet.
    private func highlighted(_ m: SearchMatch) throws -> String {
        let range = try #require(m.highlight)
        return String(Array(m.snippet)[range])
    }

    @Test func firstMatchFindsPageAndLine() throws {
        let m = try #require(match("total", ["Hello\nWorld", "SUBTOTAL 49.12\nTOTAL 52.19"]))
        #expect(m.pageIndex == 1)
        #expect(m.snippet == "SUBTOTAL 49.12")
        #expect(try highlighted(m) == "TOTAL")
    }

    @Test func firstMatchFoldsPolishLetters() throws {
        for query in ["zaplaty", "ZAPŁATY"] {
            let m = try #require(match(query, ["Razem do zapłaty: 1774,89 zł"]))
            #expect(m.snippet == "Razem do zapłaty: 1774,89 zł")
            #expect(try highlighted(m) == "zapłaty")
        }
        let city = try #require(match("lodz", ["ul. Piotrkowska, Łódź"]))
        #expect(try highlighted(city) == "Łódź")
    }

    @Test func firstMatchPrefersWholePhrase() throws {
        let m = try #require(match("total due", ["Subtotal $643.00\nTotal due $694.44"]))
        #expect(m.snippet == "Total due $694.44")
        #expect(try highlighted(m) == "Total due")
    }

    @Test func firstMatchCollapsesWhitespace() throws {
        let m = try #require(match("due", ["Total     due  5"]))
        #expect(m.snippet == "Total due 5")
    }

    @Test func firstMatchNilForTitleOnlyOrBlank() {
        #expect(match("faktura", ["nothing here"]) == nil)
        #expect(match("   ", ["nothing here"]) == nil)
        #expect(match("faktura", []) == nil)
    }

    @Test func firstMatchSkipsToLaterPage() throws {
        let m = try #require(match("invoice", ["first page", "second page", "the invoice number"]))
        #expect(m.pageIndex == 2)
    }

    @Test func firstMatchPhraseAcrossLineBreakFallsBackToToken() throws {
        let m = try #require(match("total due", ["Total\ndue"]))
        #expect(m.snippet == "Total")
    }

    @Test func firstMatchStopsNormalizingAtHitPage() throws {
        let pages = ["foo", "bar baz", "qux"]
        var asked: [Int] = []
        let m = try #require(matcher.firstMatch(for: matcher.prepare(query: "bar"), inPages: pages) { index in
            asked.append(index)
            return matcher.normalize(pages[index])
        })
        #expect(asked == [0, 1])
        #expect(m.pageIndex == 1)
    }

    @Test func firstMatchUsesSuppliedNormalizedPages() {
        // The supplied text decides which page matches; the snippet still comes from the raw page.
        let m = matcher.firstMatch(for: matcher.prepare(query: "faktura"), inPages: ["Faktura", "Faktura 2"]) { index in
            index == 0 ? "" : "faktura 2"
        }
        #expect(m?.pageIndex == 1)
        #expect(m?.snippet == "Faktura 2")
    }

    @Test func firstMatchShortensLongLineAroundHit() throws {
        let line = String(repeating: "x", count: 150) + " invoice 12"
        let m = try #require(match("invoice", [line], maxLength: 40))
        #expect(m.snippet.hasPrefix("…"))
        #expect(m.snippet.count <= 42)
        #expect(try highlighted(m) == "invoice")
        #expect(try #require(m.highlight).lowerBound <= 21)
    }

    /// A hit late in a long line: the snippet starts a few whole words before it, not mid-line.
    @Test func firstMatchStartsShortlyBeforeLateHit() throws {
        let page = "Komentarz: wyniki powinny być interpretowane przez lekarza kierującego łącznie z obrazem klinicznym."
        let m = try #require(match("razem", [page]))
        #expect(m.snippet == "…łącznie z obrazem klinicznym.")
        #expect(try highlighted(m) == "razem")
        #expect(try #require(m.highlight).lowerBound <= 21)
    }

    /// Short lines are trimmed too when the hit sits near their end, so it can't wrap out of view.
    @Test func firstMatchTrimsShortLineBeforeLateHit() throws {
        let page = "Summary of charges and payments, including the subtotal"
        let m = try #require(match("total", [page]))
        #expect(m.snippet == "…including the subtotal")
        #expect(try highlighted(m) == "total")
        #expect(try #require(m.highlight).lowerBound <= 21)
    }

    /// No word start in reach: the snippet is cut mid-word, the hit still near the start.
    @Test func firstMatchHitInsideLongWordCutsMidWord() throws {
        let page = String(repeating: "x", count: 50) + "total"
        let m = try #require(match("total", [page]))
        #expect(m.snippet.hasPrefix("…"))
        #expect(try highlighted(m) == "total")
        #expect(m.highlight?.lowerBound == 21)
    }
}
