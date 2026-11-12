import Foundation
import CoreGraphics

/// A page ready for export: the final rendered image plus the OCR result whose coordinates are
/// relative to that image.
public struct ExportPage: Sendable {
    public var image: CGImage
    public var ocr: OCRResult?

    public init(image: CGImage, ocr: OCRResult?) {
        self.image = image
        self.ocr = ocr
    }
}
