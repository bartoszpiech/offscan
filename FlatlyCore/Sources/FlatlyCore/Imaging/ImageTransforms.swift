import Foundation
import CoreGraphics
import ImageIO

/// Rotation, cropping and resizing of `CGImage`s.
public struct ImageTransforms: Sendable {
    public init() {}

    /// Rotates clockwise by whole quarter turns. Exact (no resampling).
    public func rotate(_ image: CGImage, by rotation: Rotation) throws -> CGImage {
        switch rotation {
        case .none: return image
        case .quarter: return try image.applyingOrientation(.right)          // 90° clockwise
        case .half: return try image.applyingOrientation(.down)
        case .threeQuarters: return try image.applyingOrientation(.left)     // 90° counter-clockwise
        }
    }

    /// - Parameter rect: normalised, **top-left** origin.
    public func crop(_ image: CGImage, to rect: CGRect) throws -> CGImage {
        let w = CGFloat(image.width), h = CGFloat(image.height)
        let normalized = rect.standardized.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        guard !normalized.isNull, normalized.width > 0, normalized.height > 0 else {
            throw FlatlyCoreError.processingFailed("Crop rect \(rect) is outside the image")
        }
        // CGImage.cropping(to:) uses top-left pixel coordinates, same as `rect`.
        let x = (normalized.minX * w).rounded()
        let y = (normalized.minY * h).rounded()
        let pixelRect = CGRect(
            x: x, y: y,
            width: max(1, min((normalized.width * w).rounded(), w - x)),
            height: max(1, min((normalized.height * h).rounded(), h - y))
        )
        guard let cropped = image.cropping(to: pixelRect) else {
            throw FlatlyCoreError.processingFailed("Crop failed for \(pixelRect)")
        }
        return cropped
    }

    /// Downsamples so the longest side is at most `maxDimension`; returns the input if already smaller.
    public func resized(_ image: CGImage, maxDimension: Int) throws -> CGImage {
        guard maxDimension > 0 else { throw FlatlyCoreError.processingFailed("maxDimension must be positive") }
        let longest = max(image.width, image.height)
        guard longest > maxDimension else { return image }
        let scale = Double(maxDimension) / Double(longest)
        let newWidth = max(1, Int((Double(image.width) * scale).rounded()))
        let newHeight = max(1, Int((Double(image.height) * scale).rounded()))
        let ctx = try image.makeRGBAContext(width: newWidth, height: newHeight)
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: newWidth, height: newHeight))
        guard let out = ctx.makeImage() else { throw FlatlyCoreError.processingFailed("Resize failed") }
        return out
    }
}
