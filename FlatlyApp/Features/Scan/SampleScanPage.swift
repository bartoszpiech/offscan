#if DEBUG
import UIKit

/// A synthetic "scanned" page (white sheet with a few lines of text) used by UI tests on the
/// simulator, where the VisionKit camera is unavailable. Enabled with `FLATLY_UI_TESTING=1`.
enum SampleScanPage {
    static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["FLATLY_UI_TESTING"] == "1"
    }

    @MainActor
    static func make() -> CGImage? {
        let size = CGSize(width: 1240, height: 1754)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 64, weight: .semibold),
                .foregroundColor: UIColor.black,
            ]
            let lines = ["Offscan sample page", "Invoice 2026-001", "Total 123.45 PLN"]
            for (i, line) in lines.enumerated() {
                (line as NSString).draw(at: CGPoint(x: 120, y: 200 + CGFloat(i) * 120), withAttributes: attributes)
            }
        }
        return image.cgImage
    }
}
#endif
