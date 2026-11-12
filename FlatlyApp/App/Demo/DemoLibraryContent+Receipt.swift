#if DEBUG
import UIKit

extension DemoLibraryContent {
    /// A long, narrow grocery receipt in a monospaced font.
    static func receipt(_ l: DemoLanguage, now: Date) -> DemoDocumentSpec {
        let size = CGSize(width: 620, height: 1560)
        let bought = at(daysAgo(3, from: now), hour: 17, minute: 42)
        let items: [(name: String, detail: String?, price: Double)] = l == .polish
            ? [
                ("Chleb na zakwasie", nil, 8.99),
                ("Mleko 2% 1 l", "2 x 3,49", 6.98),
                ("Jaja z wolnego wybiegu 10 szt", nil, 12.99),
                ("Ser gouda", "0,320 kg x 31,90", 10.21),
                ("Pomidory malinowe", "0,850 kg x 9,95", 8.46),
                ("Banany", "1,120 kg x 5,99", 6.71),
                ("Kawa mielona 250 g", nil, 21.99),
                ("Jogurt grecki 400 g", "4 x 2,79", 11.16),
                ("Oliwa z oliwek 500 ml", nil, 29.99),
                ("Czekolada gorzka 70%", nil, 6.49),
            ]
            : [
                ("Sourdough bread", nil, 4.50),
                ("Organic milk 2% 1 qt", "2 x 1.89", 3.78),
                ("Free-range eggs 12 ct", nil, 5.20),
                ("Gouda cheese", "0.70 lb x 9.15", 6.41),
                ("Vine tomatoes", "1.87 lb x 1.82", 3.40),
                ("Bananas", "2.46 lb x 0.59", 1.45),
                ("Ground coffee 8 oz", nil, 7.90),
                ("Greek yogurt 16 oz", "4 x 1.25", 5.00),
                ("Olive oil 500 ml", nil, 8.99),
                ("Dark chocolate 70%", nil, 2.49),
            ]
        let total = items.reduce(0) { $0 + $1.price }

        let page = DemoPageSpec(size: size) { canvas in
            let left: CGFloat = 46
            let right = size.width - 46
            let center = size.width / 2
            var y: CGFloat = 70
            canvas.text(l.t("GREEN MARKET", "ZIELONY RYNEK"), x: center, y: y, size: 36, weight: .heavy, face: .mono, align: .center)
            y += 52
            for line in [
                l.t("Fresh food & groceries", "Delikatesy i warzywniak"),
                l.t("102 Market Street, Springfield", "ul. Krakowska 102, 31-062 Kraków"),
                l.t("Tax ID 47-5531208", "NIP 676-10-20-345"),
            ] {
                canvas.text(line, x: center, y: y, size: 17, face: .mono, align: .center)
                y += 26
            }
            y += 18
            canvas.text("\(l.shortDate(bought)) \(l.time(bought))", x: left, y: y, size: 17, face: .mono)
            canvas.text("#004821", x: right, y: y, size: 17, face: .mono, align: .right)
            y += 34
            if l == .polish {
                canvas.text("PARAGON FISKALNY", x: center, y: y, size: 21, weight: .bold, face: .mono, align: .center)
                y += 36
            }
            canvas.line(CGPoint(x: left, y: y), CGPoint(x: right, y: y), color: DemoPageCanvas.ink, width: 2, dash: [6, 6])
            y += 20
            for item in items {
                canvas.text(item.name, x: left, y: y, size: 18, face: .mono)
                if let detail = item.detail {
                    y += 26
                    canvas.text("  \(detail)", x: left, y: y, size: 16, face: .mono, color: DemoPageCanvas.gray)
                }
                canvas.text(l.amount(item.price), x: right, y: y, size: 18, face: .mono, align: .right)
                y += 32
            }
            y += 4
            canvas.line(CGPoint(x: left, y: y), CGPoint(x: right, y: y), color: DemoPageCanvas.ink, width: 2, dash: [6, 6])
            y += 22
            if l == .polish {
                let vat = (total * 0.23 / 1.23 * 0.3 * 100).rounded() / 100 + (total * 0.05 / 1.05 * 0.7 * 100).rounded() / 100
                canvas.text("SP.OP.A 23%", x: left, y: y, size: 17, face: .mono)
                canvas.text(l.amount(total * 0.3), x: right, y: y, size: 17, face: .mono, align: .right)
                canvas.text("SP.OP.C 5%", x: left, y: y + 26, size: 17, face: .mono)
                canvas.text(l.amount(total * 0.7), x: right, y: y + 26, size: 17, face: .mono, align: .right)
                canvas.text("SUMA PTU", x: left, y: y + 52, size: 17, face: .mono)
                canvas.text(l.amount(vat), x: right, y: y + 52, size: 17, face: .mono, align: .right)
                y += 92
                canvas.text("SUMA PLN", x: left, y: y, size: 30, weight: .heavy, face: .mono)
            } else {
                let tax = (total * 0.0625 * 100).rounded() / 100
                canvas.text("SUBTOTAL", x: left, y: y, size: 17, face: .mono)
                canvas.text(l.amount(total), x: right, y: y, size: 17, face: .mono, align: .right)
                canvas.text("SALES TAX 6.25%", x: left, y: y + 26, size: 17, face: .mono)
                canvas.text(l.amount(tax), x: right, y: y + 26, size: 17, face: .mono, align: .right)
                y += 66
                canvas.text("TOTAL", x: left, y: y, size: 30, weight: .heavy, face: .mono)
                canvas.text(l.amount(total + tax), x: right, y: y, size: 30, weight: .heavy, face: .mono, align: .right)
                y += 52
            }
            if l == .polish {
                canvas.text(l.amount(total), x: right, y: y, size: 30, weight: .heavy, face: .mono, align: .right)
                y += 52
            }
            canvas.text(l.t("VISA CONTACTLESS **** 4821", "KARTA PŁATNICZA **** 4821"), x: left, y: y, size: 17, face: .mono)
            y += 26
            canvas.text(l.t("APPROVED  AUTH 093317", "TRANSAKCJA ZATWIERDZONA"), x: left, y: y, size: 17, face: .mono)
            y += 52
            canvas.text(l.t("Thank you for shopping with us!", "Dziękujemy, zapraszamy ponownie!"), x: center, y: y, size: 18, weight: .semibold, face: .mono, align: .center)
            y += 50
            canvas.barcode(in: CGRect(x: center - 190, y: y, width: 380, height: 90), seed: 4821)
            y += 100
            canvas.text("4 006381 333931", x: center, y: y, size: 16, face: .mono, align: .center)
        }

        return DemoDocumentSpec(
            title: l.t("Receipt – Green Market", "Paragon – Zielony Rynek"),
            folder: nil,
            age: 3 * day,
            pages: [page]
        )
    }
}
#endif
