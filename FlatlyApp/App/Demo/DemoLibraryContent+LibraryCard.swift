#if DEBUG
import UIKit

extension DemoLibraryContent {
    /// A credit-card-sized library card, front and back.
    static func libraryCard(_ l: DemoLanguage, now: Date) -> DemoDocumentSpec {
        let size = CGSize(width: 1012, height: 640)
        let green = UIColor(red: 0.16, green: 0.37, blue: 0.31, alpha: 1)
        let cream = UIColor(red: 0.98, green: 0.97, blue: 0.93, alpha: 1)
        let name = l.t("Daniel Brooks", "Tomasz Zieliński")
        let library = l.t("SPRINGFIELD CITY LIBRARY", "MIEJSKA BIBLIOTEKA PUBLICZNA")

        let front = DemoPageSpec(size: size) { canvas in
            canvas.fill(CGRect(origin: .zero, size: size), cream)
            canvas.fill(CGRect(x: 0, y: 0, width: size.width, height: 150), green)
            // A book icon in the band.
            let book = CGRect(x: 44, y: 34, width: 82, height: 82)
            canvas.fill(book, UIColor.white.withAlphaComponent(0.18), radius: 16)
            canvas.fill(CGRect(x: book.minX + 16, y: book.minY + 20, width: 22, height: 44), .white, radius: 3)
            canvas.fill(CGRect(x: book.minX + 44, y: book.minY + 20, width: 22, height: 44), .white, radius: 3)
            canvas.text(library, x: 150, y: 36, size: 30, weight: .heavy, color: .white, kern: 1)
            canvas.text(l.t("Reader card", "Karta czytelnika"), x: 150, y: 82, size: 22, weight: .medium, color: UIColor.white.withAlphaComponent(0.85))

            // Photo placeholder with a silhouette.
            let photo = CGRect(x: 52, y: 190, width: 230, height: 290)
            canvas.fill(photo, UIColor(white: 0.86, alpha: 1), radius: 8)
            canvas.circle(center: CGPoint(x: photo.midX, y: photo.minY + 110), radius: 56, fill: UIColor(white: 0.66, alpha: 1))
            canvas.fill(CGRect(x: photo.minX + 30, y: photo.minY + 180, width: photo.width - 60, height: 140), UIColor(white: 0.66, alpha: 1), radius: 70)
            canvas.fill(CGRect(x: photo.minX, y: photo.maxY, width: photo.width, height: 30), cream)
            canvas.stroke(photo, UIColor(white: 0.7, alpha: 1), width: 2, radius: 8)

            var y: CGFloat = 196
            for (label, value) in [
                (l.t("Name", "Imię i nazwisko"), name),
                (l.t("Card number", "Numer karty"), "0047 2291 8835"),
                (l.t("Valid until", "Ważna do"), l.t("12/2028", "12.2028")),
            ] {
                canvas.text(label.uppercased(), x: 322, y: y, size: 16, weight: .semibold, color: DemoPageCanvas.gray, kern: 1)
                canvas.text(value, x: 322, y: y + 24, size: 30, weight: .semibold)
                y += 92
            }
            canvas.barcode(in: CGRect(x: 322, y: 482, width: 520, height: 86), seed: 47_229_188)
            canvas.text("*0047229188350*", x: 582, y: 572, size: 16, face: .mono, align: .center)
        }

        let back = DemoPageSpec(size: size) { canvas in
            canvas.fill(CGRect(origin: .zero, size: size), cream)
            canvas.fill(CGRect(x: 0, y: 60, width: size.width, height: 70), UIColor(white: 0.18, alpha: 1))
            var y: CGFloat = 166
            for rule in [
                l.t("This card is personal and may not be lent to others.", "Karta jest imienna i nie może być udostępniana innym osobom."),
                l.t("Please report a lost card at once – you are responsible for items borrowed with it.", "Zgubienie karty należy niezwłocznie zgłosić – czytelnik odpowiada za wypożyczone nią zbiory."),
                l.t("Loan period: 30 days, renewable twice online or at any branch.", "Okres wypożyczenia: 30 dni, z możliwością dwukrotnego przedłużenia."),
            ] {
                y = canvas.paragraph("•  \(rule)", x: 52, y: y, width: size.width - 104, size: 19, indent: 24) + 6
            }
            canvas.text(l.t("Holder's signature", "Podpis czytelnika"), x: 52, y: 470, size: 15, weight: .semibold, color: DemoPageCanvas.gray, kern: 0.8)
            canvas.fill(CGRect(x: 52, y: 494, width: 520, height: 86), .white)
            canvas.stroke(CGRect(x: 52, y: 494, width: 520, height: 86), UIColor(white: 0.75, alpha: 1), width: 2)
            canvas.signature(in: CGRect(x: 92, y: 500, width: 260, height: 74), variant: 1, color: UIColor(white: 0.12, alpha: 0.9), width: 2.8)
            canvas.text(l.t("If found, please return to:", "Znalazcę prosimy o zwrot do:"), x: 620, y: 480, size: 15, color: DemoPageCanvas.gray)
            canvas.text(l.t("200 Library Square", "ul. Biblioteczna 2"), x: 620, y: 504, size: 17, weight: .semibold)
            canvas.text(l.t("Springfield · (217) 555-0170", "Kraków · 12 555 01 70"), x: 620, y: 530, size: 17)
            canvas.text(l.t("springfieldlibrary.example", "biblioteka.example"), x: 620, y: 556, size: 17, color: green)
        }

        return DemoDocumentSpec(
            title: l.t("Library card", "Karta biblioteczna"),
            folder: nil,
            age: 16 * day,
            pages: [front, back]
        )
    }
}
#endif
