import Foundation
import CoreGraphics
import Vision

/// On-device OCR via `VNRecognizeTextRequest` (accurate mode, Polish + English, automatic language detection).
public struct TextRecognizer: Sendable {
    public init() {}

    /// Preferred languages, in priority order. Polish support arrived in a later Vision release
    /// than English; intersecting with what the running OS supports keeps the request valid on
    /// older systems (Latin-script recognition still reads Polish text, diacritics may suffer).
    static let preferredLanguages = ["pl-PL", "en-US"]

    static func recognitionLanguages(for request: VNRecognizeTextRequest) -> [String] {
        guard let supported = try? request.supportedRecognitionLanguages() else { return preferredLanguages }
        let supportedSet = Set(supported.map { $0.lowercased() })
        let usable = preferredLanguages.filter { supportedSet.contains($0.lowercased()) }
        return usable.isEmpty ? ["en-US"] : usable
    }

    /// Which way text runs, bucketed to quarter turns, from a text observation's `topLeft` and
    /// `topRight` corners (normalised, bottom-left origin). The angle is measured in pixel space,
    /// so a wide image does not skew it: `.none` for upright text, `.quarter` when the text reads
    /// top to bottom, `.half` upside down, `.threeQuarters` bottom to top. Coincident corners
    /// give `.none`.
    static func textDirection(topLeft: CGPoint, topRight: CGPoint, imageSize: CGSize) -> Rotation {
        let dx = Double((topRight.x - topLeft.x) * imageSize.width)
        let dy = Double((topRight.y - topLeft.y) * imageSize.height)
        guard hypot(dx, dy) >= 1e-9 else { return .none }
        let angle = atan2(dy, dx)   // counter-clockwise positive (y up)
        let turns = Int((-angle / (.pi / 2)).rounded())
        return Rotation(rawValue: ((turns % 4) + 4) % 4)!
    }

    /// Recognises all text lines in `image`. Bounding boxes are normalised, bottom-left origin;
    /// each line also carries its text direction (sideways and upside-down text is read too).
    public func recognize(_ image: CGImage) throws -> OCRResult {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = Self.recognitionLanguages(for: request)
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            throw FlatlyCoreError.processingFailed("Text recognition failed: \(error.localizedDescription)")
        }

        let imageSize = CGSize(width: image.width, height: image.height)
        let lines: [OCRLine] = (request.results ?? []).compactMap { observation in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            let text = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            let direction = Self.textDirection(topLeft: observation.topLeft, topRight: observation.topRight, imageSize: imageSize)
            return OCRLine(text: text, boundingBox: observation.boundingBox, confidence: candidate.confidence, direction: direction)
        }
        return OCRResult(lines: lines)
    }
}
