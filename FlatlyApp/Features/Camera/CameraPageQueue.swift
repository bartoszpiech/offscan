import CoreGraphics
import Foundation
import Observation
import FlatlyCore

/// The photos of one Offscan camera session, staged in the background while the user keeps
/// shooting.
///
/// Each photo goes through `ScanProcessor.stageImport` (full photo stored as the page's `source`,
/// document re-detected on the full-resolution still), one at a time so a burst of shots never
/// decodes several 12 MP images at once. Per photo only the page id, its detection and a small
/// (≤ 240 px) thumbnail are kept; the review reloads a downsampled copy when it shows the page.
/// Photos can be removed while shooting (Undo, the "Scanned Pages" sheet).
@MainActor
@Observable
final class CameraPageQueue {
    /// A captured, staged page.
    struct Page: Sendable {
        let id: UUID
        let detection: DetectedDocument
    }

    /// One photo taken in this session.
    struct Shot: Identifiable {
        /// A local token made in `add`, not the staged page's id.
        let id: UUID
        /// Perspective-corrected when a sheet was found; nil while staging or if staging failed.
        var thumbnail: CGImage?
        var isStaging = true
    }

    /// Photos taken so far (staged or still staging), in shutter order.
    private(set) var shots: [Shot] = []
    /// The photo added last. Set only by `add` (cleared by `discardAll`), never by a removal, so
    /// Undo always refers to the newest photo.
    private(set) var lastAddedID: UUID?

    var count: Int { shots.count }
    /// Thumbnail of the most recent staged page (the newest one may still be staging).
    var latestThumbnail: CGImage? { shots.last(where: { $0.thumbnail != nil })?.thumbnail }

    @ObservationIgnored private var tasks: [UUID: Task<Page?, Never>] = [:]
    /// The newest staging task: the next photo waits for it, even if its shot was removed.
    @ObservationIgnored private var lastTask: Task<Page?, Never>?

    /// Longest side of the thumbnails (52 pt next to the shutter, 56 pt rows in the sheet, @3x).
    nonisolated private static let thumbnailDimension = 240

    /// Queues a photo for staging after the previously taken ones.
    func add(_ photoData: Data, processor: ScanProcessor) {
        let shotID = UUID()
        let previous = lastTask
        shots.append(Shot(id: shotID))
        lastAddedID = shotID
        let task = Task.detached(priority: .userInitiated) { [weak self] () -> Page? in
            _ = await previous?.value
            // Only a thumbnail is made from the preview, so ask for a small one.
            guard let staged = try? await processor.stageImport(imageData: photoData, previewMaxDimension: Self.thumbnailDimension * 2) else {
                await self?.didStage(shotID: shotID, thumbnail: nil)
                return nil
            }
            var detection = staged.detection
            #if DEBUG
            // The DEBUG demo feed's desk photo: use the sheet's known corners, as its live outline
            // does. The simulator's detector can take a desk plank for the page.
            if DemoCameraFeed.isEnabled {
                detection = DetectedDocument(quad: DemoDeskPhoto.sheetQuad, confidence: 1, source: .segmentation)
            }
            #endif
            let thumbnail = Self.thumbnail(of: staged.image, quad: detection, focalLength35mm: staged.focalLength35mm)
            // `staged.image` (at most `thumbnailDimension * 2` px) is released when this task returns.
            await self?.didStage(shotID: shotID, thumbnail: thumbnail)
            return Page(id: staged.id, detection: detection)
        }
        tasks[shotID] = task
        lastTask = task
    }

    /// Removes one photo and deletes its staged files (once staging finished). Calling it twice,
    /// or for an unknown id, does nothing.
    func remove(_ shotID: UUID, processor: ScanProcessor) {
        guard let index = shots.firstIndex(where: { $0.id == shotID }), let task = tasks.removeValue(forKey: shotID) else { return }
        shots.remove(at: index)
        Task.detached {
            if let page = await task.value { await processor.discardStagedImport(pageID: page.id) }
        }
    }

    /// The staged page at position `index` of `shots` (waits while it is still staging); nil if
    /// staging failed.
    func page(at index: Int) async -> Page? {
        guard shots.indices.contains(index), let task = tasks[shots[index].id] else { return nil }
        return await task.value
    }

    /// Deletes every staged page's files (after staging in progress has finished).
    func discardAll(processor: ScanProcessor) {
        let pending = Array(tasks.values)
        tasks = [:]
        shots = []
        lastAddedID = nil
        Task.detached {
            for task in pending {
                if let page = await task.value { await processor.discardStagedImport(pageID: page.id) }
            }
        }
    }

    private func didStage(shotID: UUID, thumbnail: CGImage?) {
        // The shot may have been removed meanwhile.
        guard let index = shots.firstIndex(where: { $0.id == shotID }) else { return }
        shots[index].isStaging = false
        shots[index].thumbnail = thumbnail
    }

    /// Same proportions as the final page: the resized frame keeps its aspect, so the focal length
    /// still applies.
    nonisolated private static func thumbnail(of image: CGImage, quad detection: DetectedDocument, focalLength35mm: Double?) -> CGImage? {
        guard let small = try? ImageTransforms().resized(image, maxDimension: thumbnailDimension * 2) else { return nil }
        guard detection.source != .fullFrame,
              let page = try? PerspectiveCorrector().correct(small, to: detection.quad, focalLength35mm: focalLength35mm) else {
            return try? ImageTransforms().resized(small, maxDimension: thumbnailDimension)
        }
        return (try? ImageTransforms().resized(page, maxDimension: thumbnailDimension)) ?? page
    }
}
