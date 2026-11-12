import CoreGraphics

/// The aspect-fit rectangle of an image inside a container, plus conversions between view points
/// (top-left origin) and FlatlyCore's normalised bottom-left-origin coordinates.
struct FittedImageRect: Equatable {
    let rect: CGRect

    init(imageSize: CGSize, in bounds: CGRect) {
        guard imageSize.width > 0, imageSize.height > 0, bounds.width > 0, bounds.height > 0 else {
            rect = CGRect(origin: CGPoint(x: bounds.midX, y: bounds.midY), size: .zero)
            return
        }
        let scale = min(bounds.width / imageSize.width, bounds.height / imageSize.height)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        rect = CGRect(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2, width: size.width, height: size.height)
    }

    /// Normalised (bottom-left origin) → view point in the container (top-left origin).
    func viewPoint(_ normalised: CGPoint) -> CGPoint {
        CGPoint(x: rect.minX + normalised.x * rect.width, y: rect.minY + (1 - normalised.y) * rect.height)
    }

    /// Normalised (bottom-left origin) → point relative to the displayed image's own top-left corner.
    func localPoint(_ normalised: CGPoint) -> CGPoint {
        CGPoint(x: normalised.x * rect.width, y: (1 - normalised.y) * rect.height)
    }

    /// A drag translation in view points → a normalised delta (bottom-left origin: up is +y).
    func normalisedDelta(_ translation: CGSize) -> CGVector {
        guard rect.width > 0, rect.height > 0 else { return .zero }
        return CGVector(dx: translation.width / rect.width, dy: -translation.height / rect.height)
    }
}
