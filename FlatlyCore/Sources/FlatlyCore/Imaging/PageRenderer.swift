import Foundation
import CoreGraphics

/// original → crop → filter → rotate → signature.
public struct PageRenderer: Sendable {
    public init() {}

    /// Applies `recipe` to the stored original page image.
    public func render(_ original: CGImage, recipe: PageRenderRecipe) throws -> CGImage {
        var image = original
        if let cropRect = recipe.cropRect, !Self.isFullRect(cropRect) {
            image = try ImageTransforms().crop(image, to: cropRect)
        }
        image = try FilterEngine().apply(recipe.filter, to: image)
        image = try ImageTransforms().rotate(image, by: recipe.rotation)
        if let signature = recipe.signature {
            image = try SignatureRenderer().composite(signature, onto: image)
        }
        return image
    }

    private static func isFullRect(_ rect: CGRect) -> Bool {
        let r = rect.standardized
        let eps: CGFloat = 1e-4
        return r.minX <= eps && r.minY <= eps && r.maxX >= 1 - eps && r.maxY >= 1 - eps
    }
}
