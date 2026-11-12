import Foundation

/// Navigation value for opening the page editor from a document: which page, and whether to start
/// straight in the edge adjustment ("Adjust Edges" from a page card's context menu).
struct EditorRoute: Hashable {
    let pageID: UUID
    let adjustEdges: Bool
}
