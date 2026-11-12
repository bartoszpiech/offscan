import AVFoundation
import Observation
import FlatlyCore

/// Main-actor face of Offscan's camera: authorisation, session start/stop, the live document
/// outline, auto-capture and the shutter. AVFoundation work happens in `CaptureSessionPipeline`
/// on its own queues; this class only receives `LiveDetectionUpdate`s and photo data.
///
/// Auto-capture fires when the tracker reports a steady sheet. Afterwards the tracker is reset and
/// auto-capture waits for a 1.2 s cooldown **and** for the next page: the outline must move away
/// or disappear for a moment first, so a sheet left under the camera isn't captured over and over.
///
/// DEBUG builds with the demo library (`FLATLY_DEMO_DATA=1`) run on `DemoCameraFeed` instead: a
/// desk photo with live detection, no camera permission, and the pipeline is never created.
@MainActor
@Observable
final class CameraController {
    enum Status: Equatable {
        case idle, starting, running, denied, failed
    }

    private(set) var status: Status = .idle
    /// The latest analysed frame (any orientation; see `liveDetection`).
    private(set) var detection: LiveDetectionUpdate?
    /// Landscape pixel size of the camera's frames (e.g. 4032×3024).
    private(set) var sensorSize = CGSize(width: 4, height: 3)
    private(set) var orientation: CameraOrientation = .portrait
    /// Incremented for every photo taken (drives the flash animation and haptic).
    private(set) var captureCount = 0
    /// A sheet was just captured and auto-capture waits for the next one.
    private(set) var isAwaitingNextPage = false
    /// Photos requested but not yet delivered to `onPhoto`.
    private(set) var capturesInFlight = 0
    /// Why the session is paused right now (interrupted or failed); nil while it runs normally.
    private(set) var interruption: CameraInterruption?
    var flashMode: CameraFlashMode = .auto
    var isAutoCaptureEnabled = true
    /// Auto-capture is suspended (a dialog covers the camera, or the app isn't active). The shutter
    /// still works. Set with `setAutoCapturePaused(_:)`.
    private(set) var isAutoCapturePaused = false

    /// Receives each photo's encoded data, in shutter order.
    @ObservationIgnored var onPhoto: ((Data) -> Void)?
    /// Receives capture errors.
    @ObservationIgnored var onError: ((Error) -> Void)?

    /// Created on first use (`session`, `start`, `stop`, `takePhoto`, …), never in `init`.
    /// `CameraCaptureFlow` holds this controller in `@State`, whose default value SwiftUI evaluates
    /// on every view init and then discards. Keeping `init` free of AVFoundation objects makes
    /// those throwaway controllers cost nothing.
    @ObservationIgnored private lazy var pipeline = CaptureSessionPipeline()
    #if DEBUG
    /// The demo still standing in for the camera while the DEBUG demo library is active; nil
    /// otherwise, and then everything below uses `pipeline`.
    @ObservationIgnored private lazy var demo: DemoCameraFeed? = DemoCameraFeed.isEnabled ? DemoCameraFeed() : nil
    #endif
    @ObservationIgnored private var updatesTask: Task<Void, Never>?
    @ObservationIgnored private var eventsTask: Task<Void, Never>?
    @ObservationIgnored private var cooldownUntil = Date.distantPast
    @ObservationIgnored private var capturedQuad: Quadrilateral?
    @ObservationIgnored private var missingSince: Date?
    /// Bumped by every `start()` and `stop()`: a `start()` that resumes after a newer call is stale.
    @ObservationIgnored private var sessionGeneration = 0

    /// Pause after any capture before auto-capture may fire again.
    static let cooldown: TimeInterval = 1.2
    /// Corner movement (normalised) that counts as "a different sheet" after a capture.
    static let rearmDistance: CGFloat = 0.08
    /// How long no sheet must be seen after a capture to count as "sheet removed".
    static let rearmGap: TimeInterval = 0.5

    static var isCameraAvailable: Bool {
        #if DEBUG
        // The demo feed works without a camera, so the simulator gets Offscan's camera screen.
        if DemoCameraFeed.isEnabled { return true }
        #endif
        return CaptureSessionPipeline.isCameraAvailable
    }

    var session: AVCaptureSession { pipeline.session }

    #if DEBUG
    /// The demo feed whose still `DocumentCameraScreen` shows instead of the preview (DEBUG demo
    /// library only).
    var demoFeed: DemoCameraFeed? { demo }
    #endif

    /// The shutter (and auto-capture) can take a photo: running and not interrupted.
    var isCaptureAvailable: Bool { status == .running && interruption == nil }

    /// The current outline, if it belongs to the orientation the screen is shown in.
    var liveDetection: LiveDetectionUpdate? {
        guard let detection, detection.orientation == orientation, detection.quad != nil else { return nil }
        return detection
    }

    /// Progress of the steady period towards an auto-capture (0 when auto-capture can't fire).
    var autoCaptureProgress: Double {
        guard isAutoCaptureEnabled, !isAutoCapturePaused, !isAwaitingNextPage, let liveDetection else { return 0 }
        return liveDetection.progress
    }

    // MARK: Lifecycle

    /// Asks for camera access if needed, then configures and starts the session.
    func start() async {
        guard status == .idle || status == .failed else { return }
        sessionGeneration += 1
        let generation = sessionGeneration
        interruption = nil
        status = .starting
        #if DEBUG
        if let demo {
            await startDemo(demo, generation: generation)
            return
        }
        #endif
        let granted = await Self.requestAccess()
        // stop() ran meanwhile (maybe start() again too): this call is stale.
        guard generation == sessionGeneration else { return }
        guard granted else {
            status = .denied
            return
        }
        do {
            let size = try await pipeline.start()
            // stop() queued pipeline.stop() after this start on the serial session queue, so the
            // session is already stopped again.
            guard generation == sessionGeneration else { return }
            sensorSize = size
            status = .running
            listen()
        } catch {
            guard generation == sessionGeneration else { return }
            status = .failed
        }
    }

    /// Stops the session; `start()` resumes it. Any `start()` still in progress is abandoned.
    func stop() {
        sessionGeneration += 1
        #if DEBUG
        if let demo { demo.stop() } else { pipeline.stop() }
        #else
        pipeline.stop()
        #endif
        detection = nil
        interruption = nil
        if status == .running || status == .starting { status = .idle }
    }

    /// Suspends or resumes auto-capture (dialogs, inactive scene). On resume a sheet that sat still
    /// under the dialog needs a fresh steady period and the cooldown first.
    func setAutoCapturePaused(_ paused: Bool) {
        guard paused != isAutoCapturePaused else { return }
        isAutoCapturePaused = paused
        guard !paused else { return }
        cooldownUntil = max(cooldownUntil, Date().addingTimeInterval(Self.cooldown))
        #if DEBUG
        if let demo {
            demo.resetTracking()
            return
        }
        #endif
        pipeline.resetTracking()
    }

    func setOrientation(_ orientation: CameraOrientation) {
        guard orientation != self.orientation else { return }
        self.orientation = orientation
        detection = nil
        #if DEBUG
        if let demo {
            demo.setOrientation(orientation)
            return
        }
        #endif
        pipeline.setOrientation(orientation)
    }

    private static func requestAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: true
        case .notDetermined: await AVCaptureDevice.requestAccess(for: .video)
        default: false
        }
    }

    private func listen() {
        if updatesTask == nil {
            let updates = pipeline.updates
            updatesTask = Task { [weak self] in
                for await update in updates {
                    self?.receive(update)
                }
            }
        }
        if eventsTask == nil {
            let events = pipeline.events
            eventsTask = Task { [weak self] in
                for await event in events {
                    self?.handle(event)
                }
            }
        }
    }

    private func handle(_ event: CaptureSessionPipeline.Event) {
        guard status == .running || status == .starting else { return }
        switch event {
        case .interrupted(let kind):
            interruption = kind
            // The frozen preview's outline is stale.
            detection = nil
            pipeline.resetTracking()
        case .resumed:
            interruption = nil
        }
    }

    // MARK: Capture

    /// Takes a photo now (shutter button, or auto-capture). Works while running and not interrupted.
    func takePhoto() {
        guard status == .running, interruption == nil else { return }
        captureCount += 1
        cooldownUntil = Date().addingTimeInterval(Self.cooldown)
        capturedQuad = liveDetection?.quad
        isAwaitingNextPage = capturedQuad != nil
        missingSince = nil
        #if DEBUG
        if let demo {
            takeDemoPhoto(demo)
            return
        }
        #endif
        pipeline.resetTracking()

        let pipeline = pipeline
        let flash = flashMode.captureMode
        let angle = orientation.rotationAngle
        capturesInFlight += 1
        Task {
            defer { capturesInFlight -= 1 }
            do {
                let data = try await pipeline.capturePhoto(flashMode: flash, rotationAngle: angle)
                onPhoto?(data)
            } catch {
                onError?(error)
            }
        }
    }

    #if DEBUG
    // MARK: Demo feed (DEBUG demo library only)

    /// `start()` on the demo still: no camera permission, frames from `DemoCameraFeed`.
    private func startDemo(_ demo: DemoCameraFeed, generation: Int) async {
        let size = await demo.prepare()
        guard generation == sessionGeneration else { return }
        guard let size else {
            status = .failed
            return
        }
        sensorSize = size
        status = .running
        demo.startFrames()
        if updatesTask == nil {
            let updates = demo.updates
            updatesTask = Task { [weak self] in
                for await update in updates {
                    self?.receive(update)
                }
            }
        }
    }

    /// The shutter on the demo still: delivers its JPEG a moment later, like a photo.
    private func takeDemoPhoto(_ demo: DemoCameraFeed) {
        demo.resetTracking()
        let data = demo.photoData
        capturesInFlight += 1
        Task {
            defer { capturesInFlight -= 1 }
            try? await Task.sleep(for: .milliseconds(150))
            if let data { onPhoto?(data) }
        }
    }
    #endif

    private func receive(_ update: LiveDetectionUpdate) {
        // A frame buffered before an interruption must not redraw an outline.
        guard status == .running, interruption == nil else { return }
        detection = update
        guard update.orientation == orientation else { return }
        let now = Date()
        if isAwaitingNextPage { updateRearm(with: update.quad, at: now) }
        if isAutoCaptureEnabled, !isAutoCapturePaused, !isAwaitingNextPage, update.isStable, now >= cooldownUntil {
            takePhoto()
        }
    }

    /// Re-arms auto-capture once the captured sheet moved away or has been gone for `rearmGap`.
    private func updateRearm(with quad: Quadrilateral?, at now: Date) {
        guard let quad else {
            if let missingSince {
                if now.timeIntervalSince(missingSince) >= Self.rearmGap { isAwaitingNextPage = false }
            } else {
                missingSince = now
            }
            return
        }
        missingSince = nil
        guard let capturedQuad else {
            isAwaitingNextPage = false
            return
        }
        let moved = zip(quad.corners, capturedQuad.corners).map { hypot($0.x - $1.x, $0.y - $1.y) }.max() ?? 0
        if moved > Self.rearmDistance { isAwaitingNextPage = false }
    }
}
