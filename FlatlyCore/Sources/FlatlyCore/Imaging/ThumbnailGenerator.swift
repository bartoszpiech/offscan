import Foundation
import CoreGraphics

/// Small preview images for the library grid.
public struct ThumbnailGenerator: Sendable {
    public init() {}

    /// Downsamples `image` so its longest side is at most `maxDimension` pixels (aspect ratio kept).
    public func thumbnail(for image: CGImage, maxDimension: Int = 400) throws -> CGImage {
        try ImageTransforms().resized(image, maxDimension: maxDimension)
    }
}
