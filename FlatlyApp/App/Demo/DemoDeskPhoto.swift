#if DEBUG
import UIKit
import CoreImage
import CoreImage.CIFilterBuiltins
import FlatlyCore

/// A phone-style photo of a demo page lying at an angle on a wooden desk, with the page's corners,
/// so a seeded page can go through the regular import path (`ScanProcessor.finishImport`) and keep
/// a source photo for "Adjust Edges".
enum DemoDeskPhoto {
    struct Photo: Sendable {
        let image: CGImage
        /// The sheet's corners, normalised with a bottom-left origin (FlatlyCore's convention).
        let quad: Quadrilateral
    }

    static let size = CGSize(width: 1500, height: 2000)

    /// The sheet's corners in the photo (top-left origin, pixels): rotated a little and seen
    /// slightly from the bottom, so the top edge is shorter than the bottom one.
    private static let topLeft = CGPoint(x: 262, y: 300)
    private static let topRight = CGPoint(x: 1236, y: 342)
    private static let bottomRight = CGPoint(x: 1318, y: 1742)
    private static let bottomLeft = CGPoint(x: 168, y: 1704)

    /// Photographs `page`. Safe to call off the main actor.
    static func compose(page: CGImage) -> Photo? {
        guard let warped = warp(page) else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        format.preferredRange = .standard
        let canvas = CGRect(origin: .zero, size: size)
        let image = UIGraphicsImageRenderer(size: size, format: format).image { renderer in
            let context = renderer.cgContext
            drawDesk(in: context)
            drawPen(in: context)

            // The sheet: a soft shadow first, then the warped page on top.
            let sheet = sheetPath()
            context.saveGState()
            context.setShadow(offset: CGSize(width: 16, height: 24), blur: 42, color: UIColor.black.withAlphaComponent(0.5).cgColor)
            UIColor(white: 0.96, alpha: 1).setFill()
            sheet.fill()
            context.restoreGState()
            UIImage(cgImage: warped).draw(in: canvas)

            // Uneven room light and a warm cast on the paper, which the scan filters flatten.
            context.saveGState()
            sheet.addClip()
            let light = CGGradient(
                colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                colors: [UIColor(white: 1, alpha: 0.10).cgColor, UIColor(red: 0.25, green: 0.18, blue: 0.08, alpha: 0.20).cgColor] as CFArray,
                locations: [0, 1]
            )
            if let light {
                context.drawLinearGradient(light, start: topLeft, end: bottomRight, options: [])
            }
            UIColor(red: 1, green: 0.86, blue: 0.62, alpha: 0.07).setFill()
            context.fill(canvas)
            context.restoreGState()

            drawVignette(in: context)
        }
        guard let cgImage = image.cgImage else { return nil }
        return Photo(image: cgImage, quad: sheetQuad)
    }

    /// The sheet's corners in every photo, normalised with a bottom-left origin (FlatlyCore's
    /// convention). Safe to call off the main actor.
    static var sheetQuad: Quadrilateral {
        func normalised(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x / size.width, y: 1 - p.y / size.height) }
        return Quadrilateral(
            topLeft: normalised(topLeft),
            topRight: normalised(topRight),
            bottomRight: normalised(bottomRight),
            bottomLeft: normalised(bottomLeft)
        )
    }

    // MARK: Private

    private static func sheetPath() -> UIBezierPath {
        let path = UIBezierPath()
        path.move(to: topLeft)
        path.addLine(to: topRight)
        path.addLine(to: bottomRight)
        path.addLine(to: bottomLeft)
        path.close()
        return path
    }

    /// Maps the page onto the sheet's corners with Core Image; transparent outside the sheet.
    private static func warp(_ page: CGImage) -> CGImage? {
        func ciPoint(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x, y: size.height - p.y) }
        let filter = CIFilter.perspectiveTransform()
        filter.inputImage = CIImage(cgImage: page)
        filter.topLeft = ciPoint(topLeft)
        filter.topRight = ciPoint(topRight)
        filter.bottomRight = ciPoint(bottomRight)
        filter.bottomLeft = ciPoint(bottomLeft)
        guard let output = filter.outputImage else { return nil }
        let context = CIContext(options: [.cacheIntermediates: false])
        return context.createCGImage(
            output,
            from: CGRect(origin: .zero, size: size),
            format: .RGBA8,
            colorSpace: CGColorSpace(name: CGColorSpace.sRGB)
        )
    }

    /// Warm wooden planks with wavy grain.
    private static func drawDesk(in context: CGContext) {
        let canvas = CGRect(origin: .zero, size: size)
        let wood = CGGradient(
            colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
            colors: [
                UIColor(red: 0.55, green: 0.37, blue: 0.23, alpha: 1).cgColor,
                UIColor(red: 0.42, green: 0.27, blue: 0.16, alpha: 1).cgColor,
            ] as CFArray,
            locations: [0, 1]
        )
        UIColor(red: 0.47, green: 0.31, blue: 0.19, alpha: 1).setFill()
        context.fill(canvas)
        if let wood {
            context.drawLinearGradient(
                wood, start: .zero, end: CGPoint(x: size.width * 0.3, y: size.height),
                options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
            )
        }
        var random = DemoRandom(seed: 7)
        for _ in 0..<190 {
            let y = random.next(in: -40...(size.height + 40))
            let amplitude = random.next(in: CGFloat(2)...16)
            let frequency = random.next(in: 0.0015...0.006)
            let phase = random.next(in: 0...6.28)
            let dark = random.next() % 3 != 0
            let color = dark
                ? UIColor(red: 0.24, green: 0.13, blue: 0.06, alpha: random.next(in: 0.06...0.22))
                : UIColor(red: 0.85, green: 0.65, blue: 0.45, alpha: random.next(in: 0.04...0.12))
            let path = UIBezierPath()
            path.move(to: CGPoint(x: -10, y: y))
            var x: CGFloat = -10
            while x <= size.width + 10 {
                x += 18
                let wave: CGFloat = amplitude * sin(x * frequency + phase)
                let bow: CGFloat = 0.00003 * x * x
                path.addLine(to: CGPoint(x: x, y: y + wave + bow))
            }
            path.lineWidth = random.next(in: 0.8...4.5)
            color.setStroke()
            path.stroke()
        }
        // Plank seams.
        for seam in [CGFloat(560), 1260] {
            UIColor(red: 0.16, green: 0.08, blue: 0.03, alpha: 0.65).setFill()
            context.fill(CGRect(x: 0, y: seam, width: size.width, height: 5))
            UIColor(red: 0.9, green: 0.7, blue: 0.5, alpha: 0.12).setFill()
            context.fill(CGRect(x: 0, y: seam + 5, width: size.width, height: 3))
        }
    }

    /// A ballpoint pen lying next to the sheet.
    private static func drawPen(in context: CGContext) {
        context.saveGState()
        context.translateBy(x: 1395, y: 1250)
        context.rotate(by: 0.32)
        context.setShadow(offset: CGSize(width: 10, height: 14), blur: 18, color: UIColor.black.withAlphaComponent(0.45).cgColor)
        UIColor(red: 0.10, green: 0.16, blue: 0.36, alpha: 1).setFill()
        UIBezierPath(roundedRect: CGRect(x: -15, y: -300, width: 30, height: 520), cornerRadius: 15).fill()
        context.setShadow(offset: .zero, blur: 0, color: nil)
        UIColor(white: 0.82, alpha: 1).setFill()
        let tip = UIBezierPath()
        tip.move(to: CGPoint(x: -13, y: 214))
        tip.addLine(to: CGPoint(x: 13, y: 214))
        tip.addLine(to: CGPoint(x: 0, y: 268))
        tip.close()
        tip.fill()
        UIColor(white: 1, alpha: 0.25).setFill()
        context.fill(CGRect(x: -8, y: -290, width: 5, height: 490))
        UIColor(white: 0.75, alpha: 1).setFill()
        UIBezierPath(roundedRect: CGRect(x: 9, y: -270, width: 10, height: 170), cornerRadius: 4).fill()
        context.restoreGState()
    }

    private static func drawVignette(in context: CGContext) {
        let center = CGPoint(x: size.width / 2, y: size.height * 0.48)
        let radius = hypot(size.width, size.height) / 2
        let vignette = CGGradient(
            colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
            colors: [UIColor.black.withAlphaComponent(0).cgColor, UIColor.black.withAlphaComponent(0.38).cgColor] as CFArray,
            locations: [0.55, 1]
        )
        if let vignette {
            context.drawRadialGradient(vignette, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: [.drawsAfterEndLocation])
        }
    }
}
#endif
