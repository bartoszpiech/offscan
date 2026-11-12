import Testing
@testable import FlatlyCore

struct SearchMatcherTests {
    let matcher = SearchMatcher()

    @Test func normalizeFoldsDiacriticsCaseAndWhitespace() {
        #expect(matcher.normalize("  Faktura   ŁÓDŹ\n zażółć ") == "faktura lodz zazolc")
    }

    @Test func asciiQueryMatchesPolishTitle() {
        #expect(matcher.matches(query: "lodz", title: "Faktura Łódź", content: ""))
    }

    @Test func tokensCanComeFromContent() {
        #expect(matcher.matches(query: "FAKTURA 2026", title: "Scan 2026-10-08", content: "faktura nr 12/2026"))
        #expect(matcher.matches(query: "FAKTURA 2026", title: "", content: "faktura nr 12/2026"))
    }

    @Test func everyTokenMustMatch() {
        #expect(!matcher.matches(query: "faktura gdansk", title: "Faktura Łódź", content: "nr 12/2026"))
    }

    @Test func blankQueryMatchesEverything() {
        #expect(matcher.matches(query: "", title: "A", content: "B"))
        #expect(matcher.matches(query: "   \n", title: "A", content: "B"))
    }

    @Test func scoreRanksTitleHitsAboveContentHits() {
        let titleHit = matcher.score(query: "lodz", title: "Faktura Łódź", content: "")
        let contentHit = matcher.score(query: "lodz", title: "Scan", content: "ul. Piotrkowska, Łódź")
        let both = matcher.score(query: "lodz", title: "Łódź", content: "Łódź")
        let none = matcher.score(query: "lodz", title: "Scan", content: "Warszawa")
        #expect(titleHit == 5)       // +3 title, +2 whole query in title
        #expect(contentHit == 1)
        #expect(both == 6)
        #expect(none == 0)
        #expect(both > titleHit && titleHit > contentHit && contentHit > none)
    }

    @Test func scoreRewardsMoreTokenHits() {
        let two = matcher.score(query: "faktura lodz", title: "Faktura Łódź", content: "")
        let partialPhrase = matcher.score(query: "faktura lodz", title: "Faktura", content: "Łódź")
        #expect(two == 3 + 3 + 2)
        #expect(partialPhrase == 3 + 1)
        #expect(two > partialPhrase)
        #expect(matcher.score(query: "faktura gdansk", title: "Faktura", content: "") == 0)
    }

    @Test func preparedScoringMatchesTheStringAPI() {
        let queries = ["lodz", "FAKTURA 2026", "faktura gdansk", "", "  \n", "zażółć gęślą", "łódź piotrkowska", "dokumentow najmu"]
        let documents = [
            ("Faktura Łódź", ""),
            ("Scan 2026-10-08", "faktura nr 12/2026\nul. Piotrkowska, Łódź"),
            ("Zażółć", "gęślą jaźń"),
            ("", ""),
            ("Umowa", "doku-\nmentów naj-\nmu"),
        ]
        for query in queries {
            let prepared = matcher.prepare(query: query)
            for (title, content) in documents {
                let text = matcher.prepare(title: title, content: content)
                #expect(matcher.score(prepared, in: text) == matcher.score(query: query, title: title, content: content),
                        "query \(query) title \(title)")
                #expect(prepared.isEmpty || (matcher.score(prepared, in: text) > 0) == matcher.matches(query: query, title: title, content: content),
                        "query \(query) title \(title)")
            }
        }
    }

    @Test func byteSubstringSearchAgreesWithStringContains() {
        let texts = ["", "a", "faktura nr 12/2026", "lodz piotrkowska", "zazolc gesla jazn", "ﬁ ligature 😀 emoji"]
        let needles = ["", "a", "2026", "lodz", "gesla jazn", "x", "faktura nr 12/2026 more", "😀", "emoji"]
        for text in texts {
            for needle in needles {
                #expect(SearchMatcher.contains(text, needle) == text.contains(needle), "\(text) / \(needle)")
            }
        }
    }

    // MARK: Line-break hyphenation

    @Test func findsWordsHyphenatedAcrossLines() {
        let content = "Potwierdzam odbiór doku-\nmentów dotyczących umowy naj-\nmu lokalu."
        for query in ["dokumentów", "dokumentow", "najmu", "odbior", "doku", "mentow"] {
            #expect(matcher.matches(query: query, title: "Scan", content: content), "\(query)")
        }
        #expect(matcher.score(query: "najmu", title: "Scan", content: content) == 1)
        #expect(!matcher.matches(query: "dokumentowdotyczacych", title: "Scan", content: content))
    }

    @Test func rejoinsCompoundsBrokenAtTheirHyphen() {
        let city = "ul. Główna 1, Bielsko-\nBiała"
        for query in ["bielsko-biala", "Bielsko-Biała", "bielsko", "biala"] {
            #expect(matcher.matches(query: query, title: "Scan", content: city), "\(query)")
        }
        #expect(!matcher.matches(query: "bielskobiala", title: "Scan", content: city))

        let flag = "flaga biało-\n-czerwona"
        for query in ["biało-czerwona", "bialo-czerwona", "bialo", "czerwona"] {
            #expect(matcher.matches(query: query, title: "Scan", content: flag), "\(query)")
        }
        #expect(!matcher.matches(query: "bialoczerwona", title: "Scan", content: flag))
    }

    @Test func doesNotJoinAcrossNonWordBreaks() {
        #expect(SearchMatcher.lineBreakJoins(in: "12-\n2026") == [])
        #expect(SearchMatcher.lineBreakJoins(in: "kwota - \nrazem") == [])
        #expect(SearchMatcher.lineBreakJoins(in: "kwota -\nrazem") == [])
        #expect(SearchMatcher.lineBreakJoins(in: "Kowalski-\nNowak") == ["Kowalski-Nowak"])
        #expect(SearchMatcher.lineBreakJoins(in: "bez myślników\ntutaj") == [])
        #expect(SearchMatcher.lineBreakJoins(in: "na końcu-") == [])
        #expect(SearchMatcher.lineBreakJoins(in: "") == [])
    }

    @Test func softAndUnicodeHyphensAtLineEnd() {
        #expect(SearchMatcher.lineBreakJoins(in: "faktu\u{AD}\nra").contains("faktura"))
        #expect(SearchMatcher.lineBreakJoins(in: "faktu\u{2010}\nra").contains("faktura"))
        #expect(matcher.matches(query: "faktura", title: "", content: "Nr faktu\u{AD}\nra VAT"))
    }

    @Test func rejoinsEveryBreakInOrder() {
        let content = "Potwierdzam odbiór doku-\nmentów dotyczących umowy naj-\nmu lokalu w Bielsko-\nBiałej, flaga biało-\n-czerwona.\n12-\n2026 - \nkoniec"
        #expect(SearchMatcher.lineBreakJoins(in: content) == [
            "dokumentów", "doku-mentów", "najmu", "naj-mu", "Bielsko-Białej", "biało-czerwona"
        ])
    }

    @Test func contentWithoutLineEndHyphensPreparesAsBefore() {
        let content = "faktura nr 12/2026\nul. Piotrkowska - Łódź\n2026-10-08"
        #expect(matcher.prepare(title: "T", content: content).content == matcher.normalize(content))
    }

    @Test func blankPreparedQueryIsEmptyAndScoresZero() {
        let blank = matcher.prepare(query: " \n ")
        #expect(blank.isEmpty)
        #expect(matcher.score(blank, in: matcher.prepare(title: "A", content: "B")) == 0)
    }
}
