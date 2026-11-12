import Foundation
import CoreGraphics
import CoreText
@testable import FlatlyCore

/// Programmatically generated test images (no fixtures, no dependency on ImageCodec).
enum SyntheticImages {
    static let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

    /// An RGBA (premultiplied) sRGB bitmap context, bottom-left origin.
    static func makeContext(width: Int, height: Int) -> CGContext {
        CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: sRGB,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
    }

    /// Solid colour image.
    static func solid(width: Int, height: Int, gray: CGFloat = 1) -> CGImage {
        let ctx = makeContext(width: width, height: height)
        ctx.setFillColor(CGColor(srgbRed: gray, green: gray, blue: gray, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()!
    }

    /// A white page with black Helvetica text drawn inside each normalised (bottom-left origin)
    /// box, plus a light grey texture so JPEG sizes react clearly to the quality setting.
    /// Returns the image and an `OCRResult` describing exactly those lines.
    static func page(width: Int, height: Int, lines: [(String, CGRect)]) -> (CGImage, OCRResult) {
        let ctx = makeContext(width: width, height: height)
        ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))

        // Deterministic speckle texture (simulates paper grain).
        var seed: UInt32 = 12345
        for _ in 0..<(width * height / 60) {
            seed = seed &* 1_103_515_245 &+ 12345
            let x = Int(seed >> 8) % width
            seed = seed &* 1_103_515_245 &+ 12345
            let y = Int(seed >> 8) % height
            let g = 0.75 + CGFloat(seed % 20) / 100
            ctx.setFillColor(CGColor(srgbRed: g, green: g, blue: g, alpha: 1))
            ctx.fill(CGRect(x: x, y: y, width: 2, height: 2))
        }

        var ocrLines: [OCRLine] = []
        for (text, box) in lines {
            let rect = CGRect(
                x: box.minX * CGFloat(width), y: box.minY * CGFloat(height),
                width: box.width * CGFloat(width), height: box.height * CGFloat(height)
            )
            let font = CTFontCreateWithName("Helvetica-Bold" as CFString, rect.height * 0.8, nil)
            let attributed = NSAttributedString(string: text, attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)
            ])
            let line = CTLineCreateWithAttributedString(attributed)
            ctx.textPosition = CGPoint(x: rect.minX, y: rect.minY + CTFontGetDescent(font))
            CTLineDraw(line, ctx)
            ocrLines.append(OCRLine(text: text, boundingBox: box, confidence: 1))
        }
        return (ctx.makeImage()!, OCRResult(lines: ocrLines))
    }

    /// RGBA8 premultiplied pixel buffer of `image` (top row first).
    static func pixels(of image: CGImage) -> (data: [UInt8], width: Int, height: Int) {
        let width = image.width, height = image.height
        var data = [UInt8](repeating: 0, count: width * height * 4)
        data.withUnsafeMutableBytes { buffer in
            let ctx = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: sRGB,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )!
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        return (data, width, height)
    }
}

/// Pixel accessor with **top-left** origin coordinates.
struct PixelBuffer {
    let data: [UInt8]
    let width: Int
    let height: Int

    init(_ image: CGImage) {
        let raw = SyntheticImages.pixels(of: image)
        data = raw.data
        width = raw.width
        height = raw.height
    }

    /// (r, g, b, a) at column `x`, row `y` from the top.
    func rgba(x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        let i = (y * width + x) * 4
        return (data[i], data[i + 1], data[i + 2], data[i + 3])
    }
}
