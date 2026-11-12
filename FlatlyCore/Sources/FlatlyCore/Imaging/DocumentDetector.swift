import Foundation
import CoreGraphics
import CoreVideo
import ImageIO
import Vision

/// Finds the document sheet in a photo.
///
/// Strategy: `VNDetectDocumentSegmentationRequest` (returns a quad + confidence). If it fails or
/// its confidence is low, fall back to `VNDetectRectanglesRequest` (largest high-confidence rect).
/// If nothing is found, return `Quadrilateral.fullFrame` with `source: .fullFrame`.
public struct DocumentDetector: Sendable {
    public init() {}

    /// Minimum confidence accepted from the segmentation request.
    static let minimumSegmentationConfidence: Float = 0.5
    /// Minimum normalised area of an accepted segmentation quad.
    static let minimumSegmentationArea: CGFloat = 0.08

    public func detect(in image: CGImage) throws -> DetectedDocument {
        let handler = VNImageRequestHandler(cgImage: image, options: [:])

        if let segmented = try? segmentation(handler: handler) {
            return segmented
        }
        if let rectangle = try? rectangles(handler: handler) {
            return rectangle
        }
        return DetectedDocument(quad: .fullFrame, confidence: 0, source: .fullFrame)
    }

    /// Fast detection for live camera frames: document segmentation only, no fallbacks.
    ///
    /// - Parameters:
    ///   - pixelBuffer: a camera frame as delivered by the capture output (sensor orientation).
    ///   - orientation: how to rotate the buffer to make it upright (e.g. `.right` for a portrait
    ///     iPhone with the back camera). The returned quad is in that **upright** image's normalised,
    ///     bottom-left-origin space, like every other `Quadrilateral`.
    /// - Returns: nil when no sheet is found with sufficient confidence.
    public func detectLive(in pixelBuffer: CVPixelBuffer, orientation: CGImagePropertyOrientation) throws -> DetectedDocument? {
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: orientation, options: [:])
        return try segmentation(handler: handler)
    }

    // MARK: - Private

    private func segmentation(handler: VNImageRequestHandler) throws -> DetectedDocument? {
        let request = VNDetectDocumentSegmentationRequest()
        try handler.perform([request])
        let candidates = (request.results ?? [])
            .filter { $0.confidence >= Self.minimumSegmentationConfidence }
            .map { (quad: Self.quad(from: $0), confidence: $0.confidence) }
            .filter { $0.quad.isConvex && $0.quad.area >= Self.minimumSegmentationArea }
        guard let best = candidates.max(by: { $0.quad.area < $1.quad.area }) else { return nil }
        return DetectedDocument(quad: best.quad, confidence: best.confidence, source: .segmentation)
    }

    private func rectangles(handler: VNImageRequestHandler) throws -> DetectedDocument? {
        let request = VNDetectRectanglesRequest()
        request.minimumConfidence = 0.5
        request.minimumAspectRatio = 0.3
        request.maximumAspectRatio = 1.0
        request.minimumSize = 0.2
        request.quadratureTolerance = 30
        request.maximumObservations = 5
        try handler.perform([request])
        let candidates = (request.results ?? [])
            .map { (quad: Self.quad(from: $0), confidence: $0.confidence) }
            .filter { $0.quad.isConvex }
        guard let best = candidates.max(by: { $0.quad.area < $1.quad.area }) else { return nil }
        return DetectedDocument(quad: best.quad, confidence: best.confidence, source: .rectangles)
    }

    /// Vision's normalised, bottom-left-origin corners map 1:1 onto `Quadrilateral`.
    private static func quad(from observation: VNRectangleObservation) -> Quadrilateral {
        Quadrilateral(
            topLeft: observation.topLeft,
            topRight: observation.topRight,
            bottomRight: observation.bottomRight,
            bottomLeft: observation.bottomLeft
        )
    }
}
