// Offscan fixture generator.
//
// Draws invented documents (no real people, addresses or companies) and "photographs" each one
// lying on a desk: the sheet is projected through a pinhole camera with a 26 mm-equivalent lens,
// held slightly off-axis, then lit unevenly and given sensor noise. The photos are written as
// HEIC with the focal length in EXIF, next to expected.json (the words OCR must find).
//
// Usage: FixtureGenerator <TestFixtures directory>

import CoreGraphics
import CoreImage
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - Page drawing

/// A sheet being drawn top-down. The context has a bottom-left origin; `y` is the distance of
/// the cursor from the top edge.
final class PageCanvas {
    let ctx: CGContext
    let width: CGFloat
    let height: CGFloat
    let margin: CGFloat = 110
    var y: CGFloat = 120

    init(width: Int, height: Int) {
        self.width = CGFloat(width)
        self.height = CGFloat(height)
        ctx = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        ctx.setFillColor(CGColor(srgbRed: 0.965, green: 0.96, blue: 0.94, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
    }

    var contentWidth: CGFloat { width - 2 * margin }

    private func line(_ string: String, size: CGFloat, bold: Bool) -> CTLine {
        let font = CTFontCreateWithName((bold ? "Helvetica-Bold" : "Helvetica") as CFString, size, nil)
        let attributes = [
            kCTFontAttributeName: font,
            kCTForegroundColorAttributeName: CGColor(srgbRed: 0.08, green: 0.08, blue: 0.1, alpha: 1),
        ] as CFDictionary
        return CTLineCreateWithAttributedString(CFAttributedStringCreate(nil, string as CFString, attributes)!)
    }

    /// Draws one line at the cursor and moves the cursor below it.
    func text(_ string: String, size: CGFloat, bold: Bool = false, centered: Bool = false) {
        let line = line(string, size: size, bold: bold)
        let lineWidth = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        let x = centered ? (width - lineWidth) / 2 : margin
        ctx.textPosition = CGPoint(x: x, y: height - y - size)
        CTLineDraw(line, ctx)
        y += size * 1.55
    }

    func gap(_ amount: CGFloat) { y += amount }

    /// A ruled table; `fractions` are the column widths as shares of the content width.
    func table(_ rows: [[String]], fractions: [CGFloat], size: CGFloat, rowHeight: CGFloat) {
        let top = y
        ctx.setStrokeColor(CGColor(srgbRed: 0.15, green: 0.15, blue: 0.18, alpha: 1))
        ctx.setLineWidth(2)
        for (index, row) in rows.enumerated() {
            var x = margin
            for (column, cell) in row.enumerated() {
                let line = line(cell, size: size, bold: index == 0)
                ctx.textPosition = CGPoint(x: x + 14, y: height - y - rowHeight / 2 - size * 0.35)
                CTLineDraw(line, ctx)
                x += contentWidth * fractions[column]
            }
            y += rowHeight
        }
        // Grid.
        for index in 0...rows.count {
            let lineY = height - top - CGFloat(index) * rowHeight
            ctx.move(to: CGPoint(x: margin, y: lineY))
            ctx.addLine(to: CGPoint(x: margin + contentWidth, y: lineY))
        }
        var x = margin
        for fraction in fractions + [0] {
            ctx.move(to: CGPoint(x: x, y: height - top))
            ctx.addLine(to: CGPoint(x: x, y: height - y))
            x += contentWidth * fraction
        }
        ctx.strokePath()
        y += 30
    }

    func image() -> CGImage { ctx.makeImage()! }
}

// MARK: - Documents

struct Document {
    var name: String
    var title: String
    var landscape: Bool
    /// Words OCR must find (see expected.json).
    var words: [String]
    var draw: (PageCanvas) -> Void

    /// A4 at 150 dpi.
    var pixelSize: (width: Int, height: Int) { landscape ? (1754, 1240) : (1240, 1754) }
    var millimetres: (width: Double, height: Double) { landscape ? (297, 210) : (210, 297) }
}

let documents: [Document] = [
    Document(
        name: "schedule-portrait.heic", title: "Class schedule, November 2026", landscape: false,
        words: ["HARMONOGRAM", "ZAJĘĆ", "LISTOPAD", "2026", "PRZYKŁADOWY", "TESTOWA", "Zmyślona", "Data", "Godziny", "SUMA", "GODZIN", "03.11.2026", "24.11.2026", "Pracownia"]
    ) { page in
        page.text("HARMONOGRAM ZAJĘĆ", size: 54, bold: true, centered: true)
        page.text("LISTOPAD 2026", size: 40, centered: true)
        page.gap(40)
        page.text("Uczestnik: JAN PRZYKŁADOWY", size: 30)
        page.text("Prowadząca: ANNA TESTOWA", size: 30)
        page.text("Miejsce: Pracownia Ceramiki, ul. Zmyślona 12, Nigdziebądź", size: 30)
        page.gap(30)
        page.table([
            ["Data", "Godziny", "Liczba godzin"],
            ["03.11.2026", "8:00 - 10:00", "2"],
            ["05.11.2026", "8:00 - 10:00", "2"],
            ["10.11.2026", "9:00 - 12:00", "3"],
            ["12.11.2026", "8:00 - 10:00", "2"],
            ["17.11.2026", "9:00 - 12:00", "3"],
            ["19.11.2026", "8:00 - 10:00", "2"],
            ["24.11.2026", "9:00 - 12:00", "3"],
            ["26.11.2026", "8:00 - 10:00", "2"],
        ], fractions: [0.34, 0.36, 0.30], size: 28, rowHeight: 78)
        page.gap(20)
        page.text("SUMA GODZIN: 19", size: 34, bold: true)
        page.gap(60)
        page.text("Podpis prowadzącej: ........................................", size: 28)
    },
    Document(
        name: "log-landscape.heic", title: "Course log, landscape", landscape: true,
        words: ["DZIENNIK", "ZAJĘĆ", "KURS", "FOTOGRAFII", "POCZĄTKUJĄCYCH", "Temat", "Uwagi", "Budowa", "aparatu", "Ekspozycja", "światło", "Kompozycja", "Portret", "plenerze", "LISTOPAD"]
    ) { page in
        page.y = 90
        page.text("DZIENNIK ZAJĘĆ", size: 50, bold: true, centered: true)
        page.text("KURS FOTOGRAFII DLA POCZĄTKUJĄCYCH", size: 34, centered: true)
        page.text("LISTOPAD 2026", size: 30, centered: true)
        page.gap(30)
        page.table([
            ["Data", "Godziny", "Temat", "Uwagi"],
            ["04.11.2026", "17:00 - 19:00", "Budowa aparatu", "sala 3"],
            ["06.11.2026", "17:00 - 19:00", "Ekspozycja i światło", ""],
            ["11.11.2026", "10:00 - 13:00", "Kompozycja kadru", "statywy"],
            ["13.11.2026", "17:00 - 19:00", "Portret w plenerze", "park"],
            ["18.11.2026", "17:00 - 19:00", "Obróbka zdjęć", "sala 3"],
            ["20.11.2026", "17:00 - 19:00", "Wystawa prac", ""],
        ], fractions: [0.18, 0.22, 0.40, 0.20], size: 28, rowHeight: 86)
        page.text("Podpis prowadzącego: ........................................", size: 26)
    },
    Document(
        name: "invoice-portrait.heic", title: "Invoice from an invented print shop", landscape: false,
        words: ["FAKTURA", "VAT", "Sprzedawca", "Nabywca", "Drukarnia", "Kropka", "Zielnik", "Wizytówki", "Ulotki", "Plakaty", "Razem", "zapłaty", "Termin", "płatności", "przelew"]
    ) { page in
        page.text("FAKTURA VAT", size: 58, bold: true)
        page.text("nr FV/018/2026", size: 34)
        page.text("Data wystawienia: 12.11.2026", size: 28)
        page.gap(40)
        page.text("Sprzedawca", size: 26, bold: true)
        page.text("Drukarnia Kropka", size: 32)
        page.text("ul. Wymyślona 7, 00-001 Nigdziebądź", size: 28)
        page.gap(24)
        page.text("Nabywca", size: 26, bold: true)
        page.text("Pracownia Zielnik", size: 32)
        page.text("ul. Zmyślona 12, 00-002 Nigdziebądź", size: 28)
        page.gap(36)
        page.table([
            ["Lp.", "Nazwa", "Ilość", "Wartość"],
            ["1", "Wizytówki dwustronne", "500", "189,00 zł"],
            ["2", "Ulotki A5", "2000", "420,00 zł"],
            ["3", "Plakaty B2", "50", "365,00 zł"],
            ["4", "Naklejki okrągłe", "1000", "280,60 zł"],
        ], fractions: [0.10, 0.48, 0.16, 0.26], size: 28, rowHeight: 80)
        page.gap(20)
        page.text("Razem do zapłaty: 1 254,60 zł", size: 38, bold: true)
        page.text("Termin płatności: 14 dni", size: 28)
        page.text("Forma płatności: przelew", size: 28)
    },
    Document(
        name: "letter-portrait.heic", title: "Notice letter from an invented housing co-op", landscape: false,
        words: ["ZAWIADOMIENIE", "Spółdzielnia", "Mieszkaniowa", "Słoneczna", "przegląd", "instalacji", "gazowej", "listopada", "mieszkań", "Prosimy", "obecność", "Zarząd", "godzinach", "Szanowni", "Państwo"]
    ) { page in
        page.text("Spółdzielnia Mieszkaniowa Słoneczna", size: 34, bold: true)
        page.text("ul. Wymyślona 1, 00-001 Nigdziebądź", size: 26)
        page.gap(50)
        page.text("Nigdziebądź, 12 listopada 2026", size: 28)
        page.gap(70)
        page.text("ZAWIADOMIENIE", size: 52, bold: true, centered: true)
        page.gap(50)
        page.text("Szanowni Państwo,", size: 32)
        page.gap(20)
        for line in [
            "informujemy, że w dniu 24 listopada 2026 odbędzie się",
            "coroczny przegląd instalacji gazowej we wszystkich",
            "lokalach budynku. Przegląd potrwa około piętnastu minut",
            "w każdym z mieszkań i zostanie wykonany w godzinach",
            "od 9:00 do 15:00.",
        ] { page.text(line, size: 32) }
        page.gap(30)
        for line in [
            "Prosimy o obecność w domu lub pozostawienie kluczy",
            "u sąsiadów. Kolejny termin zostanie wyznaczony",
            "w grudniu.",
        ] { page.text(line, size: 32) }
        page.gap(90)
        page.text("Z poważaniem", size: 30)
        page.text("Zarząd Spółdzielni", size: 30, bold: true)
    },
    Document(
        name: "hours-portrait.heic", title: "Completed hours summary", landscape: false,
        words: ["WYKAZ", "ZREALIZOWANYCH", "GODZIN", "LISTOPAD", "Tydzień", "Liczba", "Łączna", "Potwierdzenie", "podpis", "PRZYKŁADOWY", "TESTOWA", "Ceramiki", "Uczestnik", "Prowadząca"]
    ) { page in
        page.text("WYKAZ ZREALIZOWANYCH GODZIN", size: 46, bold: true, centered: true)
        page.text("LISTOPAD 2026", size: 36, centered: true)
        page.gap(50)
        page.text("Uczestnik: JAN PRZYKŁADOWY", size: 30)
        page.text("Prowadząca: ANNA TESTOWA", size: 30)
        page.text("Zajęcia: Pracownia Ceramiki", size: 30)
        page.gap(40)
        page.table([
            ["Tydzień", "Liczba godzin"],
            ["02.11 - 08.11", "4"],
            ["09.11 - 15.11", "5"],
            ["16.11 - 22.11", "5"],
            ["23.11 - 29.11", "5"],
        ], fractions: [0.6, 0.4], size: 30, rowHeight: 92)
        page.gap(30)
        page.text("Łączna liczba godzin w miesiącu: 19", size: 34, bold: true)
        page.gap(120)
        page.text("Potwierdzenie - podpis prowadzącej:", size: 28)
        page.gap(40)
        page.text("........................................", size: 28)
    },
    Document(
        name: "handover-landscape.heic", title: "Equipment handover record, landscape", landscape: true,
        words: ["PROTOKÓŁ", "ODBIORU", "SPRZĘTU", "Nazwa", "Numer", "seryjny", "Stan", "Laptop", "Monitor", "Drukarka", "laserowa", "Klawiatura", "dobry", "Przekazujący", "Odbierający"]
    ) { page in
        page.y = 90
        page.text("PROTOKÓŁ ODBIORU SPRZĘTU", size: 50, bold: true, centered: true)
        page.text("Nigdziebądź, 12 listopada 2026", size: 30, centered: true)
        page.gap(40)
        page.table([
            ["Lp.", "Nazwa", "Numer seryjny", "Stan"],
            ["1", "Laptop 14 cali", "AB-102-774", "dobry"],
            ["2", "Monitor 27 cali", "MN-550-218", "dobry"],
            ["3", "Drukarka laserowa", "DR-901-336", "nowy"],
            ["4", "Klawiatura bezprzewodowa", "KL-447-090", "dobry"],
        ], fractions: [0.08, 0.42, 0.30, 0.20], size: 30, rowHeight: 92)
        page.gap(50)
        page.text("Przekazujący: ..............................        Odbierający: ..............................", size: 28)
    },
]

// MARK: - Camera

/// How the phone is held over the sheet. Angles in degrees, lengths in millimetres.
struct Shot {
    var tiltX: Double       // rotation about the camera's horizontal axis
    var tiltY: Double       // rotation about the camera's vertical axis
    var roll: Double        // rotation in the image plane
    var offsetX: Double
    var offsetY: Double
    var fill: Double        // share of the frame the sheet's longer visible side should cover
    var desk: (r: CGFloat, g: CGFloat, b: CGFloat)
}

let shots: [Shot] = [
    Shot(tiltX: 4, tiltY: -3, roll: 2, offsetX: 6, offsetY: -8, fill: 0.74, desk: (0.71, 0.55, 0.38)),
    Shot(tiltX: -3, tiltY: 4, roll: -3, offsetX: -4, offsetY: 12, fill: 0.84, desk: (0.23, 0.23, 0.25)),
    Shot(tiltX: 6, tiltY: 2, roll: -1.5, offsetX: 0, offsetY: 5, fill: 0.76, desk: (0.44, 0.50, 0.55)),
    Shot(tiltX: 2, tiltY: -5, roll: 4, offsetX: -8, offsetY: 0, fill: 0.72, desk: (0.48, 0.33, 0.22)),
    Shot(tiltX: -4, tiltY: -2, roll: 1, offsetX: 5, offsetY: 10, fill: 0.78, desk: (0.80, 0.62, 0.60)),
    Shot(tiltX: 3, tiltY: 3, roll: -2, offsetX: 3, offsetY: -6, fill: 0.86, desk: (0.36, 0.42, 0.33)),
]

let photoWidth = 2400
let photoHeight = 3200
let focalLength35mm = 26.0
/// Same convention as PerspectiveCorrector: 43.27 mm is the diagonal of the 35 mm frame.
let focalPixels = focalLength35mm * hypot(Double(photoWidth), Double(photoHeight)) / 43.27

/// Projects the sheet's corners (top-left, top-right, bottom-right, bottom-left) into the photo,
/// in pixels with a bottom-left origin.
func project(sheet: (width: Double, height: Double), shot: Shot, landscape: Bool) -> [CGPoint] {
    let visibleSide = landscape ? sheet.width : sheet.height
    let frameSide = landscape ? Double(photoWidth) : Double(photoHeight)
    let distance = focalPixels * visibleSide / (shot.fill * frameSide)
    let (ax, ay, az) = (shot.tiltX * .pi / 180, shot.tiltY * .pi / 180, shot.roll * .pi / 180)
    let corners = [
        (-sheet.width / 2, sheet.height / 2), (sheet.width / 2, sheet.height / 2),
        (sheet.width / 2, -sheet.height / 2), (-sheet.width / 2, -sheet.height / 2),
    ]
    return corners.map { corner in
        var (x, y, z) = (corner.0, corner.1, 0.0)
        (y, z) = (y * cos(ax) - z * sin(ax), y * sin(ax) + z * cos(ax))
        (x, z) = (x * cos(ay) + z * sin(ay), -x * sin(ay) + z * cos(ay))
        (x, y) = (x * cos(az) - y * sin(az), x * sin(az) + y * cos(az))
        x += shot.offsetX
        y += shot.offsetY
        z += distance
        return CGPoint(
            x: Double(photoWidth) / 2 + focalPixels * x / z,
            y: Double(photoHeight) / 2 + focalPixels * y / z
        )
    }
}

// MARK: - Scene

/// Deterministic pseudo-random numbers in 0..<1, so the fixtures are the same on every run.
struct Random {
    var state: UInt64
    mutating func next() -> CGFloat {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return CGFloat((state >> 33) % 10_000) / 10_000
    }
}

/// The desk with grain and the sheet's shadow, before the sheet is laid on it.
func desk(shot: Shot, corners: [CGPoint], seed: UInt64) -> CGImage {
    let ctx = CGContext(
        data: nil, width: photoWidth, height: photoHeight, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    ctx.setFillColor(CGColor(srgbRed: shot.desk.r, green: shot.desk.g, blue: shot.desk.b, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: photoWidth, height: photoHeight))

    // Grain: faint streaks along the desk.
    var random = Random(state: seed)
    for _ in 0..<700 {
        let y = random.next() * CGFloat(photoHeight)
        let x = random.next() * CGFloat(photoWidth)
        let length = 200 + random.next() * 900
        let light = random.next() > 0.5
        ctx.setStrokeColor(CGColor(gray: light ? 1 : 0, alpha: 0.03 + random.next() * 0.05))
        ctx.setLineWidth(2 + random.next() * 6)
        ctx.move(to: CGPoint(x: x, y: y))
        ctx.addLine(to: CGPoint(x: x + length, y: y + (random.next() - 0.5) * 30))
        ctx.strokePath()
    }

    // The sheet's soft shadow.
    ctx.setShadow(offset: CGSize(width: 14, height: -18), blur: 46, color: CGColor(gray: 0, alpha: 0.45))
    ctx.setFillColor(CGColor(gray: 0.9, alpha: 1))
    ctx.addLines(between: corners)
    ctx.closePath()
    ctx.fillPath()
    return ctx.makeImage()!
}

func photograph(_ document: Document, shot: Shot, seed: UInt64) -> CGImage {
    let page = PageCanvas(width: document.pixelSize.width, height: document.pixelSize.height)
    document.draw(page)
    let corners = project(sheet: document.millimetres, shot: shot, landscape: document.landscape)
    let frame = CGRect(x: 0, y: 0, width: photoWidth, height: photoHeight)

    let sheet = CIImage(cgImage: page.image()).applyingFilter("CIPerspectiveTransform", parameters: [
        "inputTopLeft": CIVector(cgPoint: corners[0]),
        "inputTopRight": CIVector(cgPoint: corners[1]),
        "inputBottomRight": CIVector(cgPoint: corners[2]),
        "inputBottomLeft": CIVector(cgPoint: corners[3]),
    ])
    var scene = sheet.composited(over: CIImage(cgImage: desk(shot: shot, corners: corners, seed: seed)))

    // Uneven light: brighter towards one corner.
    let light = CIFilter(name: "CILinearGradient", parameters: [
        "inputPoint0": CIVector(x: CGFloat(photoWidth) * 0.15, y: CGFloat(photoHeight) * 0.95),
        "inputPoint1": CIVector(x: CGFloat(photoWidth) * 0.9, y: 0),
        "inputColor0": CIColor(red: 1, green: 1, blue: 1),
        "inputColor1": CIColor(red: 0.78, green: 0.78, blue: 0.8),
    ])!.outputImage!.cropped(to: frame)
    scene = scene.applyingFilter("CIMultiplyCompositing", parameters: [kCIInputBackgroundImageKey: light])

    // Lens softness and sensor noise.
    scene = scene.clampedToExtent().applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 0.7]).cropped(to: frame)
    let noise = CIFilter(name: "CIRandomGenerator")!.outputImage!
        .applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 0.02, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0.02, y: 0, z: 0, w: 0),
            "inputBVector": CIVector(x: 0.02, y: 0, z: 0, w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 1),
        ])
        .cropped(to: frame)
    scene = noise.applyingFilter("CIAdditionCompositing", parameters: [kCIInputBackgroundImageKey: scene]).cropped(to: frame)

    let context = CIContext(options: [.workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!])
    return context.createCGImage(scene, from: frame, format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)!
}

// MARK: - Output

enum GeneratorError: Error { case write(String) }

func writeHEIC(_ image: CGImage, to url: URL) throws {
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.heic.identifier as CFString, 1, nil) else {
        throw GeneratorError.write(url.path)
    }
    let properties: [CFString: Any] = [
        kCGImageDestinationLossyCompressionQuality: 0.55,
        kCGImagePropertyExifDictionary: [
            kCGImagePropertyExifFocalLenIn35mmFilm: Int(focalLength35mm),
            kCGImagePropertyExifFocalLength: 5.1,
        ],
        kCGImagePropertyTIFFDictionary: [
            kCGImagePropertyTIFFMake: "Offscan",
            kCGImagePropertyTIFFModel: "Synthetic fixture",
        ],
    ]
    CGImageDestinationAddImage(destination, image, properties as CFDictionary)
    guard CGImageDestinationFinalize(destination) else { throw GeneratorError.write(url.path) }
    print("wrote \(url.path)")
}

struct Expected: Encodable {
    struct Fixture: Encodable {
        var orientation: String
        var title: String
        var words: [String]
    }

    var _comment = "Generated by scripts/generate-fixtures.sh; edit Tools/FixtureGenerator instead. Expected OCR words per fixture photo, matched case-insensitively, diacritics-sensitively, against the OCR output of the full pipeline (document detection -> perspective correction -> colour filter -> OCR). Every fixture must reach minimumMatchRatio and the average over all fixtures must reach minimumAverageMatchRatio. 'orientation' is the orientation of the paper sheet in the photo."
    var minimumMatchRatio = 0.7
    var minimumAverageMatchRatio = 0.85
    var fixtures: [String: Fixture]
}

let arguments = CommandLine.arguments
guard arguments.count >= 2 else {
    FileHandle.standardError.write(Data("usage: FixtureGenerator <TestFixtures dir>\n".utf8))
    exit(64)
}

do {
    let root = URL(fileURLWithPath: arguments[1], isDirectory: true)
    let photos = root.appendingPathComponent("photos", isDirectory: true)
    try FileManager.default.createDirectory(at: photos, withIntermediateDirectories: true)
    var fixtures: [String: Expected.Fixture] = [:]
    for (index, document) in documents.enumerated() {
        let photo = photograph(document, shot: shots[index], seed: UInt64(index + 1))
        try writeHEIC(photo, to: photos.appendingPathComponent(document.name))
        fixtures[document.name] = Expected.Fixture(
            orientation: document.landscape ? "landscape" : "portrait", title: document.title, words: document.words
        )
    }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(Expected(fixtures: fixtures)).write(to: root.appendingPathComponent("expected.json"))
    print("wrote \(root.appendingPathComponent("expected.json").path)")
} catch {
    FileHandle.standardError.write(Data("error: \(error)\n".utf8))
    exit(1)
}
