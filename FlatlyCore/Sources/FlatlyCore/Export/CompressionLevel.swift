import Foundation
import CoreGraphics

/// Trade-off between file size and image quality for exports.
public enum CompressionLevel: String, CaseIterable, Sendable, Codable, Hashable {
    /// Best quality, biggest file.
    case low
    case medium
    /// Smallest file.
    case high

    public var jpegQuality: CGFloat {
        switch self {
        case .low: return 0.9
        case .medium: return 0.7
        case .high: return 0.5
        }
    }

    /// Longest image side in pixels after downsampling for export.
    public var maxPixelDimension: Int {
        switch self {
        case .low: return 3000
        case .medium: return 2200
        case .high: return 1600
        }
    }
}
