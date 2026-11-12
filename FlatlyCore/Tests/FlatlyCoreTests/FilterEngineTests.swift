import Testing
import CoreGraphics
@testable import FlatlyCore

struct FilterEngineTests {
    let engine = FilterEngine()

    /// A white "page" with black text, darkened by a left→right shadow down to 45 % brightness.
    /// Returns the image and the text regions (top-left origin, padded).
    static func shadowedPage(width: Int = 1600, height: Int = 1200) -> (image: CGImage, textRects: [CGRect]) {
        var rects: [CGRect] = []
        let image = Synthetic.image(width: width, height: height, background: Synthetic.gray(1)) { ctx in
            let lines: [(String, CGPoint, CGFloat)] = [
                ("HARMONOGRAM PAŹDZIERNIK 2026", CGPoint(x: 80, y: 1050), 56),
                ("Dziennik zajęć — kurs fotografii dla początkujących", CGPoint(x: 80, y: 900), 40),
                ("Data 01.10.2026  Godziny 8:00 - 10:00", CGPoint(x: 600, y: 700), 36),
                ("Projekt Fundusze Europejskie", CGPoint(x: 1000, y: 450), 32),
                ("Podpis", CGPoint(x: 1300, y: 150), 44),
                ("SUMA GODZIN 45", CGPoint(x: 120, y: 200), 44),
            ]
            for (text, point, size) in lines {
                let bounds = Synthetic.drawText(text, at: point, size: size, in: ctx)
                rects.append(Synthetic.flip(bounds, height: height).insetBy(dx: -8, dy: -8))
            }
            // Shadow: multiply by a horizontal gradient 1.0 → 0.45.
            ctx.setBlendMode(.multiply)
            let gradient = CGGradient(
                colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                colors: [Synthetic.gray(1), Synthetic.gray(0.45)] as CFArray,
                locations: [0, 1]
            )!
            ctx.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: width, y: 0), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        }
        return (image, rects)
    }

    @Test func originalReturnsIdenticalPixels() throws {
        let (page, _) = Self.shadowedPage(width: 400, height: 300)
        let out = try engine.apply(.original, to: page)
        #expect(out.width == page.width && out.height == page.height)
        #expect(Bitmap(out).bytes == Bitmap(page).bytes)
    }

    @Test func blackAndWhiteRemovesShadowAndKeepsText() throws {
        let (page, textRects) = Self.shadowedPage()
        // Sanity: the input really is shadowed on the right.
        #expect(Bitmap(page)[page.width - 5, 5].luminance < 130)

        let out = try engine.apply(.blackAndWhite, to: page)
        #expect(out.width == page.width && out.height == page.height)
        let bmp = Bitmap(out)

        var background = 0, brightBackground = 0
        for y in 0..<bmp.height {
            for x in 0..<bmp.width {
                let p = CGPoint(x: x, y: y)
                if textRects.contains(where: { $0.contains(p) }) { continue }
                background += 1
                if bmp[x, y].luminance > 230 { brightBackground += 1 }
            }
        }
        let ratio = Double(brightBackground) / Double(background)
        print("B&W synthetic: bright background ratio \(ratio)")
        #expect(ratio >= 0.97)

        for rect in textRects {
            var darkest = 255.0
            for y in Int(rect.minY)..<Int(rect.maxY) {
                for x in Int(rect.minX)..<Int(rect.maxX) where x >= 0 && y >= 0 && x < bmp.width && y < bmp.height {
                    darkest = min(darkest, bmp[x, y].luminance)
                }
            }
            #expect(darkest < 60, "text in \(rect) lost (darkest \(darkest))")
        }
    }

    @Test func grayscaleHasEqualChannels() throws {
        let colorful = Synthetic.image(width: 300, height: 200, background: CGColor(srgbRed: 0.9, green: 0.85, blue: 0.7, alpha: 1)) { ctx in
            ctx.setFillColor(CGColor(srgbRed: 0.1, green: 0.3, blue: 0.9, alpha: 1))
            ctx.fill(CGRect(x: 20, y: 20, width: 100, height: 80))
            ctx.setFillColor(CGColor(srgbRed: 0.9, green: 0.1, blue: 0.1, alpha: 1))
            ctx.fill(CGRect(x: 160, y: 100, width: 100, height: 80))
        }
        let out = try engine.apply(.grayscale, to: colorful)
        #expect(out.width == 300 && out.height == 200)
        let bmp = Bitmap(out)
        let maxSpread = (0..<bmp.height).flatMap { y in (0..<bmp.width).map { x -> Int in
            let p = bmp[x, y]
            return Int(max(p.r, p.g, p.b)) - Int(min(p.r, p.g, p.b))
        } }.max() ?? 0
        #expect(maxSpread <= 2)
    }

    @Test func colorWhitensPaperAndKeepsSize() throws {
        // Yellowish, dim paper with a dark mark: the colour filter should make the paper ≈ white.
        let paper = Synthetic.image(width: 500, height: 400, background: CGColor(srgbRed: 0.78, green: 0.74, blue: 0.62, alpha: 1)) { ctx in
            ctx.setFillColor(Synthetic.gray(0.1))
            ctx.fill(CGRect(x: 50, y: 50, width: 120, height: 40))
        }
        let out = try engine.apply(.color, to: paper)
        #expect(out.width == 500 && out.height == 400)
        let p = Bitmap(out)[400, 50]
        #expect(p.r > 240 && p.g > 240 && p.b > 235)
        #expect(Bitmap(out)[100, 330].luminance < 60)
    }

    // MARK: - Magic colour (.color / .grayscale)

    struct MagicPage {
        var image: CGImage
        /// Glyph pixels (dark in the unshadowed page), top-left origin, row-major.
        var isText: [Bool]
        /// Padded text and stamp regions (top-left origin); everything else is paper.
        var nonPaper: [CGRect]
        /// The saturated red stamp (top-left origin).
        var stamp: CGRect
    }

    static let stampColor = CGColor(srgbRed: 0.85, green: 0.15, blue: 0.12, alpha: 1)

    /// `shadowedPage`-like text plus a saturated red stamp, under the same 100 % → 45 % shadow.
    static func magicPage(width: Int = 1600, height: Int = 1200) -> MagicPage {
        let stampBL = CGRect(x: 1050, y: 760, width: 160, height: 120)
        func draw(shadow: Bool) -> (CGImage, [CGRect]) {
            var rects: [CGRect] = []
            let image = Synthetic.image(width: width, height: height, background: Synthetic.gray(1)) { ctx in
                let lines: [(String, CGPoint, CGFloat)] = [
                    ("HARMONOGRAM PAŹDZIERNIK 2026", CGPoint(x: 80, y: 1050), 56),
                    ("Dziennik zajęć — kurs fotografii dla początkujących", CGPoint(x: 80, y: 900), 40),
                    ("Data 01.10.2026  Godziny 8:00 - 10:00", CGPoint(x: 600, y: 600), 36),
                    ("Projekt Fundusze Europejskie", CGPoint(x: 1000, y: 450), 32),
                    ("Podpis", CGPoint(x: 1300, y: 150), 44),
                    ("SUMA GODZIN 45", CGPoint(x: 120, y: 200), 44),
                ]
                for (text, point, size) in lines {
                    let bounds = Synthetic.drawText(text, at: point, size: size, in: ctx)
                    rects.append(Synthetic.flip(bounds, height: height).insetBy(dx: -8, dy: -8))
                }
                ctx.setFillColor(stampColor)
                ctx.fill(stampBL)
                guard shadow else { return }
                ctx.setBlendMode(.multiply)
                let gradient = CGGradient(
                    colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                    colors: [Synthetic.gray(1), Synthetic.gray(0.45)] as CFArray,
                    locations: [0, 1]
                )!
                ctx.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: width, y: 0), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
            }
            return (image, rects)
        }
        let (shadowed, rects) = draw(shadow: true)
        let (clean, _) = draw(shadow: false)
        let stamp = Synthetic.flip(stampBL, height: height)
        let stampZone = stamp.insetBy(dx: -4, dy: -4)
        let cleanBitmap = Bitmap(clean)
        var isText = [Bool](repeating: false, count: width * height)
        for y in 0..<height {
            for x in 0..<width where cleanBitmap[x, y].luminance < 40 {
                isText[y * width + x] = !stampZone.contains(CGPoint(x: x, y: y))
            }
        }
        return MagicPage(image: shadowed, isText: isText, nonPaper: rects + [stamp.insetBy(dx: -8, dy: -8)], stamp: stamp)
    }

    /// HSV saturation (max − min) / max of an sRGB pixel.
    static func saturation(_ p: Bitmap.Pixel) -> Double {
        let hi = Double(max(p.r, p.g, p.b)), lo = Double(min(p.r, p.g, p.b))
        return hi > 0 ? (hi - lo) / hi : 0
    }

    static func meanSaturation(_ bmp: Bitmap, in rect: CGRect) -> Double {
        var sum = 0.0, n = 0
        for y in Int(rect.minY)..<Int(rect.maxY) {
            for x in Int(rect.minX)..<Int(rect.maxX) { sum += saturation(bmp[x, y]); n += 1 }
        }
        return sum / Double(max(1, n))
    }

    /// ≥ 97 % of the paper pixels must be white (> 235) and ≥ 99 % of the glyph pixels dark (< 80).
    static func checkPaperAndText(_ out: CGImage, _ page: MagicPage, label: String) {
        let bmp = Bitmap(out)
        var paper = 0, whitePaper = 0, text = 0, darkText = 0
        var darkestPaper = 255.0
        for y in 0..<bmp.height {
            for x in 0..<bmp.width {
                let lum = bmp[x, y].luminance
                if page.isText[y * bmp.width + x] {
                    text += 1
                    if lum < 80 { darkText += 1 }
                    continue
                }
                let p = CGPoint(x: x, y: y)
                if page.nonPaper.contains(where: { $0.contains(p) }) { continue }
                paper += 1
                if lum > 235 { whitePaper += 1 }
                darkestPaper = min(darkestPaper, lum)
            }
        }
        let paperRatio = Double(whitePaper) / Double(paper)
        let textRatio = Double(darkText) / Double(text)
        print("\(label): white paper \(paperRatio) (darkest \(darkestPaper)), dark text \(textRatio) of \(text) px")
        #expect(paperRatio >= 0.97, "\(label): only \(paperRatio) of the paper is white")
        #expect(textRatio >= 0.99, "\(label): only \(textRatio) of the text pixels are < 80")
    }

    @Test func colorFlattensShadowWhitensPaperAndKeepsColours() throws {
        let page = Self.magicPage()
        #expect(Bitmap(page.image)[page.image.width - 5, 5].luminance < 130)

        let out = try engine.apply(.color, to: page.image)
        #expect(out.width == page.image.width && out.height == page.image.height)
        Self.checkPaperAndText(out, page, label: "color")

        let inner = page.stamp.insetBy(dx: 10, dy: 10)
        let before = Self.meanSaturation(Bitmap(page.image), in: inner)
        let after = Self.meanSaturation(Bitmap(out), in: inner)
        let centre = Bitmap(out)[Int(inner.midX), Int(inner.midY)]
        print("color: stamp saturation \(before) → \(after), centre \(centre)")
        #expect(after >= before)
        #expect(centre.r > 150 && centre.g < 90 && centre.b < 90, "stamp is no longer red: \(centre)")
    }

    @Test func grayscaleFlattensShadowAndWhitensPaper() throws {
        let page = Self.magicPage()
        let out = try engine.apply(.grayscale, to: page.image)
        #expect(out.width == page.image.width && out.height == page.image.height)
        Self.checkPaperAndText(out, page, label: "grayscale")
        let bmp = Bitmap(out)
        var maxSpread = 0
        for y in Swift.stride(from: 0, to: bmp.height, by: 3) {
            for x in Swift.stride(from: 0, to: bmp.width, by: 3) {
                let p = bmp[x, y]
                maxSpread = max(maxSpread, Int(max(p.r, p.g, p.b)) - Int(min(p.r, p.g, p.b)))
            }
        }
        #expect(maxSpread <= 2)
    }

    /// A big black box on dim, slightly warm paper: the box must not leak into the paper estimate
    /// (no dark/bright halo around it) and must itself stay black.
    @Test(arguments: [ScanFilter.color, .grayscale])
    func noHaloAroundLargeDarkRegions(filter: ScanFilter) throws {
        let width = 1600, height = 1200
        let box = CGRect(x: 300, y: 200, width: 700, height: 450) // top-left origin, upper half
        let image = Synthetic.image(width: width, height: height, background: CGColor(srgbRed: 0.8, green: 0.77, blue: 0.7, alpha: 1)) { ctx in
            ctx.setFillColor(Synthetic.gray(0.04))
            ctx.fill(Synthetic.flip(box, height: height))
            Synthetic.drawText("Rzut parteru 1:100", at: CGPoint(x: 300, y: 200), size: 48, in: ctx)
        }
        let out = try engine.apply(filter, to: image)
        let bmp = Bitmap(out)

        // Reference paper level, far from the box and the text.
        let reference = bmp[1450, 1100].luminance
        #expect(reference > 235)
        var worst = 0.0
        // Rings 40…100 px outside the box.
        for d in Swift.stride(from: 40, through: 100, by: 20) {
            let ring = box.insetBy(dx: CGFloat(-d), dy: CGFloat(-d))
            for x in Int(ring.minX)..<Int(ring.maxX) {
                worst = max(worst, abs(bmp[x, Int(ring.minY)].luminance - reference))
                worst = max(worst, abs(bmp[x, Int(ring.maxY)].luminance - reference))
            }
            for y in Int(ring.minY)..<Int(ring.maxY) {
                worst = max(worst, abs(bmp[Int(ring.minX), y].luminance - reference))
                worst = max(worst, abs(bmp[Int(ring.maxX), y].luminance - reference))
            }
        }
        let inside = bmp[Int(box.midX), Int(box.midY)].luminance
        let insideEdge = bmp[Int(box.minX) + 20, Int(box.minY) + 20].luminance
        print("halo[\(filter)]: paper \(reference), worst ring deviation \(worst), box centre \(inside), near edge \(insideEdge)")
        #expect(worst <= 10)
        #expect(inside < 40 && insideEdge < 40)
    }
}
