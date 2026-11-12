import CoreGraphics
import FlatlyCore

/// Maps live-detection outlines onto the camera preview.
///
/// A live quad is normalised with a **bottom-left** origin in the **upright** camera frame (e.g. a
/// 3024×4032 portrait image for a portrait screen). The preview layer shows that frame with
/// `.resizeAspectFill`: scaled uniformly until it covers the view, centred, the overflow cropped.
/// So the frame occupies `aspectFillRect` (which may extend past the view's bounds) and a
/// normalised point (qx, qy) lands at
///
///     x = rect.minX + qx * rect.width
///     y = rect.minY + (1 - qy) * rect.height      // flip: view space has a top-left origin
enum CameraOverlayGeometry {
    /// The rect the whole upright frame of `imageSize` covers when aspect-filled into `bounds`.
    static func aspectFillRect(imageSize: CGSize, in bounds: CGRect) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0, bounds.width > 0, bounds.height > 0 else { return bounds }
        let scale = max(bounds.width / imageSize.width, bounds.height / imageSize.height)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2, width: size.width, height: size.height)
    }

    /// A normalised, bottom-left-origin point → view point (top-left origin) inside `imageRect`.
    static func viewPoint(_ point: CGPoint, in imageRect: CGRect) -> CGPoint {
        CGPoint(x: imageRect.minX + point.x * imageRect.width, y: imageRect.minY + (1 - point.y) * imageRect.height)
    }

    /// The quad's corners in view coordinates, in the order top-left, top-right, bottom-right,
    /// bottom-left, for an upright frame of `imageSize` aspect-filled into `bounds`.
    static func viewCorners(of quad: Quadrilateral, imageSize: CGSize, in bounds: CGRect) -> [CGPoint] {
        let rect = aspectFillRect(imageSize: imageSize, in: bounds)
        return quad.corners.map { viewPoint($0, in: rect) }
    }
}
