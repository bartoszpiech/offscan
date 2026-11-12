import CoreGraphics
import FlatlyCore

/// Pure helpers for normalised (unit square, top-left origin) crop rectangles.
///
/// `PageRenderRecipe.cropRect` is applied to the *unrotated* original, but the crop editor shows
/// the original already rotated by the page's rotation, so rects are converted between both spaces.
enum CropGeometry {
    static let fullRect = CGRect(x: 0, y: 0, width: 1, height: 1)
    static let minimumSize: CGFloat = 0.05

    /// Maps a rect in unrotated image space to the image rotated clockwise by `rotation`.
    static func rotate(_ rect: CGRect, by rotation: Rotation) -> CGRect {
        let (x, y, w, h) = (rect.minX, rect.minY, rect.width, rect.height)
        switch rotation {
        case .none: return rect
        case .quarter: return CGRect(x: 1 - y - h, y: x, width: h, height: w)        // (x,y) → (1-y, x)
        case .half: return CGRect(x: 1 - x - w, y: 1 - y - h, width: w, height: h)   // (x,y) → (1-x, 1-y)
        case .threeQuarters: return CGRect(x: y, y: 1 - x - w, width: h, height: w)  // (x,y) → (y, 1-x)
        }
    }

    /// Inverse of `rotate(_:by:)`.
    static func unrotate(_ rect: CGRect, by rotation: Rotation) -> CGRect {
        rotate(rect, by: inverse(of: rotation))
    }

    static func inverse(of rotation: Rotation) -> Rotation {
        Rotation(rawValue: (4 - rotation.rawValue) % 4) ?? .none
    }

    /// Clamps `rect` into the unit square, keeping at least `minimumSize` per side.
    static func clamped(_ rect: CGRect) -> CGRect {
        var r = rect.standardized
        r.size.width = min(max(r.width, minimumSize), 1)
        r.size.height = min(max(r.height, minimumSize), 1)
        r.origin.x = min(max(r.minX, 0), 1 - r.width)
        r.origin.y = min(max(r.minY, 0), 1 - r.height)
        return r
    }

    /// True when `rect` covers (practically) the whole image, i.e. there is no crop.
    static func isFull(_ rect: CGRect) -> Bool {
        rect.minX <= 0.002 && rect.minY <= 0.002 && rect.maxX >= 0.998 && rect.maxY >= 0.998
    }

    /// Compares optional rects with a small tolerance (rotation round-trips introduce float noise).
    static func approximatelyEqual(_ a: CGRect?, _ b: CGRect?, tolerance: CGFloat = 0.001) -> Bool {
        switch (a, b) {
        case (nil, nil): return true
        case let (a?, b?):
            return abs(a.minX - b.minX) < tolerance && abs(a.minY - b.minY) < tolerance
                && abs(a.width - b.width) < tolerance && abs(a.height - b.height) < tolerance
        default: return false
        }
    }

    /// Aspect-fit rect of an image of `imageSize` inside `container`, centred.
    static func fittedRect(imageSize: CGSize, in container: CGRect) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0, container.width > 0, container.height > 0 else { return .zero }
        let scale = min(container.width / imageSize.width, container.height / imageSize.height)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(x: container.midX - size.width / 2, y: container.midY - size.height / 2, width: size.width, height: size.height)
    }
}
