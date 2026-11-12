#if DEBUG
import UIKit

extension DemoLibraryContent {
    /// One-page letter from the homeowners' association inviting to the annual meeting.
    static func buildingLetter(_ l: DemoLanguage, now: Date) -> DemoDocumentSpec {
        let written = daysAgo(8, from: now)
        let meeting = daysAgo(-12, from: now)
        let green = UIColor(red: 0.20, green: 0.42, blue: 0.24, alpha: 1)

        let page = DemoPageSpec(size: a4) { canvas in
            // Letterhead: a small house mark and the association's name.
            let mark = UIBezierPath()
            mark.move(to: CGPoint(x: a4.width / 2, y: 70))
            mark.addLine(to: CGPoint(x: a4.width / 2 + 34, y: 100))
            mark.addLine(to: CGPoint(x: a4.width / 2 + 24, y: 100))
            mark.addLine(to: CGPoint(x: a4.width / 2 + 24, y: 128))
            mark.addLine(to: CGPoint(x: a4.width / 2 - 24, y: 128))
            mark.addLine(to: CGPoint(x: a4.width / 2 - 24, y: 100))
            mark.addLine(to: CGPoint(x: a4.width / 2 - 34, y: 100))
            mark.close()
            green.setFill()
            mark.fill()
            canvas.text(l.t("LINDEN COURT HOMEOWNERS ASSOCIATION", "WSPÓLNOTA MIESZKANIOWA „LIPOWY DWÓR”"), x: a4.width / 2, y: 144, size: 24, weight: .bold, face: .serif, color: green, align: .center, kern: 0.8)
            canvas.text(l.t("10–18 Linden Street · Springfield · board@lindencourt.example", "ul. Lipowa 10–18 · 30-001 Kraków · zarzad@lipowydwor.example"), x: a4.width / 2, y: 182, size: 16, face: .serif, color: DemoPageCanvas.gray, align: .center)
            canvas.line(CGPoint(x: margin, y: 222), CGPoint(x: a4.width - margin, y: 222), color: green, width: 2)

            canvas.text(l.t("Springfield, \(l.longDate(written))", "Kraków, \(l.longDate(written)) r."), x: a4.width - margin, y: 256, size: 18, face: .serif, align: .right)
            var y: CGFloat = 316
            for (index, line) in [
                l.t("Mr Daniel Brooks", "Pan Tomasz Zieliński"),
                l.t("14 Linden Street, Apt 4", "ul. Lipowa 14 m. 4"),
                l.t("Springfield, IL 62701", "30-001 Kraków"),
            ].enumerated() {
                canvas.text(line, x: a4.width - margin - 360, y: y, size: 19, weight: index == 0 ? .semibold : .regular, face: .serif)
                y += 30
            }
            y += 40
            canvas.text(l.t("Re: Annual meeting of owners", "Dotyczy: rocznego zebrania właścicieli lokali"), x: margin, y: y, size: 20, weight: .bold, face: .serif)
            y += 54
            canvas.text(l.t("Dear Mr Brooks,", "Szanowny Panie,"), x: margin, y: y, size: 19, face: .serif)
            y += 44
            y = canvas.paragraph(
                l.t("The Board invites you to the annual meeting of the owners of Linden Court, which will take place on \(l.longDate(meeting)) at 6:00 p.m. in the community room on the ground floor of building 12.",
                    "Zarząd Wspólnoty zaprasza na roczne zebranie właścicieli lokali, które odbędzie się \(l.longDate(meeting)) r. o godz. 18:00 w świetlicy na parterze budynku nr 12."),
                x: margin, y: y, width: contentWidth, size: 19, face: .serif
            ) + 18
            canvas.text(l.t("Agenda:", "Porządek obrad:"), x: margin, y: y, size: 19, weight: .semibold, face: .serif)
            y += 40
            for (index, item) in [
                l.t("Approval of the 2026 financial report.", "Przyjęcie sprawozdania finansowego za 2026 rok."),
                l.t("Discharge of the Board for 2026.", "Udzielenie absolutorium Zarządowi za 2026 rok."),
                l.t("Budget and maintenance fees for 2027.", "Plan gospodarczy i wysokość zaliczek na 2027 rok."),
                l.t("Renovation of the roof and the staircases.", "Remont dachu i klatek schodowych."),
                l.t("Any other business.", "Wolne wnioski."),
            ].enumerated() {
                y = canvas.paragraph("\(index + 1). \(item)", x: margin + 20, y: y, width: contentWidth - 20, size: 19, face: .serif, indent: 26)
            }
            y += 20
            y = canvas.paragraph(
                l.t("If you cannot attend, you may be represented by a person holding your written proxy. The draft budget is available from the Board and on the noticeboard in each entrance.",
                    "Jeżeli nie może Pan uczestniczyć w zebraniu, może Pana reprezentować pełnomocnik na podstawie pisemnego pełnomocnictwa. Projekt planu gospodarczego jest dostępny u Zarządu oraz na tablicach ogłoszeń w klatkach schodowych."),
                x: margin, y: y, width: contentWidth, size: 19, face: .serif
            ) + 46
            canvas.text(l.t("Kind regards,", "Z poważaniem"), x: a4.width - margin - 330, y: y, size: 19, face: .serif)
            canvas.signature(in: CGRect(x: a4.width - margin - 320, y: y + 34, width: 240, height: 88), variant: 2)
            canvas.text(l.t("Helen Carter", "Barbara Nowicka"), x: a4.width - margin - 330, y: y + 132, size: 19, weight: .semibold, face: .serif)
            canvas.text(l.t("Chair of the Board", "Przewodnicząca Zarządu"), x: a4.width - margin - 330, y: y + 160, size: 17, face: .serif, color: DemoPageCanvas.gray)
        }

        return DemoDocumentSpec(
            title: l.t("Letter – annual owners' meeting", "Pismo – zebranie wspólnoty"),
            folder: .home,
            age: 6 * day,
            pages: [page]
        )
    }
}
#endif
