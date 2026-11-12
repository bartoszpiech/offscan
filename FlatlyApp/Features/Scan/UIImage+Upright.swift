import UIKit

extension UIImage {
    /// A `CGImage` whose pixels are upright (`imageOrientation` applied). Returns the backing
    /// `CGImage` directly when the image is already `.up`; otherwise redraws it.
    func uprightCGImage() -> CGImage? {
        if imageOrientation == .up, let cgImage { return cgImage }
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let redrawn = renderer.image { _ in draw(in: CGRect(origin: .zero, size: size)) }
        return redrawn.cgImage
    }
}
