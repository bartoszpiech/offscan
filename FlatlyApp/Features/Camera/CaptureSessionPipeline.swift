import AVFoundation
import CoreImage
import FlatlyCore

/// The AVFoundation side of Offscan's camera: owns the capture session (back wide-angle camera,
/// `.photo` preset), a photo output for full-resolution stills and a YUV 4:2:0 video data output
/// whose frames are analysed with `DocumentDetector.detectLive` and a `QuadStabilityTracker`.
///
/// `@unchecked Sendable` because AVFoundation objects aren't `Sendable`. Safety rests on strict
/// queue confinement, which every member below states:
/// - session configuration, start/stop and photo capture run only on `sessionQueue`; `stop()`
///   always calls `stopRunning()`, so an interruption can't restart a stopped session;
/// - frame analysis state (`tracker`, `orientation`, `lastAnalysis`) is touched only on `videoQueue`
///   (the sample-buffer delegate queue; setters hop onto it);
/// - `session` itself is read from the main thread only to attach it to the preview layer, which
///   AVFoundation documents as safe;
/// - the session's notification observers (interruption, interruption ended, did start running,
///   runtime error) only read the notification and yield to `events`, or hop onto `sessionQueue`;
///   they are registered in `init` and removed in `deinit`.
/// Results leave through `updates` and `events`, `AsyncStream`s (thread-safe) consumed on the main
/// actor. After a runtime error the session is restarted once, at most every 3 s; if that doesn't
/// help, `.interrupted(.failed)` is reported.
final class CaptureSessionPipeline: NSObject, @unchecked Sendable {
    /// Session state changes the UI must reflect.
    enum Event: Sendable {
        /// The session was interrupted, or stopped after a runtime error.
        case interrupted(CameraInterruption)
        /// The session runs again.
        case resumed
    }

    /// Attached to `AVCaptureVideoPreviewLayer` on the main thread; otherwise sessionQueue only.
    let session = AVCaptureSession()
    /// Analysed frames, newest only (the UI never needs a backlog).
    let updates: AsyncStream<LiveDetectionUpdate>
    /// Interruptions and resumptions, in order (unbounded: they are rare and order matters).
    let events: AsyncStream<Event>

    private let continuation: AsyncStream<LiveDetectionUpdate>.Continuation
    private let eventsContinuation: AsyncStream<Event>.Continuation
    /// Set in `init`, removed in `deinit`.
    private var observers: [any NSObjectProtocol] = []
    private let sessionQueue = DispatchQueue(label: "flatly.camera.session", qos: .userInitiated)
    private let videoQueue = DispatchQueue(label: "flatly.camera.video", qos: .userInitiated)

    // sessionQueue only
    private let photoOutput = AVCapturePhotoOutput()
    private let videoOutput = AVCaptureVideoDataOutput()
    private var isConfigured = false
    private var sensorSize = CGSize(width: 4, height: 3)
    private var inProgressCaptures: [Int64: PhotoCaptureDelegate] = [:]
    /// `start()` was called and `stop()` wasn't: a runtime error may restart the session.
    private var wantsRunning = false
    private var lastAutomaticRestart: Date?

    // videoQueue only
    private let detector = DocumentDetector()
    private var tracker = QuadStabilityTracker()
    private var orientation: CameraOrientation = .portrait
    private var lastAnalysis: Date?

    /// Minimum time between analysed frames (~9 per second); frames in between are dropped.
    private static let analysisInterval: TimeInterval = 0.11
    /// Photos larger than this (48 MP sensors) only cost time and memory: `stageImport` keeps at
    /// most 3500 px on the long side anyway.
    private static let maxPhotoPixels = 12_600_000
    /// A runtime error within this time of the last automatic restart is reported as `.failed`.
    private static let minimumRestartInterval: TimeInterval = 3

    override init() {
        (updates, continuation) = AsyncStream.makeStream(of: LiveDetectionUpdate.self, bufferingPolicy: .bufferingNewest(1))
        (events, eventsContinuation) = AsyncStream.makeStream(of: Event.self)
        super.init()
        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: AVCaptureSession.wasInterruptedNotification, object: session, queue: nil) { [weak self] notification in
                let raw = notification.userInfo?[AVCaptureSessionInterruptionReasonKey] as? Int
                let reason = raw.flatMap(AVCaptureSession.InterruptionReason.init(rawValue:))
                self?.eventsContinuation.yield(.interrupted(CameraInterruption(reason: reason)))
            },
            center.addObserver(forName: AVCaptureSession.interruptionEndedNotification, object: session, queue: nil) { [weak self] _ in
                self?.eventsContinuation.yield(.resumed)
            },
            // A second, redundant resume signal, so the shutter can't stay disabled if one is missed.
            center.addObserver(forName: AVCaptureSession.didStartRunningNotification, object: session, queue: nil) { [weak self] _ in
                self?.eventsContinuation.yield(.resumed)
            },
            center.addObserver(forName: AVCaptureSession.runtimeErrorNotification, object: session, queue: nil) { [weak self] _ in
                self?.restartAfterRuntimeError()
            },
        ]
    }

    deinit {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        continuation.finish()
        eventsContinuation.finish()
    }

    static var isCameraAvailable: Bool {
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) != nil
    }

    // MARK: Session

    /// Configures the session on first use and starts it. Returns the sensor's pixel size
    /// (landscape, e.g. 4032×3024) so the UI can frame the preview at the photo's aspect ratio.
    func start() async throws -> CGSize {
        try await withCheckedThrowingContinuation { continuation in
            sessionQueue.async {
                do {
                    if !self.isConfigured { try self.configure() }
                    self.wantsRunning = true
                    if !self.session.isRunning { self.session.startRunning() }
                    continuation.resume(returning: self.sensorSize)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Stops the session (frees the camera). Safe to call repeatedly.
    ///
    /// Calls `stopRunning()` even when the session reports it isn't running: an interrupted session
    /// (background, camera in use by another app, multitasking, system pressure) has
    /// `isRunning == false` but starts again by itself when the interruption ends, unless
    /// `stopRunning()` was called. Skipping the call would let the camera resume behind the app lock
    /// or during the corner review. `stopRunning()` is a no-op on a stopped session; only a session
    /// that was never configured (e.g. camera permission denied) is left alone.
    func stop() {
        sessionQueue.async {
            // restartAfterRuntimeError must not restart a session stopped on purpose.
            self.wantsRunning = false
            if self.isConfigured { self.session.stopRunning() }
        }
    }

    /// Restarts the session once after a runtime error (any kind, e.g. media services reset),
    /// unless it was stopped on purpose; a repeat within 3 s, or a restart that doesn't take, is
    /// reported as `.failed`. A successful restart posts didStartRunning, which yields `.resumed`.
    private func restartAfterRuntimeError() {
        sessionQueue.async {
            guard self.wantsRunning, !self.session.isRunning else { return }
            if let last = self.lastAutomaticRestart, Date().timeIntervalSince(last) < Self.minimumRestartInterval {
                self.eventsContinuation.yield(.interrupted(.failed))
                return
            }
            self.lastAutomaticRestart = Date()
            self.session.startRunning()
            if !self.session.isRunning && !self.session.isInterrupted {
                self.eventsContinuation.yield(.interrupted(.failed))
            }
        }
    }

    private func configure() throws {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            throw CameraError.unavailable
        }
        let input = try AVCaptureDeviceInput(device: device)

        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .photo
        guard session.canAddInput(input) else { throw CameraError.configurationFailed }
        session.addInput(input)

        guard session.canAddOutput(photoOutput) else { throw CameraError.configurationFailed }
        session.addOutput(photoOutput)
        photoOutput.maxPhotoQualityPrioritization = .balanced
        let dimensions = device.activeFormat.supportedMaxPhotoDimensions
        let fitting = dimensions.filter { Int($0.width) * Int($0.height) <= Self.maxPhotoPixels }
        if let best = fitting.max(by: { $0.width * $0.height < $1.width * $1.height }) ?? dimensions.first {
            photoOutput.maxPhotoDimensions = best
        }

        // The camera's native YUV 4:2:0 format: Vision reads it directly. BGRA would make the output
        // convert (and deliver at ~2.7x the size) every frame at the session rate, though most are
        // dropped. Setting an unsupported format raises an exception, hence the BGRA fallback.
        let yuv = kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        let pixelFormat = videoOutput.availableVideoPixelFormatTypes.contains(yuv) ? yuv : kCVPixelFormatType_32BGRA
        videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: pixelFormat]
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.setSampleBufferDelegate(self, queue: videoQueue)
        guard session.canAddOutput(videoOutput) else { throw CameraError.configurationFailed }
        session.addOutput(videoOutput)

        let format = CMVideoFormatDescriptionGetDimensions(device.activeFormat.formatDescription)
        if format.width > 0, format.height > 0 {
            sensorSize = CGSize(width: Int(format.width), height: Int(format.height))
        }
        Self.configureFocus(device)
        isConfigured = true
    }

    /// Continuous autofocus/exposure, biased to near subjects (documents are close).
    private static func configureFocus(_ device: AVCaptureDevice) {
        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }
            if device.isFocusModeSupported(.continuousAutoFocus) { device.focusMode = .continuousAutoFocus }
            if device.isAutoFocusRangeRestrictionSupported { device.autoFocusRangeRestriction = .near }
            if device.isExposureModeSupported(.continuousAutoExposure) { device.exposureMode = .continuousAutoExposure }
        } catch {
            // Defaults are fine; focus tuning is an optimisation.
        }
    }

    // MARK: Photo

    /// Takes a full-resolution photo and returns its encoded data (HEIC or JPEG, EXIF orientation
    /// set from `rotationAngle`, so decoding with `ImageCodec` yields an upright image).
    func capturePhoto(flashMode: AVCaptureDevice.FlashMode, rotationAngle: CGFloat) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            sessionQueue.async {
                guard self.session.isRunning else {
                    continuation.resume(throwing: CameraError.notRunning)
                    return
                }
                let settings = AVCapturePhotoSettings()
                settings.flashMode = self.photoOutput.supportedFlashModes.contains(flashMode) ? flashMode : .off
                settings.photoQualityPrioritization = .balanced
                settings.maxPhotoDimensions = self.photoOutput.maxPhotoDimensions
                if let connection = self.photoOutput.connection(with: .video),
                   connection.isVideoRotationAngleSupported(rotationAngle) {
                    connection.videoRotationAngle = rotationAngle
                }
                let id = settings.uniqueID
                let delegate = PhotoCaptureDelegate(
                    completion: { result in continuation.resume(with: result) },
                    // Strong capture: the cycle with `inProgressCaptures` ends when the entry is removed.
                    onFinished: {
                        self.sessionQueue.async { self.inProgressCaptures[id] = nil }
                    }
                )
                // The photo output doesn't retain its delegate long enough on every OS version.
                self.inProgressCaptures[id] = delegate
                self.photoOutput.capturePhoto(with: settings, delegate: delegate)
            }
        }
    }

    // MARK: Analysis

    /// Sets the orientation frames are analysed for and restarts tracking.
    func setOrientation(_ orientation: CameraOrientation) {
        videoQueue.async {
            guard self.orientation != orientation else { return }
            self.orientation = orientation
            self.tracker.reset()
        }
    }

    /// Forgets the tracked sheet, so the next auto-capture needs a fresh steady period.
    func resetTracking() {
        videoQueue.async { self.tracker.reset() }
    }
}

extension CaptureSessionPipeline: AVCaptureVideoDataOutputSampleBufferDelegate {
    /// Called on `videoQueue`. Late frames are discarded by the output while one is analysed.
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let now = Date()
        if let lastAnalysis, now.timeIntervalSince(lastAnalysis) < Self.analysisInterval { return }
        lastAnalysis = now
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let detection = try? detector.detectLive(in: pixelBuffer, orientation: orientation.visionOrientation)
        tracker.update(with: detection?.quad, at: now)
        let sensorSize = CGSize(width: CVPixelBufferGetWidth(pixelBuffer), height: CVPixelBufferGetHeight(pixelBuffer))
        continuation.yield(LiveDetectionUpdate(
            quad: tracker.smoothedQuad,
            progress: tracker.progress(at: now),
            isStable: tracker.isStable(at: now),
            isTooSmall: tracker.isSheetTooSmall,
            orientation: orientation,
            uprightSize: orientation.uprightSize(forSensorSize: sensorSize)
        ))
    }
}
