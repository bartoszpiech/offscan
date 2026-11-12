import Foundation
import CoreGraphics

/// Single-page JPEG export honouring a `CompressionLevel`.
public struct JPEGExporter: Sendable {
    public init() {}

    /// Encodes `image` as JPEG using `compression.jpegQuality`. Downsampling to
    /// `compression.maxPixelDimension` is the caller's job.
    public func makeJPEG(_ image: CGImage, compression: CompressionLevel) throws -> Data {
        try JPEGEncoding.encode(image, quality: compression.jpegQuality)
    }
}
