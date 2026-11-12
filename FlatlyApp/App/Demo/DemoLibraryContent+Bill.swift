#if DEBUG
import UIKit

extension DemoLibraryContent {
    /// Two-page electricity bill with a usage chart and a charges breakdown.
    static func electricityBill(_ l: DemoLanguage, now: Date) -> DemoDocumentSpec {
        let issued = daysAgo(3, from: now)
        let due = issued.addingTimeInterval(21 * day)
        let orange = UIColor(red: 0.93, green: 0.45, blue: 0.09, alpha: 1)
        let navy = UIColor(red: 0.12, green: 0.20, blue: 0.36, alpha: 1)
        let usage: [(month: String, kWh: Double)] = l == .polish
            ? [("maj", 268), ("cze", 241), ("lip", 229), ("sie", 236), ("wrz", 284), ("paź", 312)]
            : [("May", 268), ("Jun", 241), ("Jul", 229), ("Aug", 236), ("Sep", 284), ("Oct", 312)]
        let charges: [(String, String, Double)] = l == .polish
            ? [
                ("Energia czynna, taryfa G11", "312 kWh × 0,6212 zł", 193.81),
                ("Opłata handlowa", "2 mies. × 9,99 zł", 19.98),
                ("Opłata sieciowa zmienna", "312 kWh × 0,2786 zł", 86.92),
                ("Opłata sieciowa stała", "2 mies. × 11,23 zł", 22.46),
                ("Opłata mocowa", "2 mies. × 9,50 zł", 19.00),
            ]
            : [
                ("Energy charge", "312 kWh × $0.1840", 57.41),
                ("Customer charge", "2 months × $9.50", 19.00),
                ("Delivery charge", "312 kWh × $0.0915", 28.55),
                ("Transmission charge", "312 kWh × $0.0294", 9.17),
                ("Taxes and fees", "", 14.27),
            ]
        let total = charges.reduce(0) { $0 + $1.2 }
        let netForPolish = total
        let polishGross = (netForPolish * 1.23 * 100).rounded() / 100
        let amountDue = l == .polish ? polishGross : total

        @Sendable func logo(_ canvas: DemoPageCanvas) {
            canvas.circle(center: CGPoint(x: margin + 34, y: 112), radius: 34, fill: orange)
            let bolt = UIBezierPath()
            bolt.move(to: CGPoint(x: margin + 40, y: 88))
            bolt.addLine(to: CGPoint(x: margin + 22, y: 116))
            bolt.addLine(to: CGPoint(x: margin + 34, y: 116))
            bolt.addLine(to: CGPoint(x: margin + 28, y: 138))
            bolt.addLine(to: CGPoint(x: margin + 48, y: 106))
            bolt.addLine(to: CGPoint(x: margin + 36, y: 106))
            bolt.close()
            UIColor.white.setFill()
            bolt.fill()
            canvas.text(l.t("VOLTA ENERGY", "VOLTA ENERGIA"), x: margin + 84, y: 86, size: 30, weight: .heavy, color: navy, kern: 1)
            canvas.text(l.t("Power for every home", "Energia dla każdego domu"), x: margin + 84, y: 122, size: 16, color: DemoPageCanvas.gray)
        }

        let page1 = DemoPageSpec(size: a4) { canvas in
            logo(canvas)
            let right = a4.width - margin
            canvas.text(l.t("Electricity bill", "Faktura za energię elektryczną"), x: right, y: 84, size: 24, weight: .bold, color: navy, align: .right)
            canvas.text(l.t("No. E/10/2026/558213", "nr E/10/2026/558213"), x: right, y: 120, size: 17, color: DemoPageCanvas.gray, align: .right)

            // Customer and account details.
            canvas.fill(CGRect(x: margin, y: 196, width: contentWidth, height: 150), DemoPageCanvas.tint, radius: 10)
            let customer = [
                l.t("Daniel Brooks", "Tomasz Zieliński"),
                l.t("14 Linden Street, Apt 4", "ul. Lipowa 14 m. 4"),
                l.t("Springfield, IL 62701", "30-001 Kraków"),
            ]
            for (index, line) in customer.enumerated() {
                canvas.text(line, x: margin + 24, y: 214 + CGFloat(index) * 30, size: 19, weight: index == 0 ? .semibold : .regular)
            }
            for (index, (label, value)) in [
                (l.t("Customer no.", "Nr klienta"), "2071 5531"),
                (l.t("Issue date", "Data wystawienia"), l.shortDate(issued)),
                (l.t("Billing period", "Okres rozliczeniowy"), "\(l.shortDate(daysAgo(64, from: now))) – \(l.shortDate(daysAgo(4, from: now)))"),
            ].enumerated() {
                canvas.text(label, x: margin + 470, y: 214 + CGFloat(index) * 40, size: 15, color: DemoPageCanvas.gray)
                canvas.text(value, x: right - 24, y: 214 + CGFloat(index) * 40 + 16, size: 17, weight: .semibold, align: .right)
            }

            // Amount due.
            let box = CGRect(x: margin, y: 380, width: contentWidth, height: 128)
            canvas.fill(box, orange.withAlphaComponent(0.1), radius: 12)
            canvas.stroke(box, orange, width: 2.5, radius: 12)
            canvas.text(l.t("Total amount due", "Razem do zapłaty"), x: box.minX + 28, y: box.minY + 26, size: 22, weight: .semibold)
            canvas.text(l.t("Please pay by \(l.shortDate(due))", "Termin płatności: \(l.shortDate(due))"), x: box.minX + 28, y: box.minY + 70, size: 18, color: DemoPageCanvas.gray)
            canvas.text(l.money(amountDue), x: box.maxX - 28, y: box.minY + 30, size: 48, weight: .bold, color: navy, align: .right)

            // Usage chart.
            var y: CGFloat = 560
            canvas.text(l.t("Your electricity usage (kWh)", "Twoje zużycie energii (kWh)"), x: margin, y: y, size: 21, weight: .bold)
            y += 50
            let chartHeight: CGFloat = 230
            let barWidth: CGFloat = 86
            let gap = (contentWidth - CGFloat(usage.count) * barWidth) / CGFloat(usage.count - 1)
            let maximum = usage.map(\.kWh).max() ?? 1
            canvas.line(CGPoint(x: margin, y: y + chartHeight), CGPoint(x: a4.width - margin, y: y + chartHeight), color: DemoPageCanvas.gray, width: 2)
            for (index, entry) in usage.enumerated() {
                let height = chartHeight * 0.86 * entry.kWh / maximum
                let x = margin + CGFloat(index) * (barWidth + gap)
                let isCurrent = index == usage.count - 1
                canvas.fill(CGRect(x: x, y: y + chartHeight - height, width: barWidth, height: height), isCurrent ? orange : navy.withAlphaComponent(0.35), radius: 6)
                canvas.text("\(Int(entry.kWh))", x: x + barWidth / 2, y: y + chartHeight - height - 30, size: 16, weight: .semibold, align: .center)
                canvas.text(entry.month, x: x + barWidth / 2, y: y + chartHeight + 10, size: 16, color: DemoPageCanvas.gray, align: .center)
            }
            y += chartHeight + 70

            canvas.text(l.t("Meter readings", "Odczyty licznika"), x: margin, y: y, size: 21, weight: .bold)
            y = canvas.table(
                x: margin, y: y + 44,
                columns: [
                    .init(title: l.t("Meter", "Licznik"), width: 230),
                    .init(title: l.t("Previous", "Poprzedni"), width: 200, align: .right),
                    .init(title: l.t("Current", "Obecny"), width: 200, align: .right),
                    .init(title: l.t("Usage", "Zużycie"), width: 236, align: .right),
                ],
                rows: [["Z-48812093", l.t("23,106 (A)", "23 106 (O)"), l.t("23,418 (A)", "23 418 (O)"), "312 kWh"]],
                fontSize: 18
            ) + 36
            canvas.paragraph(
                l.t("(A) actual reading taken by our meter reader. Your next reading is planned for early January.",
                    "(O) odczyt rzeczywisty wykonany przez inkasenta. Kolejny odczyt planujemy na początku stycznia."),
                x: margin, y: y, width: contentWidth, size: 16, color: DemoPageCanvas.gray
            )
            canvas.line(CGPoint(x: margin, y: a4.height - 150), CGPoint(x: a4.width - margin, y: a4.height - 150), width: 1.5)
            canvas.text(l.t("Volta Energy Inc. · 1 Power Plaza, Springfield · voltaenergy.example", "Volta Energia S.A. · ul. Energetyków 1, 30-100 Kraków · volta.example"), x: a4.width / 2, y: a4.height - 130, size: 15, color: DemoPageCanvas.gray, align: .center)
            pageFooter(canvas, l, page: 1, of: 2)
        }

        let page2 = DemoPageSpec(size: a4) { canvas in
            logo(canvas)
            var y: CGFloat = 210
            canvas.text(l.t("Charges breakdown", "Rozliczenie opłat"), x: margin, y: y, size: 26, weight: .bold, color: navy)
            y = canvas.table(
                x: margin, y: y + 56,
                columns: [
                    .init(title: l.t("Item", "Pozycja"), width: 380),
                    .init(title: l.t("Calculation", "Wyliczenie"), width: 300),
                    .init(title: l.t("Amount", "Kwota netto"), width: 186, align: .right),
                ],
                rows: charges.map { [$0.0, $0.1, l.amount($0.2)] }, fontSize: 17, rowHeight: 46, verticalRules: false
            ) + 24
            let summary: [(String, Double)] = l == .polish
                ? [("Razem netto", total), ("VAT 23%", polishGross - total), ("Razem do zapłaty", polishGross)]
                : [("Total amount due", total)]
            for (index, (label, value)) in summary.enumerated() {
                let isLast = index == summary.count - 1
                canvas.text(label, x: a4.width - margin - 220, y: y, size: isLast ? 22 : 18, weight: isLast ? .bold : .regular, align: .right)
                canvas.text(l.money(value), x: a4.width - margin - 12, y: y, size: isLast ? 22 : 18, weight: isLast ? .bold : .regular, align: .right)
                y += isLast ? 40 : 32
            }
            y += 40
            canvas.text(l.t("How to pay", "Jak zapłacić"), x: margin, y: y, size: 21, weight: .bold)
            y = canvas.paragraph(
                l.t("Pay by bank transfer to account 0098 7654 3210, quoting your customer number 2071 5531, or scan the code on the right with your banking app.",
                    "Zapłać przelewem na rachunek 45 1140 2004 0000 3102 7654 3210, podając numer klienta 2071 5531, albo zeskanuj kod obok w aplikacji bankowej."),
                x: margin, y: y + 40, width: contentWidth - 230, size: 18
            )
            canvas.matrixCode(in: CGRect(x: a4.width - margin - 190, y: y - 150, width: 190, height: 190), seed: 20_715_531)
            y += 50
            canvas.text(l.t("Save energy this winter", "Oszczędzaj energię zimą"), x: margin, y: y, size: 21, weight: .bold)
            y += 42
            for tip in [
                l.t("Lower the heating by 1 °C to save up to 6% of your heating costs.", "Obniżenie temperatury o 1 °C to nawet 6% niższe koszty ogrzewania."),
                l.t("Run the washing machine and dishwasher only when they are full.", "Uruchamiaj pralkę i zmywarkę tylko z pełnym załadunkiem."),
                l.t("Switch devices off instead of leaving them on standby.", "Wyłączaj urządzenia zamiast zostawiać je w trybie czuwania."),
            ] {
                y = canvas.paragraph("•  \(tip)", x: margin + 6, y: y, width: contentWidth - 6, size: 18, indent: 24) + 6
            }
            pageFooter(canvas, l, page: 2, of: 2)
        }

        return DemoDocumentSpec(
            title: l.t("Electricity bill – October", "Rachunek za prąd – październik"),
            folder: .home,
            age: 2 * day,
            pages: [page1, page2]
        )
    }
}
#endif
