import Foundation

/// The result of `DocumentDetector.detect(in:)`.
public struct DetectedDocument: Sendable, Hashable {
    /// Which detector produced the quad.
    public enum Source: String, Sendable, Hashable, Codable {
        case segmentation, rectangles, fullFrame
    }
    public var quad: Quadrilateral
    /// 0...1. `fullFrame` fallbacks report 0.
    public var confidence: Float
    public var source: Source

    public init(quad: Quadrilateral, confidence: Float, source: Source) {
        self.quad = quad
        self.confidence = confidence
        self.source = source
    }
}
