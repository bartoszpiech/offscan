import Foundation
import CoreGraphics

/// A handwritten signature (PencilKit drawing) placed on a page.
public struct SignaturePlacement: Sendable, Hashable, Codable {
    /// `PKDrawing.dataRepresentation()`.
    public var drawingData: Data
    /// Normalised frame with **top-left** origin, relative to the rotated & cropped page image.
    public var frame: CGRect

    public init(drawingData: Data, frame: CGRect) {
        self.drawingData = drawingData
        self.frame = frame
    }
}
