import SwiftUI
import FlatlyCore

/// One library search result as a list row: a small first-page thumbnail, the title, the matched
/// line with the hit highlighted (bold on an accent tint) and, for multi-page documents, the page
/// it was found on next to the date. Without a snippet (a title-only match) the row shows just
/// title and date. The thumbnail is left out at accessibility text sizes, where the text needs the
/// width.
///
/// Tapping it pushes the document (`NavigationLink(value: document.id)`); in the library's Select
/// mode (`selectionState` non-nil) it is a toggle with a leading numbered mark (selection order)
/// instead, like `DocumentCard`.
struct SearchResultRow: View {
    let document: ScanDocument
    /// The date to show (modified or created, depending on the library sort).
    let date: Date
    /// Where the query was found in the document's text; nil for a title-only match.
    let match: SearchMatch?
    /// nil = not selecting; otherwise whether this row is selected.
    var selectionState: Bool? = nil
    /// 1-based position in selection order; set only while the row is selected (see
    /// `DocumentCard.selectionNumber`).
    var selectionNumber: Int? = nil
    var onToggleSelection: () -> Void = {}

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var thumbnailWidth: CGFloat = 52

    private let thumbnailShape = RoundedRectangle(cornerRadius: 6, style: .continuous)

    var body: some View {
        let pageCount = document.pages.count
        let relativeDate = date.formatted(.relative(presentation: .named))
        Group {
            if let selected = selectionState {
                Button(action: onToggleSelection) {
                    row(pageCount: pageCount, relativeDate: relativeDate)
                }
                .accessibilityAddTraits(selected ? .isSelected : [])
            } else {
                NavigationLink(value: document.id) {
                    row(pageCount: pageCount, relativeDate: relativeDate)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(document.title))
        .accessibilityValue(accessibilityValue(relativeDate: relativeDate, pageCount: pageCount))
        .accessibilityIdentifier("library.searchResult")
    }

    private func row(pageCount: Int, relativeDate: String) -> some View {
        let isAccessibilitySize = dynamicTypeSize.isAccessibilitySize
        // The chevron is centred on the row like a folder row's; the rest is top-aligned.
        return HStack(alignment: .center, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                if let selected = selectionState {
                    selectionMark(selected)
                }
                if !isAccessibilitySize {
                    thumbnail
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(document.title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(isAccessibilitySize ? 4 : 2)
                        .multilineTextAlignment(.leading)
                    if let match {
                        Text(highlighted(match))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(isAccessibilitySize ? 4 : 2)
                            .multilineTextAlignment(.leading)
                    }
                    metaLine(pageCount: pageCount, relativeDate: relativeDate)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        // Polish relative dates ("w zeszłym tygodniu") get long at accessibility sizes.
                        .lineLimit(isAccessibilitySize ? 2 : 1)
                }
            }
            Spacer(minLength: 8)
            if selectionState == nil {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    /// "Page 2 · Yesterday" when the hit is in a multi-page document, else just the date.
    @ViewBuilder
    private func metaLine(pageCount: Int, relativeDate: String) -> some View {
        if let match, pageCount > 1 {
            HStack(spacing: 4) {
                Text("Page \(match.pageIndex + 1)")
                Text(verbatim: "·")
                    .accessibilityHidden(true)
                Text(relativeDate)
            }
        } else {
            Text(relativeDate)
        }
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

    @ViewBuilder
    private func selectionMark(_ selected: Bool) -> some View {
        Group {
            if selected {
                Image(systemName: DocumentCard.selectedSymbol(selectionNumber))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(Color.onAccent, .tint)
            } else {
                Image(systemName: "circle")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.title2)
        .accessibilityHidden(true)
    }

    /// Date and page count, where the query was found, then the selection position.
    private func accessibilityValue(relativeDate: String, pageCount: Int) -> Text {
        if match == nil && selectionNumber == nil {
            return Text("\(relativeDate), \(pageCount) pages", comment: "Accessibility value of a document card: relative date, page count")
        }
        var value = String(localized: "\(relativeDate), \(pageCount) pages", comment: "Accessibility value of a document card: relative date, page count")
        if let match {
            value += ". " + String(localized: "Found on page \(match.pageIndex + 1): \(match.snippet)", comment: "Accessibility: where a library search query was found in the document")
        }
        if let selectionNumber {
            value += ", " + String(localized: "number \(selectionNumber) in the selection", comment: "Accessibility value suffix of a selected library document: its position in the selection order, which Merge and Share follow")
        }
        return Text(verbatim: value)
    }

    /// The snippet with the hit in bold, primary colour, on a light accent tint (readable in light
    /// and dark mode, as the hit's text is primary).
    private func highlighted(_ match: SearchMatch) -> AttributedString {
        var text = AttributedString(match.snippet)
        guard let hit = match.highlight, hit.lowerBound >= 0, hit.upperBound <= text.characters.count else { return text }
        let lower = text.characters.index(text.startIndex, offsetBy: hit.lowerBound)
        let upper = text.characters.index(text.startIndex, offsetBy: hit.upperBound)
        text[lower..<upper].inlinePresentationIntent = .stronglyEmphasized
        text[lower..<upper].foregroundColor = Color.primary
        text[lower..<upper].backgroundColor = Color.accentColor.opacity(0.22)
        return text
    }
}
