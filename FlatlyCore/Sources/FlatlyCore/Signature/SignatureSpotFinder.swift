import Foundation
import CoreGraphics

/// Picks where a new signature should first appear on a page so that it doesn't cover recognised
/// text (e.g. a contract clause), staying as close as possible to the preferred spot.
public struct SignatureSpotFinder: Sendable {
    public init() {}

    /// Returns a frame the same size as `preferred` that stays at least `margin` away from every
    /// OCR line box, picking the one whose centre is closest to `preferred`'s centre (ties: lower
    /// on the page, then further right). Returns `preferred` unchanged if it is already clear, if
    /// `lines` is empty, or if no clear position exists.
    ///
    /// `preferred` and the result are normalised with a **top-left** origin (like
    /// `SignaturePlacement.frame`); OCR line boxes are Vision's bottom-left normalised boxes on the
    /// same (processed) page image.
    public func frame(near preferred: CGRect, avoiding lines: [OCRLine], margin: CGFloat = 0.01) -> CGRect {
        let boxes = lines.compactMap { line -> CGRect? in
            let box = line.boundingBox.standardized
            guard box.width > 0, box.height > 0 else { return nil }
            return CGRect(x: box.minX, y: 1 - box.maxY, width: box.width, height: box.height)
        }
        func isClear(_ rect: CGRect) -> Bool {
            let padded = rect.insetBy(dx: -margin, dy: -margin)
            return !boxes.contains { $0.intersects(padded) }
        }
        guard !boxes.isEmpty, !isClear(preferred) else { return preferred }
        let width = preferred.width, height = preferred.height
        guard width <= 1, height <= 1 else { return preferred }

        /// 0.01 steps across the page (computed from the index, no accumulating error), clamped so
        /// the frame stays inside, plus the preferred origin itself.
        func origins(size: CGFloat, preferred origin: CGFloat) -> [CGFloat] {
            var values = Set((0...100).map { min(CGFloat($0) * 0.01, 1 - size) })
            values.insert(origin)
            return values.sorted()
        }
        var best: CGRect?
        var bestScore = CGFloat.infinity
        for y in origins(size: height, preferred: preferred.minY) {
            for x in origins(size: width, preferred: preferred.minX) {
                let candidate = CGRect(x: x, y: y, width: width, height: height)
                guard isClear(candidate) else { continue }
                let score = hypot(candidate.midX - preferred.midX, candidate.midY - preferred.midY)
                if let current = best, abs(score - bestScore) < 1e-9 {
                    // Tie: lower on the page, then further right (signatures go bottom right).
                    if candidate.minY > current.minY || (candidate.minY == current.minY && candidate.minX > current.minX) {
                        best = candidate
                    }
                } else if score < bestScore {
                    best = candidate
                    bestScore = score
                }
            }
        }
        return best ?? preferred
    }
}
