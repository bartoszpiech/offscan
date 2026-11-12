import SwiftUI
import CoreGraphics
import FlatlyCore

/// Row of four equal tiles, one per scan filter, spanning the bar's width (at most 440 pt, leading
/// aligned like the caption above it). Each tile has a live preview of the page rendered in the
/// background by `ScanProcessor.preview`; thumbnails show the top of the page filling the tile,
/// so the filters' treatment of text and paper is visible. Names wrap to two lines instead of
/// shrinking. Previews reload when the page, its crop, rotation or edges change, never after a
/// filter or signature change (they don't affect them). Like the tool bar beneath it, the row
/// stops growing at `.xxxLarge` text size; at accessibility sizes a long-press on a filter or on
/// Apply to All shows it in the Large Content Viewer.
struct FilterPickerBar: View {
    let pageID: UUID
    /// The page's current recipe; previews keep its crop and rotation.
    let recipe: PageRenderRecipe
    /// Quad that produced the page's stored `original` (nil for camera scans whose edges were never
    /// adjusted). Previews are rendered from `original` plus crop and rotation only, so they reload
    /// when this, the crop or the rotation changes, but not after a filter or signature change.
    let quad: Quadrilateral?
    let onSelect: (ScanFilter) -> Void
    /// Applies the current filter to every page of the document; nil hides the button (single
    /// page, or every page already uses this filter).
    var onApplyToAll: (() -> Void)? = nil

    @Environment(AppServices.self) private var services
    @State private var previews: [ScanFilter: CGImage] = [:]
    /// The page `previews` belong to (the editor pages through the document with the same bar).
    @State private var previewsPageID: UUID?

    private struct PreviewKey: Hashable {
        let pageID: UUID
        let recipe: PageRenderRecipe
        let quad: Quadrilateral?
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            selectionCaption
                .padding(.horizontal)
                .padding(.top, 8)
            // Four equal columns: they fill an iPhone's width in portrait; in landscape and on iPad
            // the row stops at 440 pt.
            HStack(alignment: .top, spacing: 8) {
                ForEach(ScanFilter.allCases, id: \.self) { filter in
                    filterButton(filter)
                }
            }
            .frame(maxWidth: 440)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .background(.bar)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .task(id: PreviewKey(pageID: pageID, recipe: previewBase, quad: quad)) {
            await loadPreviews()
        }
    }

    private func filterButton(_ filter: ScanFilter) -> some View {
        let isSelected = recipe.filter == filter
        return Button {
            onSelect(filter)
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(.secondarySystemBackground))
                    if previews[filter] == nil {
                        ProgressView()
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 84)
                // The page fills the tile's width, anchored at its top (an overlay keeps the tile's
                // size while the taller image overflows downwards and is clipped).
                .overlay(alignment: .top) {
                    if let image = previews[filter] {
                        Image(decorative: image, scale: 1)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .allowsHitTesting(false)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                // After the clip, so the offset checkmark isn't cut off.
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(isSelected ? Color.accentColor : Color(.separator), lineWidth: isSelected ? 3 : 1)
                }
                .overlay(alignment: .topTrailing) {
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.subheadline)
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(Color.onAccent, Color.accentColor)
                            .offset(x: 6, y: -6)
                            .accessibilityHidden(true)
                    }
                }
                // Wraps to a second line instead of shrinking below its neighbours.
                Text(filter.displayName)
                    .font(.caption)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity)
            // The whole column is tappable, including the space beside a short caption.
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // The label is a thumbnail plus a capped caption: show the filter name in the HUD.
        .accessibilityShowsLargeContentViewer {
            Label(filter.displayName, systemImage: "camera.filters")
        }
        .accessibilityLabel(Text(filter.displayName))
        .accessibilityHint(Text(filter.summary))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityIdentifier("editor.filter.\(filter.rawValue)")
    }

    /// "Color — White paper, true colors" for the page's current filter, with "Apply to All" next to it
    /// (or below it, when both don't fit on one line) when `onApplyToAll` is set.
    @ViewBuilder
    private var selectionCaption: some View {
        if onApplyToAll == nil {
            captionText
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    captionText
                    Spacer(minLength: 8)
                    applyToAllButton
                }
                VStack(alignment: .leading, spacing: 6) {
                    captionText
                    applyToAllButton
                }
            }
        }
    }

    private var applyToAllButton: some View {
        Button("Apply to All") { onApplyToAll?() }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .font(.footnote)
            .accessibilityShowsLargeContentViewer()
            .accessibilityLabel(Text("Apply this filter to all pages"))
            .accessibilityIdentifier("editor.applyFilterToAllButton")
    }

    private var captionText: some View {
        // Wraps to a second line instead of shrinking or truncating a long summary; the name and
        // dash stay level with its first line.
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(recipe.filter.displayName)
                .fontWeight(.semibold)
            Text(verbatim: "—")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(recipe.filter.summary)
                .foregroundStyle(.secondary)
        }
        .font(.footnote)
        .lineLimit(2)
        .minimumScaleFactor(0.8)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("editor.filterCaption")
    }

    /// Recipe used for previews: same geometry, no signature, filter replaced per thumbnail.
    private var previewBase: PageRenderRecipe {
        var r = recipe
        r.filter = .original
        r.signature = nil
        return r
    }

    private func loadPreviews() async {
        // Another page: its thumbnails must not stand in for this one's. Same page (crop, rotation
        // or edges changed): keep the old thumbnails until each new one replaces it, so the strip
        // never blanks to spinners.
        if previewsPageID != pageID {
            previews = [:]
            previewsPageID = pageID
        }
        let processor = services.processor
        let id = pageID
        let base = previewBase
        for filter in ScanFilter.allCases {
            if Task.isCancelled { return }
            var r = base
            r.filter = filter
            // 400 px: a tile is about 90-100 pt wide, so the top-anchored fill isn't upscaled at 3x.
            if let image = try? await processor.preview(pageID: id, recipe: r, maxDimension: 400), !Task.isCancelled {
                previews[filter] = image
            }
        }
    }
}
