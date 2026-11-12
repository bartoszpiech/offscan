import Foundation
import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins

/// Warps the region inside a `Quadrilateral` into a flat, axis-aligned rectangle (CIPerspectiveCorrection).
public struct PerspectiveCorrector: Sendable {
    public init() {}

    /// - Parameters:
    ///   - quad: normalised corners, bottom-left origin.
    ///   - focalLength35mm: the 35 mm-equivalent focal length of the uncropped camera frame `image`
    ///     is, when known (EXIF `FocalLenIn35mmFilm`). With it the page's aspect ratio follows the
    ///     real sheet (Zhang–He rectangle recovery, principal point at the image centre), so a page
    ///     shot at an angle isn't squashed; implausible results fall back to the average edges.
    /// - Returns: the corrected image. Without a focal length its size follows the quad's average
    ///   edge lengths in pixels; with one, the longer of those is kept and the other side follows
    ///   the recovered aspect ratio (no side is smaller than without it).
    public func correct(_ image: CGImage, to quad: Quadrilateral, focalLength35mm: Double? = nil) throws -> CGImage {
        guard quad.isConvex, quad.area > 0 else { throw FlatlyCoreError.invalidQuadrilateral }
        let size = CGSize(width: image.width, height: image.height)
        // Normalised bottom-left origin × pixel size = CIImage pixel space (also bottom-left).
        let px = quad.scaled(to: size)

        let input = CIImage(cgImage: image)
        let filter = CIFilter.perspectiveCorrection()
        // Clamp so corners lying on (or slightly beyond) the image border sample edge pixels
        // instead of transparent black.
        filter.inputImage = input.clampedToExtent()
        filter.topLeft = px.topLeft
        filter.topRight = px.topRight
        filter.bottomRight = px.bottomRight
        filter.bottomLeft = px.bottomLeft
        filter.crop = true
        guard var output = filter.outputImage else {
            throw FlatlyCoreError.processingFailed("CIPerspectiveCorrection produced no output")
        }

        // Scale to the size of the flattened sheet.
        let target = Self.targetSize(for: px, imageSize: size, focalLength35mm: focalLength35mm)
        let targetWidth = target.width, targetHeight = target.height
        guard targetWidth >= 1, targetHeight >= 1 else { throw FlatlyCoreError.invalidQuadrilateral }

        var extent = output.extent
        guard !extent.isInfinite, !extent.isEmpty else {
            throw FlatlyCoreError.processingFailed("CIPerspectiveCorrection produced an unbounded image")
        }
        output = output.transformed(by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY))
        let sx = targetWidth / extent.width, sy = targetHeight / extent.height
        if abs(sx - 1) > 0.01 || abs(sy - 1) > 0.01 {
            output = output.clampedToExtent()
                .transformed(by: CGAffineTransform(scaleX: sx, y: sy), highQualityDownsample: true)
        }
        extent = CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight)
        return try CIContextProvider.render(output, from: extent, colorSpace: image.rgbOutputColorSpace)
    }

    /// Largest accepted change of the aspect ratio by the focal-length correction. A genuine
    /// correction is about 20 % at a 40° tilt; anything larger means the focal length does not
    /// describe this frame (e.g. a cropped photo), so the average edges are used instead.
    static let maximumAspectCorrection: Double = 1.25

    /// Pixel size of the flattened sheet for the pixel-space quad `px` (bottom-left origin) in an
    /// image of `imageSize`.
    ///
    /// Without a usable focal length (nil, not finite or outside 8…400 mm) the size is the quad's
    /// average edge lengths, which squashes sheets shot at an angle (the far edge is foreshortened).
    /// With the 35 mm-equivalent focal length of the uncropped frame, the aspect ratio comes from
    /// Zhang & He's rectangle recovery ("Whiteboard scanning and image enhancement", 2007) with the
    /// principal point at the image centre; parallel-edged quads give exactly their edge ratio.
    static func targetSize(for px: Quadrilateral, imageSize: CGSize, focalLength35mm: Double?) -> CGSize {
        func dist(_ a: CGPoint, _ b: CGPoint) -> Double { Double(hypot(a.x - b.x, a.y - b.y)) }
        let avgW = (dist(px.topLeft, px.topRight) + dist(px.bottomLeft, px.bottomRight)) / 2
        let avgH = (dist(px.topLeft, px.bottomLeft) + dist(px.topRight, px.bottomRight)) / 2
        let fallback = CGSize(width: avgW.rounded(), height: avgH.rounded())
        guard let f35 = focalLength35mm, f35.isFinite, (8...400).contains(f35), avgW > 0, avgH > 0 else { return fallback }

        // Focal length in pixels: 43.27 mm is the diagonal of the 35 mm full frame.
        let fPx = f35 * Double(hypot(imageSize.width, imageSize.height)) / 43.27
        let cx = Double(imageSize.width) / 2, cy = Double(imageSize.height) / 2
        typealias Vec = (x: Double, y: Double, z: Double)
        func vec(_ p: CGPoint) -> Vec { (Double(p.x) - cx, Double(p.y) - cy, 1) }
        func cross(_ a: Vec, _ b: Vec) -> Vec { (a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x) }
        func dot(_ a: Vec, _ b: Vec) -> Double { a.x * b.x + a.y * b.y + a.z * b.z }
        func minus(_ a: Vec, _ b: Vec) -> Vec { (a.x - b.x, a.y - b.y, a.z - b.z) }
        func scaled(_ a: Vec, _ k: Double) -> Vec { (a.x * k, a.y * k, a.z * k) }
        // Squared length of the sheet edge direction in camera space (A⁻¹ n), up to a common factor.
        func norm(_ n: Vec) -> Double { (n.x * n.x + n.y * n.y) / (fPx * fPx) + n.z * n.z }

        let m1 = vec(px.topLeft), m2 = vec(px.topRight), m3 = vec(px.bottomLeft), m4 = vec(px.bottomRight)
        let k2 = dot(cross(m1, m4), m3) / dot(cross(m2, m4), m3)
        let k3 = dot(cross(m1, m4), m2) / dot(cross(m3, m4), m2)
        let n2 = minus(scaled(m2, k2), m1)   // along the width (top-left → top-right)
        let n3 = minus(scaled(m3, k3), m1)   // along the height (top-left → bottom-left)
        let aspect = (norm(n3) / norm(n2)).squareRoot()   // height / width of the real sheet
        let avgAspect = avgH / avgW
        guard aspect.isFinite, aspect > 0,
              (1 / Self.maximumAspectCorrection...Self.maximumAspectCorrection).contains(aspect / avgAspect) else { return fallback }
        // Keep the longer measured side and stretch the other, so no side loses resolution.
        if aspect >= avgAspect {
            return CGSize(width: avgW.rounded(), height: (avgW * aspect).rounded())
        } else {
            return CGSize(width: (avgH / aspect).rounded(), height: avgH.rounded())
        }
    }
}
