import Testing
import CoreGraphics
@testable import FlatlyCore

/// `OCRResult.readableText`: wrapped paragraph lines are joined, everything else keeps its breaks.
struct OCRReadableTextTests {
    /// A line at a top-left position (stored as Vision's bottom-left box).
    private func line(_ text: String, x: CGFloat = 0.09, top: CGFloat, width: CGFloat = 0.80, height: CGFloat = 0.015) -> OCRLine {
        OCRLine(text: text, boundingBox: CGRect(x: x, y: 1 - top - height, width: width, height: height), confidence: 1)
    }

    /// Full-width lines with a regular line pitch.
    private func paragraph(_ texts: [String], top: CGFloat = 0.10, pitch: CGFloat = 0.021) -> [OCRLine] {
        texts.enumerated().map { i, text in line(text, top: top + CGFloat(i) * pitch) }
    }

    @Test func emptyAndSingleLine() {
        #expect(OCRResult.empty.readableText == "")
        #expect(OCRResult(lines: [line("  Hello world  ", top: 0.1)]).readableText == "Hello world")
    }

    @Test func joinsWrappedParagraph() {
        let result = OCRResult(lines: [
            line("The Landlord leases to the Tenant the apartment at 14 Linden Street, Apt 4, Springfield, with a", top: 0.10, width: 0.80),
            line("floor area of 52 m², consisting of two rooms, a kitchen, a bathroom", top: 0.121, width: 0.79),
            line("and a hallway.", top: 0.142, width: 0.40),
        ])
        #expect(result.readableText == "The Landlord leases to the Tenant the apartment at 14 Linden Street, Apt 4, Springfield, with a floor area of 52 m², consisting of two rooms, a kitchen, a bathroom and a hallway.")
    }

    @Test func hangingIndentClauseMerges() {
        let result = OCRResult(lines: [
            line("1. Margaret Hale, residing at 8 Rose Lane, Springfield, hereinafter referred to as the", top: 0.10, width: 0.80),
            line("“Landlord”, and", x: 0.115, top: 0.121, width: 0.15),
        ])
        #expect(result.readableText == "1. Margaret Hale, residing at 8 Rose Lane, Springfield, hereinafter referred to as the “Landlord”, and")
    }

    @Test func numberedAndBulletItemsStaySeparate() {
        let texts = [
            "1. The Tenant pays the rent by the tenth day of each month and keeps the flat",
            "2. The Landlord repairs the heating and the water installation at his own cost",
            "• Keys are returned to the Landlord when the agreement ends and the flat is empty",
            "§ 2. Term",
        ]
        #expect(OCRResult(lines: paragraph(texts)).readableText == texts.joined(separator: "\n"))
    }

    @Test func addressLinesStaySeparate() {
        let result = OCRResult(lines: [
            line("This agreement is made between the parties named below on the first day of May.", top: 0.10),
            line("Jan Kowalski", top: 0.30, width: 0.20),
            line("ul. Długa 5", top: 0.321, width: 0.18),
            line("30-215 Kraków", top: 0.342, width: 0.22),
        ])
        #expect(result.readableText.hasSuffix("\nJan Kowalski\nul. Długa 5\n30-215 Kraków"))
    }

    @Test func sentenceEndBreaksLine() {
        let texts = [
            "The deposit is returned within thirty days after the flat is handed back.",
            "Any damage beyond normal wear is deducted from the deposit by the Landlord",
        ]
        #expect(OCRResult(lines: paragraph(texts)).readableText == texts.joined(separator: "\n"))
    }

    @Test func lineEndingInNumberStaysSeparate() {
        let texts = [
            "Łączna liczba godzin zajęć w pracowni ceramiki zrealizowanych w miesiącu listopadzie: 45",
            "Potwierdzenie zrealizowania zajęć - podpis prowadzącej:",
        ]
        #expect(OCRResult(lines: paragraph(texts)).readableText == texts.joined(separator: "\n"))
    }

    @Test func receiptRowsStaySeparate() {
        let texts = ["MLEKO UHT 3,2% 1L 3,49 A", "CHLEB PSZENNY KROJONY 4,99 A"]
        #expect(OCRResult(lines: paragraph(texts)).readableText == texts.joined(separator: "\n"))
    }

    @Test func sameRowCellsStaySeparate() {
        let result = OCRResult(lines: [
            line("Description of the service provided", x: 0.09, top: 0.50, width: 0.45),
            line("Amount due", x: 0.65, top: 0.50, width: 0.25),
        ])
        #expect(result.readableText == "Description of the service provided\nAmount due")
    }

    @Test func headingHeightDiffersStaysSeparate() {
        let result = OCRResult(lines: [
            line("Terms and conditions of the residential lease", top: 0.10, height: 0.022),
            line("The following terms apply to the whole duration of the lease agreement", top: 0.127),
        ])
        #expect(result.readableText == "Terms and conditions of the residential lease\nThe following terms apply to the whole duration of the lease agreement")
    }

    @Test func blankLineForLargeGap() {
        let result = OCRResult(lines: [
            line("The first paragraph talks about the rent and when it has to be paid", top: 0.10),
            // 1.3 line heights of empty space.
            line("The second paragraph talks about the deposit and the keys of the flat", top: 0.10 + 0.015 + 0.0195),
        ])
        #expect(result.readableText == "The first paragraph talks about the rent and when it has to be paid\n\nThe second paragraph talks about the deposit and the keys of the flat")
    }

    @Test func dehyphenation() {
        let word = OCRResult(lines: paragraph([
            "Both parties confirm that they have read the agree-",
            "ment is binding for both of them from the day of signing",
        ]))
        #expect(word.readableText == "Both parties confirm that they have read the agreement is binding for both of them from the day of signing")
        let compound = OCRResult(lines: paragraph([
            "The apartment is located in the quiet part of Kraków-",
            "Nowa Huta district, close to the tram stop and shops",
        ]))
        #expect(compound.readableText == "The apartment is located in the quiet part of Kraków-Nowa Huta district, close to the tram stop and shops")
    }

    @Test func textUnchanged() {
        let lines = paragraph(["one two three four", "five six seven eight"])
        let result = OCRResult(lines: lines)
        #expect(result.text == lines.map(\.text).joined(separator: "\n"))
    }
}
