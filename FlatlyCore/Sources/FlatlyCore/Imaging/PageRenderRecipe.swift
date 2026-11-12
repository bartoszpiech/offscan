import Foundation
import CoreGraphics

/// Everything needed to turn a page's stored *original* image into its displayed/exported image.
/// Order of operations in `PageRenderer`: crop → filter → rotate → signature.
public struct PageRenderRecipe: Sendable, Hashable, Codable {
    /// Normalised crop rectangle with **top-left** origin, relative to the original. `nil` = no crop.
    public var cropRect: CGRect?
    public var filter: ScanFilter
    public var rotation: Rotation
    /// Signature composited last, so its frame is relative to the rotated, cropped image.
    public var signature: SignaturePlacement?

    public init(cropRect: CGRect? = nil, filter: ScanFilter = .color, rotation: Rotation = .none, signature: SignaturePlacement? = nil) {
        self.cropRect = cropRect
        self.filter = filter
        self.rotation = rotation
        self.signature = signature
    }

    public static let `default` = PageRenderRecipe()
}
