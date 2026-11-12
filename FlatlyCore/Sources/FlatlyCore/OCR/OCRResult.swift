import Foundation
import CoreGraphics

/// One recognised line of text.
public struct OCRLine: Sendable, Hashable, Codable {
    public var text: String
    /// Normalised bounding box with **bottom-left** origin (Vision convention), relative to the image OCR ran on.
    public var boundingBox: CGRect
    /// 0...1
    public var confidence: Float
    /// Which way the line's text runs on the image, in quarter turns clockwise from upright
    /// left-to-right text: `.quarter` reads top to bottom, `.half` is upside down,
    /// `.threeQuarters` reads bottom to top. `boundingBox` stays the axis-aligned box.
    /// `nil` means unknown (text recognised before this field existed, or a hand-made line)
    /// and is treated as `.none`.
    public var direction: Rotation?

    public init(text: String, boundingBox: CGRect, confidence: Float, direction: Rotation? = nil) {
        self.text = text
        self.boundingBox = boundingBox
        self.confidence = confidence
        self.direction = direction
    }
}

/// All text recognised on one page, in reading order as returned by Vision.
public struct OCRResult: Sendable, Hashable, Codable {
    public var lines: [OCRLine]

    public init(lines: [OCRLine]) { self.lines = lines }

    public static let empty = OCRResult(lines: [])

    /// Lines joined with newlines, one per observation (search, PDF text layer). For reading,
    /// copying and sharing use `readableText`, which rejoins wrapped paragraphs.
    public var text: String { lines.map(\.text).joined(separator: "\n") }
    public var isEmpty: Bool { lines.isEmpty }
}
