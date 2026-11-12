import SwiftUI

/// Adaptive grid of page cards, below an optional header that scrolls with the pages. Tap opens a
/// page; the context menu (long press) offers "Edit Page", "Adjust Edges" and "Delete Page". The
/// grid ends with an "Add Pages" tile that opens the camera / Photos / Files menu
/// (`addPagesMenuItems`).
struct PageGridView<Header: View, AddPagesMenuItems: View>: View {
    let pages: [ScanPage]
    let onSelect: (ScanPage) -> Void
    let onAdjustEdges: (ScanPage) -> Void
    let onDelete: (ScanPage) -> Void
    private let header: Header
    private let addPagesMenuItems: () -> AddPagesMenuItems

    @ScaledMetric(relativeTo: .body) private var minimumCellWidth: CGFloat = 140

    init(
        pages: [ScanPage],
        onSelect: @escaping (ScanPage) -> Void,
        onAdjustEdges: @escaping (ScanPage) -> Void,
        onDelete: @escaping (ScanPage) -> Void,
        @ViewBuilder header: () -> Header,
        @ViewBuilder addPagesMenuItems: @escaping () -> AddPagesMenuItems
    ) {
        self.pages = pages
        self.onSelect = onSelect
        self.onAdjustEdges = onAdjustEdges
        self.onDelete = onDelete
        self.header = header()
        self.addPagesMenuItems = addPagesMenuItems
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                header
                LazyVGrid(columns: [GridItem(.adaptive(minimum: minimumCellWidth), spacing: 16)], spacing: 16) {
                    ForEach(Array(pages.enumerated()), id: \.element.id) { offset, page in
                        Button {
                            onSelect(page)
                        } label: {
                            PageCardView(page: page, number: offset + 1)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint(Text("Opens the page editor"))
                        .accessibilityIdentifier("document.pageCard.\(offset + 1)")
                        .contextMenu {
                            Button {
                                onSelect(page)
                            } label: {
                                Label("Edit Page", systemImage: "slider.horizontal.3")
                            }
                            Button {
                                onAdjustEdges(page)
                            } label: {
                                Label("Adjust Edges", systemImage: "perspective")
                            }
                            .accessibilityIdentifier("document.pageCard.adjustEdges")
                            Divider()
                            Button(role: .destructive) {
                                onDelete(page)
                            } label: {
                                Label("Delete Page", systemImage: "trash")
                            }
                        }
                    }
                    addPagesTile
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .accessibilityIdentifier("document.pageGrid")
    }

    /// Last cell, the size and shape of a page card (10 pt corners, 3:4).
    private var addPagesTile: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        return Menu {
            addPagesMenuItems()
        } label: {
            shape
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                .foregroundStyle(.tertiary)
                .aspectRatio(3.0 / 4.0, contentMode: .fit)
                .overlay {
                    VStack(spacing: 6) {
                        Image(systemName: "plus")
                            .font(.title2)
                            .accessibilityHidden(true)
                        Text("Add Pages")
                            .font(.subheadline)
                            .multilineTextAlignment(.center)
                    }
                    .padding(8)
                    .foregroundStyle(.tint)
                }
                // The whole tile is tappable, not just the dashed outline.
                .contentShape(shape)
        }
        .accessibilityLabel(Text("Add Pages"))
        .accessibilityIdentifier("document.addPagesTile")
    }
}
