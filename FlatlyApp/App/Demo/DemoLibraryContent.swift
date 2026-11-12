#if DEBUG
import UIKit

/// The demo library seeded by `DemoLibrarySeeder`: eight documents (two in each of the two
/// folders), 1–4 pages each, written in the app language. Everything in it is fictional.
///
/// `FlatlyUITests/ScreenshotTests.swift` opens documents and folders by title prefix ("Lease
/// agreement" / "Umowa najmu", "Invoice" / "Faktura", "Receipt" / "Paragon", "Library card" /
/// "Karta biblioteczna", "Health" / "Zdrowie") and searches for "total" / "razem": keep those in
/// sync. The merge test relies on the invoice and the library card having 2 pages each.
enum DemoLibraryContent {
    /// A4 at about 127 dpi.
    static let a4 = CGSize(width: 1050, height: 1485)
    static let margin: CGFloat = 92
    static var contentWidth: CGFloat { a4.width - 2 * margin }

    static func documents(language l: DemoLanguage, now: Date) -> [DemoDocumentSpec] {
        [
            leaseAgreement(l, now: now),
            invoice(l, now: now),
            receipt(l, now: now),
            libraryCard(l, now: now),
            electricityBill(l, now: now),
            buildingLetter(l, now: now),
            medicalCertificate(l, now: now),
            bloodTestResults(l, now: now),
        ]
    }

    // MARK: Shared helpers

    static let hour: TimeInterval = 3600
    static let day: TimeInterval = 86_400

    static func daysAgo(_ days: Double, from now: Date) -> Date {
        now.addingTimeInterval(-days * day)
    }

    /// `date` at the given time of day (receipts and lab reports print a time).
    static func at(_ date: Date, hour: Int, minute: Int) -> Date {
        Calendar(identifier: .gregorian).date(bySettingHour: hour, minute: minute, second: 0, of: date) ?? date
    }

    /// "Page 1 of 4" / "Strona 1 z 4", centred at the bottom.
    static func pageFooter(_ canvas: DemoPageCanvas, _ l: DemoLanguage, page: Int, of count: Int) {
        canvas.text(
            l.t("Page \(page) of \(count)", "Strona \(page) z \(count)"),
            x: canvas.size.width / 2, y: canvas.size.height - 70, size: 16, color: DemoPageCanvas.gray, align: .center
        )
    }

    /// A bold heading followed by numbered clauses with a hanging indent. Returns the y below.
    @discardableResult
    static func section(_ canvas: DemoPageCanvas, title: String, clauses: [String], y: CGFloat, face: DemoPageCanvas.Face = .serif) -> CGFloat {
        var top = y
        canvas.text(title, x: margin, y: top, size: 23, weight: .bold, face: face)
        top += 42
        for (index, clause) in clauses.enumerated() {
            top = canvas.paragraph(
                clauses.count > 1 ? "\(index + 1). \(clause)" : clause,
                x: margin, y: top, width: contentWidth, size: 19, face: face, indent: clauses.count > 1 ? 26 : 0
            )
            top += 8
        }
        return top + 18
    }
}
#endif
