#if DEBUG
import UIKit

extension DemoLibraryContent {
    /// Four-page residential lease, signed on the last page, initialled on the others.
    static func leaseAgreement(_ l: DemoLanguage, now: Date) -> DemoDocumentSpec {
        let signed = now.addingTimeInterval(-45 * 60)
        let calendar = Calendar(identifier: .gregorian)
        let nextMonth = calendar.date(byAdding: .month, value: 1, to: signed) ?? signed
        let start = calendar.date(from: calendar.dateComponents([.year, .month], from: nextMonth)) ?? nextMonth
        let end = calendar.date(byAdding: DateComponents(year: 1, day: -1), to: start) ?? start
        let city = l.t("Springfield", "Kraków")
        let landlord = l.t("Margaret Hale", "Anna Wiśniewska")
        let tenant = l.t("Daniel Brooks", "Tomasz Zieliński")
        let rent = l.money(l == .polish ? 2800 : 1450)
        let deposit = l.money(l == .polish ? 5600 : 2900)

        @Sendable func initials(_ canvas: DemoPageCanvas) {
            canvas.signature(in: CGRect(x: a4.width - margin - 250, y: a4.height - 165, width: 110, height: 52), variant: 0, width: 2.6)
            canvas.signature(in: CGRect(x: a4.width - margin - 115, y: a4.height - 165, width: 110, height: 52), variant: 1, width: 2.6)
        }

        let page1 = DemoPageSpec(size: a4) { canvas in
            canvas.text("\(city), \(l.longDate(signed))", x: a4.width - margin, y: 84, size: 18, color: DemoPageCanvas.gray, align: .right)
            canvas.text(l.t("RESIDENTIAL LEASE AGREEMENT", "UMOWA NAJMU LOKALU MIESZKALNEGO"), x: a4.width / 2, y: 168, size: 31, weight: .bold, face: .serif, align: .center)
            canvas.text(l.t("No. 07/2026", "nr 07/2026"), x: a4.width / 2, y: 216, size: 19, face: .serif, color: DemoPageCanvas.gray, align: .center)
            var y = canvas.paragraph(
                l.t("This agreement is made on \(l.longDate(signed)) in \(city) between:", "zawarta w dniu \(l.longDate(signed)) w Krakowie pomiędzy:"),
                x: margin, y: 290, width: contentWidth, size: 19, face: .serif
            ) + 8
            y = canvas.paragraph(
                l.t("1. \(landlord), residing at 8 Rose Lane, Springfield, hereinafter referred to as the “Landlord”, and",
                    "1. \(landlord), zam. ul. Różana 8/2, 30-215 Kraków, zwaną dalej „Wynajmującym”, a"),
                x: margin, y: y, width: contentWidth, size: 19, face: .serif, indent: 26
            ) + 8
            y = canvas.paragraph(
                l.t("2. \(tenant), residing at 27 Elm Avenue, Springfield, hereinafter referred to as the “Tenant”.",
                    "2. \(tenant), zam. ul. Wiązowa 27/9, 31-424 Kraków, zwanym dalej „Najemcą”."),
                x: margin, y: y, width: contentWidth, size: 19, face: .serif, indent: 26
            ) + 36
            y = section(canvas, title: l.t("§ 1. Subject of the agreement", "§ 1. Przedmiot umowy"), clauses: [
                l.t("The Landlord leases to the Tenant the apartment at 14 Linden Street, Apt 4, Springfield, with a floor area of 52 m², consisting of two rooms, a kitchen, a bathroom and a hallway.",
                    "Wynajmujący oddaje Najemcy do używania lokal mieszkalny położony w Krakowie przy ul. Lipowej 14 m. 4, o powierzchni 52 m², składający się z dwóch pokoi, kuchni, łazienki i przedpokoju."),
                l.t("The apartment is handed over furnished, as listed in the inventory in Appendix 1, together with three sets of keys.",
                    "Lokal wydawany jest wraz z wyposażeniem wymienionym w protokole stanowiącym Załącznik nr 1 oraz trzema kompletami kluczy."),
                l.t("The Tenant will use the apartment for residential purposes only and will not sublet it without the Landlord's written consent.",
                    "Najemca będzie używał lokalu wyłącznie na cele mieszkaniowe i nie podnajmie go bez pisemnej zgody Wynajmującego."),
            ], y: y)
            y = section(canvas, title: l.t("§ 2. Term", "§ 2. Okres najmu"), clauses: [
                l.t("The agreement is concluded for a fixed term from \(l.longDate(start)) to \(l.longDate(end)).",
                    "Umowa zostaje zawarta na czas określony od \(l.longDate(start)) r. do \(l.longDate(end)) r."),
                l.t("Either party may terminate the agreement with three months' notice for the reasons listed in § 7.",
                    "Każda ze stron może wypowiedzieć umowę z zachowaniem trzymiesięcznego okresu wypowiedzenia z przyczyn wskazanych w § 7."),
            ], y: y)
            section(canvas, title: l.t("§ 3. Rent and charges", "§ 3. Czynsz i opłaty"), clauses: [
                l.t("The monthly rent is \(rent), payable in advance by the 10th day of each month to the Landlord's bank account.",
                    "Miesięczny czynsz najmu wynosi \(rent) i jest płatny z góry do 10. dnia każdego miesiąca na rachunek bankowy Wynajmującego."),
                l.t("In addition to the rent, the Tenant pays for electricity, gas, water and internet according to actual consumption.",
                    "Oprócz czynszu Najemca ponosi opłaty za energię elektryczną, gaz, wodę i internet według rzeczywistego zużycia."),
                l.t("The rent may be adjusted once a year by the average annual inflation rate, with one month's written notice.",
                    "Czynsz może być waloryzowany raz w roku o średnioroczny wskaźnik inflacji, z miesięcznym pisemnym uprzedzeniem."),
            ], y: y)
            initials(canvas)
            pageFooter(canvas, l, page: 1, of: 4)
        }

        let page2 = DemoPageSpec(size: a4) { canvas in
            var y = section(canvas, title: l.t("§ 4. Security deposit", "§ 4. Kaucja"), clauses: [
                l.t("On signing this agreement the Tenant pays a security deposit of \(deposit).",
                    "W dniu podpisania umowy Najemca wpłaca kaucję zabezpieczającą w wysokości \(deposit)."),
                l.t("The deposit is returned within 30 days of handing back the apartment, less any unpaid rent and the cost of repairing damage beyond normal wear and tear.",
                    "Kaucja podlega zwrotowi w terminie 30 dni od dnia zwrotu lokalu, po potrąceniu ewentualnych zaległości oraz kosztów naprawy szkód wykraczających poza normalne zużycie."),
            ], y: 100)
            y = section(canvas, title: l.t("§ 5. Obligations of the Tenant", "§ 5. Obowiązki Najemcy"), clauses: [
                l.t("To keep the apartment clean and in good repair and to carry out minor maintenance at their own expense.",
                    "Utrzymywać lokal w czystości i należytym stanie technicznym oraz dokonywać na własny koszt drobnych napraw."),
                l.t("To observe the house rules and to respect quiet hours between 10 p.m. and 6 a.m.",
                    "Przestrzegać porządku domowego oraz ciszy nocnej w godzinach od 22:00 do 6:00."),
                l.t("Not to make alterations to the apartment without the Landlord's prior written consent.",
                    "Nie dokonywać zmian w lokalu bez uprzedniej pisemnej zgody Wynajmującego."),
                l.t("To allow the Landlord to inspect the apartment once a quarter, at a time agreed in advance.",
                    "Umożliwić Wynajmującemu oględziny lokalu raz na kwartał, w uzgodnionym wcześniej terminie."),
            ], y: y)
            section(canvas, title: l.t("§ 6. Termination", "§ 6. Wypowiedzenie umowy"), clauses: [
                l.t("The Landlord may terminate the agreement if the Tenant is more than two months in arrears with the rent.",
                    "Wynajmujący może wypowiedzieć umowę, jeżeli Najemca zalega z zapłatą czynszu za dwa pełne okresy płatności."),
                l.t("The Tenant may terminate the agreement on taking up employment in another city or for other important reasons.",
                    "Najemca może wypowiedzieć umowę w przypadku podjęcia pracy w innej miejscowości lub z innych ważnych przyczyn."),
            ], y: y)
            initials(canvas)
            pageFooter(canvas, l, page: 2, of: 4)
        }

        let page3 = DemoPageSpec(size: a4) { canvas in
            var y: CGFloat = 100
            canvas.text(l.t("Appendix 1 – Inventory of furnishings", "Załącznik nr 1 – Protokół wyposażenia lokalu"), x: margin, y: y, size: 23, weight: .bold, face: .serif)
            y += 52
            let items: [(String, String, String)] = [
                (l.t("Sofa bed", "Sofa rozkładana"), "1", l.t("Good", "Dobry")),
                (l.t("Wardrobe with mirror", "Szafa z lustrem"), "2", l.t("Very good", "Bardzo dobry")),
                (l.t("Dining table with 4 chairs", "Stół z 4 krzesłami"), "1", l.t("Good", "Dobry")),
                (l.t("Refrigerator with freezer", "Lodówka z zamrażarką"), "1", l.t("New", "Nowy")),
                (l.t("Washing machine", "Pralka"), "1", l.t("Good", "Dobry")),
                (l.t("Induction hob and oven", "Płyta indukcyjna i piekarnik"), "1", l.t("Very good", "Bardzo dobry")),
                (l.t("Desk and office chair", "Biurko i krzesło biurowe"), "1", l.t("Good", "Dobry")),
                (l.t("Bookshelf", "Regał na książki"), "2", l.t("Good", "Dobry")),
                (l.t("Ceiling lamps", "Lampy sufitowe"), "4", l.t("Very good", "Bardzo dobry")),
            ]
            y = canvas.table(
                x: margin, y: y,
                columns: [
                    .init(title: l.t("No.", "Lp."), width: 70, align: .center),
                    .init(title: l.t("Item", "Przedmiot"), width: 476),
                    .init(title: l.t("Qty", "Ilość"), width: 110, align: .center),
                    .init(title: l.t("Condition", "Stan"), width: 210),
                ],
                rows: items.enumerated().map { ["\($0.offset + 1)", $0.element.0, $0.element.1, $0.element.2] }
            ) + 44
            canvas.text(l.t("Meter readings on handover", "Stany liczników w dniu wydania lokalu"), x: margin, y: y, size: 21, weight: .semibold, face: .serif)
            y += 44
            for line in [
                l.t("Electricity: 23,418 kWh", "Energia elektryczna: 23 418 kWh"),
                l.t("Gas: 4,512 m³", "Gaz: 4512 m³"),
                l.t("Cold water: 312.4 m³", "Woda zimna: 312,4 m³"),
                l.t("Hot water: 148.9 m³", "Woda ciepła: 148,9 m³"),
            ] {
                canvas.text("•  \(line)", x: margin + 8, y: y, size: 19, face: .serif)
                y += 32
            }
            initials(canvas)
            pageFooter(canvas, l, page: 3, of: 4)
        }

        let page4 = DemoPageSpec(size: a4) { canvas in
            var y = section(canvas, title: l.t("§ 7. Final provisions", "§ 7. Postanowienia końcowe"), clauses: [
                l.t("Any amendments to this agreement must be made in writing to be valid.",
                    "Wszelkie zmiany niniejszej umowy wymagają formy pisemnej pod rygorem nieważności."),
                l.t("Matters not covered by this agreement are governed by the applicable provisions of the Civil Code.",
                    "W sprawach nieuregulowanych niniejszą umową zastosowanie mają przepisy Kodeksu cywilnego."),
                l.t("The agreement has been drawn up in two identical copies, one for each party.",
                    "Umowę sporządzono w dwóch jednobrzmiących egzemplarzach, po jednym dla każdej ze stron."),
            ], y: 100)
            y += 150
            let columnWidth: CGFloat = 340
            for (index, (role, name)) in [(l.t("Landlord", "Wynajmujący"), landlord), (l.t("Tenant", "Najemca"), tenant)].enumerated() {
                let left = index == 0 ? margin : a4.width - margin - columnWidth
                canvas.signature(in: CGRect(x: left + 40, y: y - 10, width: 250, height: 100), variant: index)
                canvas.line(CGPoint(x: left, y: y + 96), CGPoint(x: left + columnWidth, y: y + 96), color: DemoPageCanvas.gray, width: 1.5, dash: [4, 5])
                canvas.text(role, x: left + columnWidth / 2, y: y + 110, size: 19, weight: .semibold, face: .serif, align: .center)
                canvas.text(name, x: left + columnWidth / 2, y: y + 140, size: 18, face: .serif, color: DemoPageCanvas.gray, align: .center)
            }
            pageFooter(canvas, l, page: 4, of: 4)
        }

        return DemoDocumentSpec(
            title: l.t("Lease agreement – 14 Linden St", "Umowa najmu – ul. Lipowa 14"),
            folder: nil,
            age: 45 * 60,
            pages: [page1, page2, page3, page4]
        )
    }
}
#endif
