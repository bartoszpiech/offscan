import SwiftUI

/// First row of the export sheet: the document's first page, title and page count, so the user
/// sees what is being exported.
struct ExportDocumentHeader: View {
    let document: ScanDocument

    @ScaledMetric(relativeTo: .headline) private var thumbnailWidth: CGFloat = 56

    var body: some View {
        HStack(spacing: 14) {
            thumbnail
            VStack(alignment: .leading, spacing: 4) {
                Text(document.title)
                    .font(.headline)
                    .lineLimit(2)
                Text("\(document.pages.count) pages")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("export.header")
    }

    private var thumbnail: some View {
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        return Color.clear
            .frame(width: thumbnailWidth, height: thumbnailWidth * 4 / 3)
            .overlay {
                if let first = document.orderedPages.first {
                    PageImageView(page: first)
                        .padding(3)
                } else {
                    Image(systemName: "doc")
                        .font(.title2)
                        .foregroundStyle(.tertiary)
                }
            }
            .background(Color(uiColor: .secondarySystemBackground))
            .clipShape(shape)
            .overlay(shape.strokeBorder(.separator, lineWidth: 0.5))
            .accessibilityHidden(true)
    }
}
