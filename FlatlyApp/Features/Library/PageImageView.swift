import SwiftUI
import CoreGraphics
import FlatlyCore

/// Asynchronously loads and displays one of a page's stored images (thumbnail by default),
/// aspect-fit, with a placeholder while loading. Reloads automatically when the page is
/// re-rendered (`ImageCache.invalidate(pageID:)`). When only the kind or size changes (the editor
/// swapping a thumbnail for the full page), the current image stays up until the new one is
/// decoded, so there is no spinner flash.
struct PageImageView: View {
    let page: ScanPage
    var kind: PageImageStore.Kind = .thumb
    /// Optional downsampling for full-size kinds.
    var maxDimension: Int? = nil

    @Environment(AppServices.self) private var services
    @Environment(ImageCache.self) private var cache
    @State private var image: CGImage?
    @State private var failed = false
    /// "<page id>-<generation>" of the shown image. While only kind/maxDimension change the current
    /// image stays up until the new one is decoded.
    @State private var shownVersion: String?

    var body: some View {
        let generation = cache.generation(for: page.id)
        ZStack {
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Rectangle()
                    .fill(.quaternary)
                    .overlay {
                        if failed {
                            Image(systemName: "doc.questionmark")
                                .font(.title)
                                .foregroundStyle(.secondary)
                                .accessibilityLabel("Image unavailable")
                        } else {
                            ProgressView()
                        }
                    }
                    .aspectRatio(aspectRatio, contentMode: .fit)
            }
        }
        .task(id: "\(page.id)-\(kind.rawValue)-\(maxDimension ?? 0)-\(generation)") {
            let version = "\(page.id)-\(generation)"
            if let cached = cache.image(pageID: page.id, kind: kind, maxDimension: maxDimension) {
                image = cached
                shownVersion = version
                failed = false
                return
            }
            // A new page or a re-render blanks to the spinner; a size change keeps the old image.
            if shownVersion != version {
                image = nil
                shownVersion = nil
            }
            failed = false
            let id = page.id
            let kind = kind
            let maxDimension = maxDimension
            let processor = services.processor
            let loaded = try? await processor.loadImage(pageID: id, kind: kind, maxDimension: maxDimension)
            if let loaded, !Task.isCancelled {
                cache.store(loaded, pageID: id, kind: kind, maxDimension: maxDimension)
                image = loaded
                shownVersion = version
            } else if !Task.isCancelled {
                // Never leave a stale thumbnail up with no sign that the full page failed.
                image = nil
                shownVersion = nil
                failed = true
            }
        }
    }

    private var aspectRatio: CGFloat {
        guard page.widthPx > 0, page.heightPx > 0 else { return 210.0 / 297.0 }
        return CGFloat(page.widthPx) / CGFloat(page.heightPx)
    }
}
