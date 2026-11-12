import Foundation
import CoreGraphics
import CoreImage
import ImageIO

extension CGImage {
    /// The colour space to keep when redrawing this image: its own if it is RGB, otherwise sRGB.
    var rgbOutputColorSpace: CGColorSpace {
        if let cs = colorSpace, cs.model == .rgb { return cs }
        return CIContextProvider.sRGB
    }

    /// An 8-bit premultiplied RGBA bitmap context in this image's (RGB) colour space.
    func makeRGBAContext(width: Int, height: Int) throws -> CGContext {
        guard width > 0, height > 0,
              let ctx = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: rgbOutputColorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { throw FlatlyCoreError.processingFailed("Cannot create bitmap context \(width)x\(height)") }
        return ctx
    }

    /// Returns the image re-drawn so that the EXIF `orientation` is applied (i.e. upright).
    /// Exact for all eight orientations (pure pixel moves, no resampling).
    func applyingOrientation(_ orientation: CGImagePropertyOrientation) throws -> CGImage {
        if orientation == .up { return self }
        let w = CGFloat(width), h = CGFloat(height)
        // `orientationTransform` maps the stored image (bottom-left origin) onto the upright one.
        let transform = CIImage(cgImage: self).orientationTransform(for: orientation)
        let outRect = CGRect(x: 0, y: 0, width: w, height: h).applying(transform).integral
        let ctx = try makeRGBAContext(width: Int(outRect.width), height: Int(outRect.height))
        ctx.interpolationQuality = .none
        ctx.translateBy(x: -outRect.minX, y: -outRect.minY)
        ctx.concatenate(transform)
        ctx.draw(self, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let out = ctx.makeImage() else { throw FlatlyCoreError.processingFailed("Orientation render failed") }
        return out
    }
}
