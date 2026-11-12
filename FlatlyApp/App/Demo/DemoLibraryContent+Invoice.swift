#if DEBUG
import UIKit

extension DemoLibraryContent {
    /// Two-page print shop invoice. Page 1 was "imported" from a photo of the sheet on a desk.
    static func invoice(_ l: DemoLanguage, now: Date) -> DemoDocumentSpec {
        let issued = daysAgo(2, from: now)
        let due = issued.addingTimeInterval(14 * day)
        let navy = UIColor(red: 0.15, green: 0.23, blue: 0.50, alpha: 1)
        let number = l.t("INV-2026-0412", "FV/412/2026")
        let taxRate = l == .polish ? 0.23 : 0.08
        let items: [(name: String, quantity: Double, unit: String, price: Double)] = l == .polish
            ? [
                ("Wizytówki 350 g, folia matowa", 500, "szt.", 0.36),
                ("Ulotki A5, druk dwustronny", 2000, "szt.", 0.15),
                ("Karty menu A4, 300 g", 60, "szt.", 4.90),
                ("Roll-up 85×200 cm", 1, "szt.", 189),
                ("Projekt graficzny", 4, "godz.", 120),
            ]
            : [
                ("Business cards, 350 g matte", 500, "pcs", 0.18),
                ("Flyers A5, double-sided", 2000, "pcs", 0.07),
                ("Menu cards A4, 300 g", 60, "pcs", 2.40),
                ("Roll-up banner 85×200 cm", 1, "pcs", 89),
                ("Graphic design", 4, "h", 45),
            ]
        let net = items.reduce(0) { $0 + $1.quantity * $1.price }
        let tax = (net * taxRate * 100).rounded() / 100
        let total = net + tax

        @Sendable func letterhead(_ canvas: DemoPageCanvas, compact: Bool) {
            let logo = CGRect(x: margin, y: 80, width: compact ? 56 : 76, height: compact ? 56 : 76)
            canvas.fill(logo, navy, radius: 14)
            canvas.text("L", x: logo.midX, y: logo.minY + (compact ? 6 : 8), size: compact ? 38 : 52, weight: .heavy, color: .white, align: .center, recognized: false)
            canvas.text(l.t("LUMEN PRINT STUDIO", "DRUKARNIA LUMEN"), x: logo.maxX + 20, y: logo.minY + (compact ? 4 : 8), size: compact ? 24 : 30, weight: .heavy, kern: 1)
            canvas.text(l.t("Printing · Design · Large format", "Druk · Projekty · Wielki format"), x: logo.maxX + 20, y: logo.minY + (compact ? 34 : 46), size: compact ? 15 : 17, color: DemoPageCanvas.gray)
        }

        let page1 = DemoPageSpec(size: a4, capture: .deskPhoto) { canvas in
            letterhead(canvas, compact: false)
            let right = a4.width - margin
            canvas.text(l.t("INVOICE", "FAKTURA VAT"), x: right, y: 74, size: 40, weight: .bold, color: navy, align: .right)
            canvas.text(l.t("No. \(number)", "nr \(number)"), x: right, y: 128, size: 20, weight: .semibold, align: .right)

            var y: CGFloat = 214
            let details = [
                (l.t("Issue date", "Data wystawienia"), l.shortDate(issued)),
                (l.t("Delivery date", "Data sprzedaży"), l.shortDate(issued)),
                (l.t("Due date", "Termin płatności"), l.shortDate(due)),
                (l.t("Payment", "Sposób zapłaty"), l.t("Bank transfer", "Przelew")),
            ]
            for (label, value) in details {
                canvas.text(label, x: right - 230, y: y, size: 17, color: DemoPageCanvas.gray, align: .right)
                canvas.text(value, x: right, y: y, size: 17, weight: .semibold, align: .right)
                y += 28
            }

            let partiesTop: CGFloat = 352
            let column = contentWidth / 2
            for (index, (heading, lines)) in [
                (l.t("Seller", "Sprzedawca"), [
                    l.t("Lumen Print Studio LLC", "Drukarnia Lumen sp. z o.o."),
                    l.t("21 Factory Road", "ul. Fabryczna 21"),
                    l.t("Springfield, IL 62704", "31-553 Kraków"),
                    l.t("Tax ID: 47-2918305", "NIP: 677-24-18-905"),
                ]),
                (l.t("Bill to", "Nabywca"), [
                    l.t("Clockwork Café", "Kawiarnia Pod Zegarem s.c."),
                    l.t("5 Long Street", "ul. Długa 5"),
                    l.t("Springfield, IL 62701", "31-147 Kraków"),
                    l.t("Tax ID: 83-1027764", "NIP: 945-11-27-386"),
                ]),
            ].enumerated() {
                let left = margin + CGFloat(index) * column
                canvas.text(heading.uppercased(), x: left, y: partiesTop, size: 15, weight: .bold, color: navy, kern: 1.2)
                for (row, line) in lines.enumerated() {
                    canvas.text(line, x: left, y: partiesTop + 30 + CGFloat(row) * 28, size: 18, weight: row == 0 ? .semibold : .regular)
                }
            }

            y = canvas.table(
                x: margin, y: 540,
                columns: [
                    .init(title: "#", width: 44, align: .center),
                    .init(title: l.t("Description", "Nazwa towaru lub usługi"), width: 372),
                    .init(title: l.t("Qty", "Ilość"), width: 130, align: .right),
                    .init(title: l.t("Unit price", "Cena netto"), width: 150, align: .right),
                    .init(title: l.t("Amount", "Wartość netto"), width: 170, align: .right),
                ],
                rows: items.enumerated().map { index, item in
                    [
                        "\(index + 1)", item.name,
                        "\(Int(item.quantity)) \(item.unit)",
                        l.amount(item.price), l.amount(item.quantity * item.price),
                    ]
                },
                fontSize: 17, rowHeight: 44, headerFill: navy.withAlphaComponent(0.12), verticalRules: false
            ) + 30

            let labelX = a4.width - margin - 200
            for (label, value, bold) in [
                (l.t("Subtotal", "Razem netto"), l.money(net), false),
                (l.t("Tax 8%", "VAT 23%"), l.money(tax), false),
            ] {
                canvas.text(label, x: labelX, y: y, size: 18, color: DemoPageCanvas.gray, align: .right)
                canvas.text(value, x: a4.width - margin - 12, y: y, size: 18, weight: bold ? .bold : .regular, align: .right)
                y += 34
            }
            canvas.fill(CGRect(x: a4.width - margin - 430, y: y + 6, width: 430, height: 62), navy.withAlphaComponent(0.12), radius: 8)
            canvas.text(l.t("Total due", "Do zapłaty"), x: labelX, y: y + 20, size: 22, weight: .semibold, align: .right)
            canvas.text(l.money(total), x: a4.width - margin - 12, y: y + 16, size: 28, weight: .bold, color: navy, align: .right)
            y += 92
            if l == .polish {
                canvas.text("Słownie: tysiąc siedemset siedemdziesiąt cztery złote 89/100", x: a4.width - margin - 12, y: y, size: 16, color: DemoPageCanvas.gray, align: .right)
                y += 28
            }

            y += 30
            canvas.text(l.t("Payment details", "Dane do przelewu"), x: margin, y: y, size: 18, weight: .bold)
            canvas.text(l.t("First Prairie Bank · Account 0012 3456 7890 · Routing 123456789", "Bank Przykładowy S.A. · PL 12 1020 2892 0000 5402 0123 4567"), x: margin, y: y + 32, size: 17)
            canvas.text(l.t("Please quote \(number) as the payment reference.", "W tytule przelewu prosimy podać numer faktury \(number)."), x: margin, y: y + 60, size: 17, color: DemoPageCanvas.gray)

            let signatureTop = a4.height - 250
            canvas.signature(in: CGRect(x: margin + 30, y: signatureTop - 20, width: 210, height: 80), variant: 2)
            canvas.line(CGPoint(x: margin, y: signatureTop + 66), CGPoint(x: margin + 300, y: signatureTop + 66), color: DemoPageCanvas.gray, dash: [4, 5])
            canvas.text(l.t("Issued by: Emma Lewis", "Wystawił(a): Ewa Lis"), x: margin, y: signatureTop + 78, size: 16, color: DemoPageCanvas.gray)
            canvas.line(CGPoint(x: a4.width - margin - 300, y: signatureTop + 66), CGPoint(x: a4.width - margin, y: signatureTop + 66), color: DemoPageCanvas.gray, dash: [4, 5])
            canvas.text(l.t("Received by", "Odebrał(a)"), x: a4.width - margin - 300, y: signatureTop + 78, size: 16, color: DemoPageCanvas.gray)
            pageFooter(canvas, l, page: 1, of: 2)
        }

        let page2 = DemoPageSpec(size: a4) { canvas in
            letterhead(canvas, compact: true)
            canvas.text(l.t("Invoice \(number) – terms", "Faktura \(number) – warunki"), x: a4.width - margin, y: 96, size: 17, color: DemoPageCanvas.gray, align: .right)
            canvas.line(CGPoint(x: margin, y: 168), CGPoint(x: a4.width - margin, y: 168), color: navy, width: 2)
            var y: CGFloat = 206
            canvas.text(l.t("Payment terms and complaints", "Warunki płatności i reklamacje"), x: margin, y: y, size: 26, weight: .bold)
            y += 58
            for paragraph in [
                l.t("Payment is due within 14 days of the issue date. Late payments may be charged statutory interest for each day of delay.",
                    "Należność należy uregulować w terminie 14 dni od daty wystawienia faktury. Za opóźnienie w płatności mogą zostać naliczone odsetki ustawowe."),
                l.t("Printed materials remain the property of Lumen Print Studio until the invoice has been paid in full.",
                    "Wydrukowane materiały pozostają własnością Drukarni Lumen do czasu zapłaty całej należności."),
                l.t("Please check the delivered goods on receipt. Complaints about quantity or print quality can be made within 7 days, together with this invoice and samples of the defective items.",
                    "Prosimy o sprawdzenie towaru przy odbiorze. Reklamacje dotyczące ilości lub jakości druku przyjmujemy w ciągu 7 dni, wraz z fakturą i próbkami wadliwego towaru."),
                l.t("Colours may differ slightly from those shown on screen. Proofs approved by the customer are binding.",
                    "Kolory wydruku mogą nieznacznie różnić się od wyświetlanych na ekranie. Zaakceptowane przez klienta proofy są wiążące."),
                l.t("Design files remain available for repeat orders for 24 months.",
                    "Pliki projektów przechowujemy na potrzeby kolejnych zamówień przez 24 miesiące."),
            ] {
                y = canvas.paragraph(paragraph, x: margin, y: y, width: contentWidth, size: 19) + 18
            }
            y += 20
            canvas.text(l.t("Thank you for your order!", "Dziękujemy za zamówienie!"), x: margin, y: y, size: 24, weight: .semibold, color: navy)
            canvas.text(l.t("Questions? orders@lumenprint.example · (217) 555-0142", "Pytania? zamowienia@lumen.example · 12 555 01 42"), x: margin, y: y + 44, size: 17, color: DemoPageCanvas.gray)
            canvas.roundStamp(
                center: CGPoint(x: a4.width - margin - 170, y: y + 260), radius: 150,
                ring: l.t("LUMEN PRINT STUDIO · SPRINGFIELD", "DRUKARNIA LUMEN · KRAKÓW · NIP 6772418905"),
                middle: l.t("PAID", "ZAPŁACONO"), detail: l.shortDate(now.addingTimeInterval(-day)),
                color: UIColor(red: 0.78, green: 0.12, blue: 0.14, alpha: 1), angle: -0.21
            )
            pageFooter(canvas, l, page: 2, of: 2)
        }

        return DemoDocumentSpec(
            title: l.t("Invoice \(number) – Lumen Print", "Faktura \(number) – Drukarnia Lumen"),
            folder: nil,
            age: 26 * hour,
            pages: [page1, page2]
        )
    }
}
#endif
