import Foundation
import Testing

/// PencilKit's `PKDrawing.image(from:scale:)` hangs on headless CI virtual machines (no window
/// server). Tests that rasterise drawings are skipped when `FLATLY_SKIP_PENCILKIT` is set; the CI
/// workflow sets it, local runs don't.
enum PencilKitAvailability {
    static let isSkipped = ProcessInfo.processInfo.environment["FLATLY_SKIP_PENCILKIT"] != nil
    static let trait: ConditionTrait = .disabled(if: isSkipped, "PencilKit rendering hangs on headless CI")
}
