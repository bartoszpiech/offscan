import SwiftUI
import FlatlyCore

/// A document in Recently Deleted: first-page thumbnail, title and the days left before it is
/// erased (`DeletionRetention.standard`). Tapping it asks whether to restore the document or delete
/// it now; the actions come from `RecentlyDeletedView`. The thumbnail is left out at accessibility
/// text sizes, where the text needs the width (like `SearchResultRow`).
struct RecentlyDeletedRow: View {
    let document: ScanDocument
    let onRestore: () -> Void
    let onDeleteNow: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var thumbnailWidth: CGFloat = 44
    @State private var isShowingActions = false

    private let thumbnailShape = RoundedRectangle(cornerRadius: 6, style: .continuous)

    var body: some View {
        let daysLeft = DeletionRetention.standard.daysRemaining(deletedAt: document.deletedAt ?? .now, now: .now)
        Button {
            isShowingActions = true
        } label: {
            row(daysLeft: daysLeft)
        }
        // Plain, like `SearchResultRow`: in a List the default style tints the label, which
        // turned the title and "N days left" into low-contrast accent text.
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: document.title))
        .accessibilityValue(daysLeftText(daysLeft))
        .accessibilityHint(Text("Shows Restore and Delete Now."))
        .accessibilityIdentifier("recentlyDeleted.row")
        .confirmationDialog(Text(verbatim: document.title), isPresented: $isShowingActions, titleVisibility: .visible) {
            Button("Restore") { onRestore() }
                .accessibilityIdentifier("recentlyDeleted.restore")
            Button("Delete Now", role: .destructive) { onDeleteNow() }
                .accessibilityIdentifier("recentlyDeleted.deleteNow")
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Restore the document to the library, or delete it permanently now.")
        }
    }

    private func row(daysLeft: Int) -> some View {
        HStack(alignment: .center, spacing: 12) {
            if !dynamicTypeSize.isAccessibilitySize {
                thumbnail
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: document.title)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 4 : 2)
                    .multilineTextAlignment(.leading)
                daysLeftText(daysLeft)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }

    private func daysLeftText(_ days: Int) -> Text {
        Text("\(days) days left", comment: "Recently Deleted: days until a deleted document is erased permanently")
    }

    private var thumbnail: some View {
        Color.clear
            .frame(width: thumbnailWidth, height: thumbnailWidth * 4 / 3)
            .overlay {
                if let firstPage = document.orderedPages.first {
                    PageImageView(page: firstPage)
                        .padding(2)
                } else {
                    Image(systemName: "doc")
                        .foregroundStyle(.tertiary)
                }
            }
            .background(Color(uiColor: .secondarySystemBackground))
            .clipShape(thumbnailShape)
            .overlay {
                thumbnailShape.strokeBorder(.separator, lineWidth: 1)
            }
            .accessibilityHidden(true)
    }
}
