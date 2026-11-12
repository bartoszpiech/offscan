#if DEBUG
import UIKit
import FlatlyCore

/// One synthetic page of the demo library: its pixel size, how it was "captured" and a drawing
/// closure that lays out its content on a `DemoPageCanvas`.
struct DemoPageSpec: Sendable {
    enum Capture: Sendable {
        /// A camera scan: the drawn page becomes the corrected image directly.
        case scan
        /// An imported photo: the page is photographed lying at an angle on a desk
        /// (`DemoDeskPhoto`), so the page keeps a source photo whose edges can be adjusted.
        case deskPhoto
    }

    /// The rendered page and the text a perfect OCR pass would find on it.
    struct Rendered: Sendable {
        let image: CGImage
        let ocr: OCRResult
    }

    let size: CGSize
    var capture: Capture = .scan
    let draw: @Sendable (DemoPageCanvas) -> Void

    init(size: CGSize, capture: Capture = .scan, draw: @escaping @Sendable (DemoPageCanvas) -> Void) {
        self.size = size
        self.capture = capture
        self.draw = draw
    }

    /// Draws the page on white paper (8-bit sRGB, scale 1). Safe to call off the main actor.
    func render() -> Rendered? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        format.preferredRange = .standard
        var lines: [OCRLine] = []
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            let canvas = DemoPageCanvas(size: size, context: context.cgContext)
            draw(canvas)
            lines = canvas.lines
        }
        guard let cgImage = image.cgImage else { return nil }
        return Rendered(image: cgImage, ocr: OCRResult(lines: lines))
    }
}
#endif
