import SwiftUI

/// Edit-mode list of pages: drag handles to reorder, swipe or tap the minus button to delete.
struct PageReorderList: View {
    let pages: [ScanPage]
    let onMove: (IndexSet, Int) -> Void
    let onDelete: ([ScanPage]) -> Void

    @ScaledMetric(relativeTo: .body) private var thumbnailHeight: CGFloat = 72

    var body: some View {
        List {
            ForEach(Array(pages.enumerated()), id: \.element.id) { offset, page in
                HStack(spacing: 16) {
                    PageImageView(page: page)
                        .frame(width: thumbnailHeight * 0.75, height: thumbnailHeight)
                        .accessibilityHidden(true)
                    Text("Page \(offset + 1)")
                        .font(.body)
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("document.pageRow.\(offset + 1)")
            }
            .onMove(perform: onMove)
            .onDelete { offsets in
                onDelete(offsets.map { pages[$0] })
            }
        }
        .environment(\.editMode, .constant(.active))
        .accessibilityIdentifier("document.pageList")
    }
}
