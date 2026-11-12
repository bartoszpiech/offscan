import SwiftUI
import FlatlyCore

/// A document tile in the library grid: first-page thumbnail, title, date and page count, and
/// optionally the folder it is in (the Recent strip). Search results are list rows instead
/// (`SearchResultRow`).
/// Tapping it pushes the document (`NavigationLink(value: document.id)`); in the library's Select
/// mode (`selectionState` non-nil) it is a toggle with a numbered mark (selection order) instead.
struct DocumentCard: View {
    let document: ScanDocument
    /// The date to show (modified or created, depending on the library sort).
    let date: Date
    /// Shown under the date (the Recent strip shows where a filed document lives). nil = no folder line.
    var folderName: String? = nil
    /// Accessibility identifier; the Recent strip uses its own so UI tests that look for
    /// `library.documentCard` keep matching the grid.
    var accessibilityID: String = "library.documentCard"
    /// Title lines added on top of the size-based limit. The narrow Recent cards pass 1, so typical
    /// titles ("Invoice INV-2026-0412 – Lumen Print") show in full instead of being cut after two
    /// lines.
    var extraTitleLines: Int = 0
    /// nil = not selecting; otherwise whether this card is selected.
    var selectionState: Bool? = nil
    /// 1-based position in selection order (the order Merge and Share follow); set only while the
    /// card is selected. The mark shows the number (a checkmark beyond 50).
    var selectionNumber: Int? = nil
    var onToggleSelection: () -> Void = {}

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)

    /// 2 title lines, 3 from xxxLarge and 4 at accessibility sizes (so the timestamp in default
    /// titles, "Scan 2026-11-12 10.30", stays visible), plus `extraTitleLines`. No reserved space:
    /// a one-line title is followed directly by the date (the grid aligns cards to the top).
    private var titleLineLimit: Int {
        let base: Int
        if dynamicTypeSize.isAccessibilitySize {
            base = 4
        } else {
            base = dynamicTypeSize >= .xxxLarge ? 3 : 2
        }
        return base + extraTitleLines
    }

    var body: some View {
        let pageCount = document.pages.count
        let relativeDate = date.formatted(.relative(presentation: .named))
        Group {
            if let selected = selectionState {
                Button(action: onToggleSelection) {
                    card(pageCount: pageCount, relativeDate: relativeDate)
                }
                .accessibilityAddTraits(selected ? .isSelected : [])
            } else {
                NavigationLink(value: document.id) {
                    card(pageCount: pageCount, relativeDate: relativeDate)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(document.title))
        .accessibilityValue(accessibilityValue(relativeDate: relativeDate, pageCount: pageCount))
        .accessibilityIdentifier(accessibilityID)
    }

    private func card(pageCount: Int, relativeDate: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            thumbnail(pageCount: pageCount)
            Text(document.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(titleLineLimit)
                .multilineTextAlignment(.leading)
            Text(relativeDate)
                .font(.caption)
                .foregroundStyle(.secondary)
                // Polish relative dates ("w zeszłym tygodniu") get long at accessibility sizes.
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
            if let folderName {
                Label {
                    Text(verbatim: folderName)
                } icon: {
                    Image(systemName: "folder")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    /// Date and page count, then the folder (Recent cards) or the selection position (selected
    /// cards). Both can't apply at once: Recent is hidden while selecting.
    private func accessibilityValue(relativeDate: String, pageCount: Int) -> Text {
        var suffixes: [String] = []
        if let folderName {
            suffixes.append(String(localized: "in folder \(folderName)", comment: "Accessibility value suffix of a Recent card: the folder the document is in"))
        }
        if let selectionNumber {
            suffixes.append(String(localized: "number \(selectionNumber) in the selection", comment: "Accessibility value suffix of a selected library document: its position in the selection order, which Merge and Share follow"))
        }
        guard !suffixes.isEmpty else {
            return Text("\(relativeDate), \(pageCount) pages", comment: "Accessibility value of a document card: relative date, page count")
        }
        let base = String(localized: "\(relativeDate), \(pageCount) pages", comment: "Accessibility value of a document card: relative date, page count")
        return Text(verbatim: ([base] + suffixes).joined(separator: ", "))
    }

    private func thumbnail(pageCount: Int) -> some View {
        Color.clear
            .aspectRatio(3.0 / 4.0, contentMode: .fit)
            .overlay {
                if let firstPage = document.orderedPages.first {
                    PageImageView(page: firstPage)
                        .padding(4)
                } else {
                    Image(systemName: "doc")
                        .font(.largeTitle)
                        .foregroundStyle(.tertiary)
                }
            }
            .background(Color(uiColor: .secondarySystemBackground))
            .clipShape(shape)
            .overlay {
                if selectionState == true {
                    shape.strokeBorder(.tint, lineWidth: 3)
                } else {
                    shape.strokeBorder(.separator, lineWidth: 1)
                }
            }
            .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 2)
            .overlay(alignment: .bottomTrailing) {
                if pageCount > 1 {
                    pageBadge(pageCount)
                        .padding(6)
                }
            }
            .overlay(alignment: .topTrailing) {
                if let selected = selectionState {
                    selectionMark(selected)
                        .padding(6)
                }
            }
    }

    @ViewBuilder
    private func selectionMark(_ selected: Bool) -> some View {
        Group {
            if selected {
                Image(systemName: Self.selectedSymbol(selectionNumber))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(Color.onAccent, .tint)
            } else {
                Image(systemName: "circle")
                    .foregroundStyle(.secondary)
                    .background(.regularMaterial, in: Circle())
            }
        }
        .font(.title2)
        .accessibilityHidden(true)
    }

    /// The mark of a selected card or search row: its position in selection order as a filled
    /// numbered circle (SF Symbols has 1–50), or a checkmark without a number or beyond 50.
    static func selectedSymbol(_ number: Int?) -> String {
        if let number, (1...50).contains(number) { return "\(number).circle.fill" }
        return "checkmark.circle.fill"
    }

    private func pageBadge(_ count: Int) -> some View {
        HStack(spacing: 3) {
            Image(systemName: "doc.on.doc")
            Text(count, format: .number)
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.primary)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(.regularMaterial, in: Capsule())
    }
}
