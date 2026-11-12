#if DEBUG
import CoreGraphics
import CoreVideo
import Foundation
import Observation
import FlatlyCore

/// Stands in for the camera while the DEBUG demo library is active (`DemoLibrarySeeder.isEnabled`,
/// i.e. `FLATLY_UI_TESTING=1` + `FLATLY_DEMO_DATA=1`), so the simulator, which has no camera, shows
/// Offscan's scanner for screenshots. `CameraController` uses it instead of `CaptureSessionPipeline`
/// (which it then never creates) and `DocumentCameraScreen` shows `still` instead of the preview.
///
/// The still is a demo letter photographed on a desk (`DemoDeskPhoto`, 1500×2000, upright in
/// portrait). `DocumentDetector.detectLive` runs on it once (falling back to the sheet's known
/// corners should Vision find nothing), and ~9 frames a second go through a real
/// `QuadStabilityTracker`, so the normal outline and stability ring appear. Like an unsteady hand,
/// the steady period restarts before it completes, so auto-capture never fires on its own and
/// screenshots show the ring filling instead of racing a capture; the shutter delivers the still's
/// JPEG (`photoData`), which `CameraPageQueue` stages with the sheet's known corners
/// (`DemoDeskPhoto.sheetQuad`). Portrait only: the outline is computed for the upright portrait still.
@MainActor
@Observable
final class DemoCameraFeed {
    /// The demo still and what was found on it (made off the main actor).
    private struct Still: Sendable {
        let image: CGImage
        let jpeg: Data
        /// The sheet's outline (normalised, bottom-left origin, upright frame).
        let quad: Quadrilateral
    }

    nonisolated static var isEnabled: Bool { DemoLibrarySeeder.isEnabled }

    /// The landscape "sensor" whose upright portrait frame is the still.
    static let sensorSize = CGSize(width: DemoDeskPhoto.size.height, height: DemoDeskPhoto.size.width)
    /// About 9 analysed frames a second, like the camera pipeline.
    private static let frameInterval: Duration = .milliseconds(110)
    /// Steady time after which the tracker starts over (auto-capture needs 0.9 s).
    private static let steadyRestart: TimeInterval = 0.8

    /// Shown in place of the camera preview; nil until `prepare()` has made it.
    private(set) var still: CGImage?

    /// Analysed frames, newest only (as `CaptureSessionPipeline.updates`).
    let updates: AsyncStream<LiveDetectionUpdate>
    private let continuation: AsyncStream<LiveDetectionUpdate>.Continuation

    @ObservationIgnored private var prepared: Still?
    @ObservationIgnored private var frameTask: Task<Void, Never>?
    @ObservationIgnored private var tracker = QuadStabilityTracker()
    @ObservationIgnored private var orientation: CameraOrientation = .portrait

    init() {
        (updates, continuation) = AsyncStream.makeStream(of: LiveDetectionUpdate.self, bufferingPolicy: .bufferingNewest(1))
    }

    deinit {
        // Ends the controller's `for await` over `updates`. The frame loop holds the feed weakly
        // and ends by itself.
        continuation.finish()
    }

    /// The still's JPEG, delivered by the shutter like a camera photo.
    var photoData: Data? { prepared?.jpeg }

    /// Makes the still and detects the sheet on it (once). Returns the sensor size, or nil when
    /// the still couldn't be drawn.
    func prepare() async -> CGSize? {
        if prepared == nil {
            prepared = await Task.detached(priority: .userInitiated) { DemoCameraFeed.makeStill() }.value
            still = prepared?.image
        }
        return prepared == nil ? nil : Self.sensorSize
    }

    /// Starts publishing frames (after `prepare()`); a no-op while running.
    func startFrames() {
        guard frameTask == nil, let quad = prepared?.quad else { return }
        tracker.reset()
        let interval = Self.frameInterval
        frameTask = Task { [weak self] in
            while !Task.isCancelled {
                // Not held across the sleep: a released feed ends the loop.
                guard self?.publishFrame(quad: quad) != nil else { return }
                try? await Task.sleep(for: interval)
            }
        }
    }

    func stop() {
        frameTask?.cancel()
        frameTask = nil
        tracker.reset()
    }

    /// Forgets the tracked sheet (after a capture, on resuming auto-capture).
    func resetTracking() {
        tracker.reset()
    }

    func setOrientation(_ orientation: CameraOrientation) {
        guard orientation != self.orientation else { return }
        self.orientation = orientation
        tracker.reset()
    }

    private func publishFrame(quad: Quadrilateral) {
        let now = Date()
        if let since = tracker.steadySince, now.timeIntervalSince(since) >= Self.steadyRestart {
            // The hand moved a little: the outline stays, the steady period starts over.
            tracker.reset()
        }
        tracker.update(with: quad, at: now)
        continuation.yield(LiveDetectionUpdate(
            quad: tracker.smoothedQuad,
            progress: tracker.progress(at: now),
            isStable: tracker.isStable(at: now),
            isTooSmall: tracker.isSheetTooSmall,
            orientation: orientation,
            uprightSize: orientation.uprightSize(forSensorSize: Self.sensorSize)
        ))
    }

    // MARK: Off the main actor

    /// The demo letter on a desk, its JPEG and the sheet found on it by live detection.
    nonisolated private static func makeStill() -> Still? {
        let language = DemoLanguage.current
        let letter = DemoLibraryContent.buildingLetter(language, now: .now)
        guard let page = letter.pages.first?.render(),
              let photo = DemoDeskPhoto.compose(page: page.image),
              let jpeg = try? ImageCodec().jpegData(photo.image, quality: 0.9) else { return nil }
        var quad = photo.quad
        if let buffer = pixelBuffer(from: photo.image),
           let detected = try? DocumentDetector().detectLive(in: buffer, orientation: .up),
           detected.quad.isConvex {
            quad = detected.quad
        }
        return Still(image: photo.image, jpeg: jpeg, quad: quad)
    }

    /// A BGRA copy of `image` for Vision, like a camera frame.
    nonisolated private static func pixelBuffer(from image: CGImage) -> CVPixelBuffer? {
        let attributes: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
        ]
        var created: CVPixelBuffer?
        guard CVPixelBufferCreate(kCFAllocatorDefault, image.width, image.height, kCVPixelFormatType_32BGRA,
                                  attributes as CFDictionary, &created) == kCVReturnSuccess,
              let buffer = created else { return nil }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: CVPixelBufferGetBaseAddress(buffer),
                width: image.width,
                height: image.height,
                bitsPerComponent: 8,
                bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
              ) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return buffer
    }
}
#endif
