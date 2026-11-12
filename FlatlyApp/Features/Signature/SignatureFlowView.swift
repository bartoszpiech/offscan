import SwiftUI
import FlatlyCore

/// Sheet content for signing a page: draw (or reuse) a signature, then place it on the page.
/// `onPlace` receives the placement; the sheet dismisses itself afterwards.
struct SignatureFlowView: View {
    let pageID: UUID
    /// The page's current recipe; the placement preview renders it without any existing signature.
    let recipe: PageRenderRecipe
    let onPlace: (SignaturePlacement) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft: Draft?

    private struct Draft: Hashable {
        let id = UUID()
        let drawingData: Data
    }

    var body: some View {
        NavigationStack {
            SignatureCanvasView { data in
                draft = Draft(drawingData: data)
            } onCancel: {
                dismiss()
            }
            .navigationDestination(item: $draft) { draft in
                SignaturePlacementView(pageID: pageID, recipe: recipe, drawingData: draft.drawingData) { placement in
                    onPlace(placement)
                    dismiss()
                }
            }
        }
        .interactiveDismissDisabled()
    }
}
