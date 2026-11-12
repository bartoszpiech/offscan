import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// Shared ImageIO JPEG encoder for the exporters.
enum JPEGEncoding {
    /// Encodes `image` as baseline JPEG with the given lossy quality (0...1).
    static func encode(_ image: CGImage, quality: CGFloat) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw FlatlyCoreError.encodingFailed
        }
        let options: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: min(max(quality, 0), 1)
        ]
        CGImageDestinationAddImage(destination, image, options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw FlatlyCoreError.encodingFailed
        }
        return data as Data
    }
}
