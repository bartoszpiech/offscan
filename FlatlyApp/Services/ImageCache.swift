import Foundation
import CoreGraphics
import Observation
import FlatlyCore

/// Main-actor cache of decoded page images (thumbnails and full pages) keyed by page id, kind and
/// the `maxDimension` they were decoded at (nil = full size), so a downsampled copy is never
/// handed to a caller that asked for another size.
/// Call `invalidate(pageID:)` after a page is re-rendered so views reload.
///
/// Thumbnails and full pages have separate budgets, so editor pages never evict library and grid
/// thumbnails.
@MainActor
@Observable
final class ImageCache {
    private let thumbnails = NSCache<NSString, CGImageBox>()
    private let pages = NSCache<NSString, CGImageBox>()
    /// Every key stored per page, so `invalidate(pageID:)` can remove all sizes.
    @ObservationIgnored private var keys: [UUID: Set<String>] = [:]
    /// Bumped on invalidation so observing views re-run their `.task(id:)`.
    private(set) var generation: [UUID: Int] = [:]

    /// About 110 thumbnails and 9 editor pages with the defaults.
    init(thumbnailLimitBytes: Int = 50 * 1024 * 1024, pageLimitBytes: Int = 100 * 1024 * 1024) {
        thumbnails.totalCostLimit = thumbnailLimitBytes
        pages.totalCostLimit = pageLimitBytes
    }

    func image(pageID: UUID, kind: PageImageStore.Kind, maxDimension: Int?) -> CGImage? {
        storage(for: kind).object(forKey: key(pageID, kind, maxDimension) as NSString)?.image
    }

    func store(_ image: CGImage, pageID: UUID, kind: PageImageStore.Kind, maxDimension: Int?) {
        let key = key(pageID, kind, maxDimension)
        keys[pageID, default: []].insert(key)
        storage(for: kind).setObject(CGImageBox(image), forKey: key as NSString, cost: image.bytesPerRow * image.height)
    }

    func invalidate(pageID: UUID) {
        // Keys don't record their cache; removing a missing key is a no-op.
        for key in keys.removeValue(forKey: pageID) ?? [] {
            thumbnails.removeObject(forKey: key as NSString)
            pages.removeObject(forKey: key as NSString)
        }
        generation[pageID, default: 0] += 1
    }

    func generation(for pageID: UUID) -> Int { generation[pageID] ?? 0 }

    private func storage(for kind: PageImageStore.Kind) -> NSCache<NSString, CGImageBox> {
        kind == .thumb ? thumbnails : pages
    }

    private func key(_ id: UUID, _ kind: PageImageStore.Kind, _ maxDimension: Int?) -> String {
        "\(id.uuidString)/\(kind.rawValue)/\(maxDimension.map(String.init) ?? "full")"
    }
}

final class CGImageBox: NSObject, Sendable {
    let image: CGImage
    init(_ image: CGImage) { self.image = image }
}
