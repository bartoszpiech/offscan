#if DEBUG
import UIKit

extension DemoLibraryContent {
    /// One-page sick note from a family clinic, stamped and signed.
    static func medicalCertificate(_ l: DemoLanguage, now: Date) -> DemoDocumentSpec {
        let examined = daysAgo(5, from: now)
        let until = daysAgo(-2, from: now)
        let green = UIColor(red: 0.0, green: 0.52, blue: 0.45, alpha: 1)

        let page = DemoPageSpec(size: a4) { canvas in
            clinicHeader(canvas, l, name: l.t("Riverside Family Clinic", "Przychodnia Rodzinna „Nad Wisłą”"),
                         address: l.t("3 River Road, Springfield · (217) 555-0190", "ul. Wiślana 3, 30-302 Kraków · tel. 12 555 01 90"), color: green)
            canvas.text(l.t("MEDICAL CERTIFICATE", "ZAŚWIADCZENIE LEKARSKIE"), x: a4.width / 2, y: 250, size: 32, weight: .bold, align: .center, kern: 1.5)
            canvas.text(l.t("Springfield, \(l.longDate(examined))", "Kraków, \(l.longDate(examined)) r."), x: a4.width - margin, y: 316, size: 18, align: .right)
            var y: CGFloat = 380
            for (label, value) in [
                (l.t("Patient", "Pacjent"), l.t("Daniel Brooks", "Tomasz Zieliński")),
                (l.t("Date of birth", "Data urodzenia"), l.t("March 14, 1991", "14.03.1991")),
                (l.t("Address", "Adres"), l.t("14 Linden Street, Apt 4, Springfield", "ul. Lipowa 14 m. 4, 30-001 Kraków")),
            ] {
                canvas.text(label, x: margin, y: y, size: 18, color: DemoPageCanvas.gray)
                canvas.text(value, x: margin + 220, y: y, size: 19, weight: .semibold)
                canvas.line(CGPoint(x: margin + 220, y: y + 32), CGPoint(x: a4.width - margin, y: y + 32), dash: [2, 4])
                y += 52
            }
            y += 30
            y = canvas.paragraph(
                l.t("I hereby certify that the above patient was examined on \(l.longDate(examined)) and, owing to an acute respiratory infection, is unfit for work from \(l.longDate(examined)) to \(l.longDate(until)) inclusive.",
                    "Zaświadcza się, że wyżej wymieniony pacjent był badany w dniu \(l.shortDate(examined)) r. i z powodu ostrej infekcji dróg oddechowych jest niezdolny do pracy w okresie od \(l.shortDate(examined)) r. do \(l.shortDate(until)) r. włącznie."),
                x: margin, y: y, width: contentWidth, size: 20, lineSpacing: 1.5
            ) + 30
            canvas.text(l.t("Recommendations", "Zalecenia"), x: margin, y: y, size: 21, weight: .bold)
            y += 44
            for item in [
                l.t("Rest at home, plenty of fluids.", "Leżenie w domu, dużo płynów."),
                l.t("Paracetamol 500 mg up to four times a day if feverish.", "Paracetamol 500 mg do 4 razy dziennie w razie gorączki."),
                l.t("Follow-up visit if symptoms persist after five days.", "Wizyta kontrolna, jeśli objawy utrzymają się dłużej niż 5 dni."),
            ] {
                y = canvas.paragraph("•  \(item)", x: margin + 6, y: y, width: contentWidth - 6, size: 19, indent: 24) + 4
            }
            let stampCenter = CGPoint(x: a4.width - margin - 230, y: a4.height - 330)
            canvas.boxStamp(center: stampCenter, lines: [
                l.t("Katherine Novak, MD", "lek. med. Katarzyna Nowak"),
                l.t("Family medicine", "specjalista medycyny rodzinnej"),
                l.t("Licence no. 0000000", "nr prawa wyk. zawodu 0000000"),
            ], color: UIColor(red: 0.12, green: 0.25, blue: 0.62, alpha: 1), angle: -0.04)
            canvas.signature(in: CGRect(x: stampCenter.x - 140, y: stampCenter.y + 40, width: 260, height: 90), variant: 2)
            canvas.line(CGPoint(x: stampCenter.x - 200, y: stampCenter.y + 140), CGPoint(x: stampCenter.x + 200, y: stampCenter.y + 140), color: DemoPageCanvas.gray, dash: [4, 5])
            canvas.text(l.t("Physician's stamp and signature", "Pieczątka i podpis lekarza"), x: stampCenter.x, y: stampCenter.y + 152, size: 16, color: DemoPageCanvas.gray, align: .center)
        }

        return DemoDocumentSpec(
            title: l.t("Medical certificate", "Zaświadczenie lekarskie"),
            folder: .health,
            age: 4 * day,
            pages: [page]
        )
    }

    /// Two-page laboratory report: blood count and biochemistry, with out-of-range values flagged.
    static func bloodTestResults(_ l: DemoLanguage, now: Date) -> DemoDocumentSpec {
        let collected = at(daysAgo(10, from: now), hour: 7, minute: 45)
        let purple = UIColor(red: 0.42, green: 0.22, blue: 0.62, alpha: 1)
        let lab = l.t("Medilab Diagnostics", "Laboratorium Medilab")
        let address = l.t("40 Science Park, Springfield · results@medilab.example", "ul. Naukowa 40, 31-410 Kraków · wyniki@medilab.example")

        @Sendable func patientBox(_ canvas: DemoPageCanvas) {
            canvas.fill(CGRect(x: margin, y: 214, width: contentWidth, height: 112), DemoPageCanvas.tint, radius: 10)
            let fields = [
                (l.t("Patient", "Pacjent"), l.t("Daniel Brooks", "Tomasz Zieliński")),
                (l.t("Date of birth", "Data urodzenia"), l.t("Mar 14, 1991", "14.03.1991")),
                (l.t("Order no.", "Nr zlecenia"), "LAB-26-118402"),
                (l.t("Collected", "Pobrano"), "\(l.shortDate(collected)) \(l.time(collected))"),
            ]
            for (index, (label, value)) in fields.enumerated() {
                let x = margin + 24 + CGFloat(index % 2) * 440
                let y = 228 + CGFloat(index / 2) * 48
                canvas.text(label, x: x, y: y, size: 15, color: DemoPageCanvas.gray)
                canvas.text(value, x: x + 170, y: y - 2, size: 18, weight: .semibold)
            }
        }

        let columns: [DemoPageCanvas.Column] = [
            .init(title: l.t("Test", "Badanie"), width: 300),
            .init(title: l.t("Result", "Wynik"), width: 130, align: .right),
            .init(title: l.t("Unit", "Jednostka"), width: 150),
            .init(title: l.t("Reference range", "Zakres referencyjny"), width: 226),
            .init(title: "", width: 60, align: .center),
        ]

        let page1 = DemoPageSpec(size: a4) { canvas in
            clinicHeader(canvas, l, name: lab, address: address, color: purple)
            patientBox(canvas)
            canvas.text(l.t("Complete blood count", "Morfologia krwi"), x: margin, y: 360, size: 23, weight: .bold, color: purple)
            let rows = [
                [l.t("White blood cells (WBC)", "Leukocyty (WBC)"), l.t("6.8", "6,8"), "10³/µl", l.t("4.0 – 10.0", "4,0 – 10,0"), ""],
                [l.t("Red blood cells (RBC)", "Erytrocyty (RBC)"), l.t("4.92", "4,92"), "10⁶/µl", l.t("4.50 – 5.90", "4,50 – 5,90"), ""],
                [l.t("Hemoglobin (HGB)", "Hemoglobina (HGB)"), l.t("14.6", "14,6"), "g/dl", l.t("13.5 – 17.5", "13,5 – 17,5"), ""],
                [l.t("Hematocrit (HCT)", "Hematokryt (HCT)"), l.t("43.1", "43,1"), "%", "40 – 52", ""],
                ["MCV", l.t("87.6", "87,6"), "fl", "80 – 100", ""],
                ["MCH", l.t("29.7", "29,7"), "pg", "27 – 33", ""],
                [l.t("Platelets (PLT)", "Płytki krwi (PLT)"), "251", "10³/µl", "150 – 400", ""],
                [l.t("Neutrophils", "Neutrofile"), l.t("3.9", "3,9"), "10³/µl", l.t("1.8 – 7.7", "1,8 – 7,7"), ""],
                [l.t("Lymphocytes", "Limfocyty"), l.t("2.1", "2,1"), "10³/µl", l.t("1.0 – 4.8", "1,0 – 4,8"), ""],
                [l.t("Monocytes", "Monocyty"), l.t("0.6", "0,6"), "10³/µl", l.t("0.1 – 0.8", "0,1 – 0,8"), ""],
                [l.t("Eosinophils", "Eozynofile"), l.t("0.6", "0,6"), "10³/µl", l.t("0.0 – 0.5", "0,0 – 0,5"), "H"],
            ]
            canvas.table(x: margin, y: 410, columns: columns, rows: rows, fontSize: 17, rowHeight: 44, headerFill: purple.withAlphaComponent(0.12), boldRows: [10], verticalRules: false)
            canvas.text(l.t("H – above the reference range, L – below the reference range", "H – powyżej zakresu referencyjnego, L – poniżej zakresu referencyjnego"), x: margin, y: 980, size: 16, color: DemoPageCanvas.gray)
            pageFooter(canvas, l, page: 1, of: 2)
        }

        let page2 = DemoPageSpec(size: a4) { canvas in
            clinicHeader(canvas, l, name: lab, address: address, color: purple)
            patientBox(canvas)
            canvas.text(l.t("Biochemistry", "Biochemia"), x: margin, y: 360, size: 23, weight: .bold, color: purple)
            let rows = [
                [l.t("Glucose, fasting", "Glukoza na czczo"), "97", "mg/dl", "70 – 99", ""],
                [l.t("Total cholesterol", "Cholesterol całkowity"), "212", "mg/dl", "< 190", "H"],
                [l.t("HDL cholesterol", "Cholesterol HDL"), "52", "mg/dl", "> 40", ""],
                [l.t("LDL cholesterol", "Cholesterol LDL"), "138", "mg/dl", "< 115", "H"],
                [l.t("Triglycerides", "Triglicerydy"), "110", "mg/dl", "< 150", ""],
                [l.t("Creatinine", "Kreatynina"), l.t("0.94", "0,94"), "mg/dl", l.t("0.70 – 1.20", "0,70 – 1,20"), ""],
                ["ALT", "24", "U/l", "< 41", ""],
                ["TSH", l.t("1.82", "1,82"), "µIU/ml", l.t("0.27 – 4.20", "0,27 – 4,20"), ""],
                [l.t("Vitamin D (25-OH)", "Witamina D (25-OH)"), l.t("24.5", "24,5"), "ng/ml", "30 – 50", "L"],
            ]
            var y = canvas.table(x: margin, y: 410, columns: columns, rows: rows, fontSize: 17, rowHeight: 44, headerFill: purple.withAlphaComponent(0.12), boldRows: [1, 3, 8], verticalRules: false) + 40
            y = canvas.paragraph(
                l.t("Comment: results should be interpreted by the referring physician together with the clinical picture.",
                    "Komentarz: wyniki powinny być interpretowane przez lekarza kierującego łącznie z obrazem klinicznym."),
                x: margin, y: y, width: contentWidth, size: 17, color: DemoPageCanvas.gray
            ) + 60
            canvas.text(l.t("Validated by", "Wynik autoryzował(a)"), x: a4.width - margin - 330, y: y, size: 16, color: DemoPageCanvas.gray)
            canvas.signature(in: CGRect(x: a4.width - margin - 320, y: y + 24, width: 220, height: 80), variant: 0)
            canvas.text(l.t("Sarah Mills, MSc, clinical laboratory scientist", "mgr Agnieszka Mazur, diagnosta laboratoryjny"), x: a4.width - margin, y: y + 116, size: 16, weight: .semibold, align: .right)
            canvas.text(l.t("— End of report —", "— Koniec wyniku —"), x: a4.width / 2, y: a4.height - 140, size: 16, color: DemoPageCanvas.gray, align: .center)
            pageFooter(canvas, l, page: 2, of: 2)
        }

        return DemoDocumentSpec(
            title: l.t("Blood test results", "Wyniki badań krwi"),
            folder: .health,
            age: 9 * day,
            pages: [page1, page2]
        )
    }

    /// Medical letterhead: a rounded cross in `color`, the name and the address, and a rule.
    private static func clinicHeader(_ canvas: DemoPageCanvas, _ l: DemoLanguage, name: String, address: String, color: UIColor) {
        let cross = CGRect(x: margin, y: 74, width: 72, height: 72)
        canvas.fill(CGRect(x: cross.minX + 24, y: cross.minY, width: 24, height: 72), color, radius: 5)
        canvas.fill(CGRect(x: cross.minX, y: cross.minY + 24, width: 72, height: 24), color, radius: 5)
        canvas.text(name, x: cross.maxX + 22, y: 78, size: 29, weight: .bold, color: color)
        canvas.text(address, x: cross.maxX + 22, y: 120, size: 16, color: DemoPageCanvas.gray)
        canvas.line(CGPoint(x: margin, y: 176), CGPoint(x: a4.width - margin, y: 176), color: color, width: 2)
    }
}
#endif
