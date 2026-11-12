import SwiftUI

/// The layout of a row in the library's Folders section (`FolderRow`, `RecentlyDeletedFolderRow`):
/// icon, title, document count and a chevron. The icon column has a fixed minimum width, so the
/// titles line up whatever the symbol's width (the section's dividers start at 56 pt).
struct LibraryFolderRowLabel: View {
    let systemImage: String
    let title: Text
    let count: Int

    @ScaledMetric(relativeTo: .title2) private var iconWidth: CGFloat = 28

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(minWidth: iconWidth)
                .accessibilityHidden(true)
            title
                .font(.body)
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 8)
            Text(count, format: .number)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}
