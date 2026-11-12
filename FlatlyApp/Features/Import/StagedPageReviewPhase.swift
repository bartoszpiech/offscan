import Foundation

/// State machine of `StagedPageReview`.
enum StagedPageReviewPhase {
    /// Loading (or waiting for) page `index` (0-based) so its corners can be shown.
    case staging(index: Int)
    /// The user is adjusting the corners of page `index`.
    case adjusting(index: Int, staged: ScanProcessor.StagedImport)
    /// Waiting for the perspective-corrected pages and inserting them into the document.
    case saving
}
