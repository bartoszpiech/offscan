import Foundation

/// State machine of `ImportFlowView`.
enum ImportPhase {
    /// Photos picker / file importer is showing.
    case picking
    /// Picked files are being opened and inspected (a multi-page TIFF is split into pages).
    case opening
    /// The picked items are being staged and reviewed one by one (`StagedPageReview`).
    case reviewing
    /// Finished; only the final alert (if any) remains.
    case done

    var isPicking: Bool {
        if case .picking = self { return true }
        return false
    }

    /// Swipe-down may dismiss the flow: nothing has been staged yet.
    var allowsInteractiveDismiss: Bool {
        switch self {
        case .picking, .opening: true
        case .reviewing, .done: false
        }
    }
}
