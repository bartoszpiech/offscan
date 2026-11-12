import SwiftUI
import UIKit
import FlatlyCore

/// Offscan's full-screen document camera: live preview with the detected sheet outlined, flash and
/// auto-capture toggles, a shutter that fills a ring while a steady sheet counts down to an
/// auto-capture, and a thumbnail of the latest page. Photos are handed to `pages` for staging.
/// For 3 s after each photo the hint becomes an Undo button (`onDelete`); the thumbnail opens the
/// "Scanned Pages" sheet over the live camera (delete single pages; auto-capture pauses while it is
/// open). Only `onDone` (the camera's Done, or Finish Scanning in the pages sheet) ends shooting
/// and starts the review; `onCancel` leaves (after confirming when pages would be lost).
///
/// With VoiceOver running, a settled change in detection ("Document detected" / "No document
/// detected") and every capture ("Captured") are announced.
///
/// The session stops while the app is locked or in the background; auto-capture pauses under
/// dialogs and alerts and while the scene is inactive; the screen stays awake only for 2 minutes
/// after opening the camera or the last capture, then normal auto-lock applies.
struct DocumentCameraScreen: View {
    let controller: CameraController
    let pages: CameraPageQueue
    /// The host shows an alert over the camera (auto-capture pauses).
    let isAlertPresented: Bool
    let onCancel: () -> Void
    let onDone: () -> Void
    /// Removes one photo (a `CameraPageQueue.Shot` id).
    let onDelete: (UUID) -> Void

    @Environment(AppLockManager.self) private var lock
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityVoiceOverEnabled) private var isVoiceOverEnabled

    @AppStorage("autoCapture") private var autoCapture = true
    @AppStorage("cameraFlash") private var flashMode: CameraFlashMode = .auto
    @State private var flashOpacity = 0.0
    @State private var showsCapturedHint = false
    @State private var capturedHintTask: Task<Void, Never>?
    @State private var isCancelDialogPresented = false
    @State private var isPagesSheetPresented = false
    /// Finish Scanning was tapped in the pages sheet: Done runs once the sheet has closed.
    @State private var finishesAfterPagesSheet = false
    /// The photo the Undo button would remove (for 3 s after it was added).
    @State private var undoableShotID: UUID?
    @State private var undoTask: Task<Void, Never>?
    @State private var undoCount = 0
    @State private var detectionAnnouncementTask: Task<Void, Never>?
    /// The last detection state spoken. False at first: the camera opens with nothing detected,
    /// so there is nothing to say.
    @State private var announcedDocument = false

    /// Detection must stay unchanged this long before VoiceOver hears about it, so flickering
    /// frames and the brief gap while pages are swapped (longer than `CameraController.rearmGap`)
    /// don't chatter.
    private static let detectionAnnouncementDelay: Duration = .milliseconds(800)

    /// Restarts the awake window: each capture, and the camera being allowed again.
    private struct AwakeKey: Equatable {
        let captureCount: Int
        let isCameraAllowed: Bool
    }

    /// Screen stays on this long after opening the camera or the last capture; then normal
    /// auto-lock applies.
    private static let awakeWindow: Duration = .seconds(120)

    /// The camera may run: the app is unlocked and not in the background.
    private var isCameraAllowed: Bool { !lock.isLocked && scenePhase != .background }

    private var isAutoCapturePaused: Bool {
        !isCameraAllowed || scenePhase != .active || isCancelDialogPresented || isAlertPresented
            || isPagesSheetPresented || finishesAfterPagesSheet
    }

    /// The photo Undo would remove: the one just taken, while it is still in the session (it may
    /// have been deleted in the Scanned Pages sheet).
    private var undoableShot: UUID? {
        guard let id = undoableShotID, pages.shots.contains(where: { $0.id == id }) else { return nil }
        return id
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            switch controller.status {
            case .denied:
                CameraPermissionView(onClose: onCancel)
            case .failed:
                CameraUnavailableView(onClose: onCancel)
            case .idle, .starting, .running:
                camera
            }
        }
        .environment(\.colorScheme, .dark)
        .statusBarHidden()
        .task {
            controller.isAutoCaptureEnabled = autoCapture
            controller.flashMode = flashMode
            if isCameraAllowed { await controller.start() }
        }
        .onChange(of: isCameraAllowed) { _, allowed in
            // start() resumes from .idle (which stop() sets) and retries after .failed.
            if allowed { Task { await controller.start() } } else { controller.stop() }
        }
        .onChange(of: isAutoCapturePaused, initial: true) { _, paused in
            controller.setAutoCapturePaused(paused)
        }
        .task(id: AwakeKey(captureCount: controller.captureCount, isCameraAllowed: isCameraAllowed)) {
            guard isCameraAllowed else {
                UIApplication.shared.isIdleTimerDisabled = false
                return
            }
            UIApplication.shared.isIdleTimerDisabled = true
            do { try await Task.sleep(for: Self.awakeWindow) } catch { return }
            UIApplication.shared.isIdleTimerDisabled = false
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            capturedHintTask?.cancel()
            undoTask?.cancel()
            detectionAnnouncementTask?.cancel()
            controller.stop()
        }
        .onChange(of: autoCapture) { _, enabled in controller.isAutoCaptureEnabled = enabled }
        .onChange(of: flashMode) { _, mode in controller.flashMode = mode }
        .onChange(of: controller.captureCount) { didCapture() }
        .onChange(of: pages.lastAddedID) { _, id in
            guard let id else { return }
            undoableShotID = id
            undoTask?.cancel()
            undoTask = Task {
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled else { return }
                undoableShotID = nil
            }
        }
        .onChange(of: pages.count) { _, count in
            if count == 0 { isPagesSheetPresented = false }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: undoCount)
        .onChange(of: controller.liveDetection != nil) { scheduleDetectionAnnouncement() }
        .onChange(of: controller.interruption) { _, new in
            if let message = new?.message { announce(message, interrupting: true) }
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: controller.captureCount)
        .confirmationDialog(Text("Discard Scanned Pages?"), isPresented: $isCancelDialogPresented, titleVisibility: .visible) {
            Button("Discard All Pages", role: .destructive, action: onCancel)
                .accessibilityIdentifier("camera.discardAll")
            Button("Keep Scanning", role: .cancel) {}
                .accessibilityIdentifier("camera.keepScanning")
        }
        // Outside the forced dark environment: the sheet follows the system appearance, matching
        // its UIKit background. Opaque: over the live feed the iOS 26 glass at the medium detent is
        // hard to read and shows the camera's controls blurred underneath.
        // Finish Scanning only closes the sheet; Done runs from onDismiss, once the sheet is gone,
        // so the screen is never replaced while its sheet is still up.
        .sheet(isPresented: $isPagesSheetPresented, onDismiss: finishAfterPagesSheetIfRequested) {
            CapturedPagesSheet(
                pages: pages,
                canFinish: canFinish,
                onDelete: onDelete,
                onFinish: requestFinishFromPagesSheet
            )
            .presentationDetents([.medium, .large])
            .presentationBackground(Color(uiColor: .systemGroupedBackground))
        }
    }

    private var camera: some View {
        VStack(spacing: 0) {
            topBar
            viewfinder
            hintLabel
            bottomBar
        }
        .overlay {
            Color.white
                .opacity(flashOpacity)
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    // MARK: Viewfinder

    private var viewfinder: some View {
        ZStack {
            preview
            LiveQuadOverlay(detection: controller.liveDetection)
            if controller.interruption?.message != nil {
                // Hides the frozen frame, like the system Camera app.
                Color.black.opacity(0.6)
                    .overlay {
                        Image(systemName: "video.slash.fill")
                            .font(.largeTitle)
                            .foregroundStyle(.white)
                    }
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            if controller.status != .running {
                ProgressView()
                    .controlSize(.large)
                    .tint(.white)
            }
        }
        // Framed at the photo's aspect ratio, so the preview shows exactly what is captured.
        .aspectRatio(controller.orientation.uprightSize(forSensorSize: controller.sensorSize), contentMode: .fit)
        .clipped()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement()
        .accessibilityLabel(Text("Camera viewfinder"))
        .accessibilityValue(viewfinderValue)
        .accessibilityIdentifier("camera.viewfinder")
    }

    /// The live camera preview; with the DEBUG demo library, the demo still instead.
    @ViewBuilder
    private var preview: some View {
        #if DEBUG
        if let demoFeed = controller.demoFeed {
            if let still = demoFeed.still {
                // Same aspect as the viewfinder (the demo sensor size), filled like the preview layer.
                Image(decorative: still, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Color.black
            }
        } else {
            cameraPreview
        }
        #else
        cameraPreview
        #endif
    }

    private var cameraPreview: some View {
        CameraPreviewView(
            session: controller.session,
            isRunning: controller.status == .running,
            onOrientationChange: { controller.setOrientation($0) }
        )
    }

    private var viewfinderValue: Text {
        if let message = controller.interruption?.message { return Text(message) }
        return Text(controller.liveDetection == nil ? "No document detected" : "Document detected")
    }

    private var hintText: Text? {
        // Already localized (`CameraInterruption.message`).
        if let message = controller.interruption?.message { return Text(message) }
        if showsCapturedHint { return Text("Captured") }
        guard controller.status == .running else { return nil }
        guard let detection = controller.liveDetection else { return Text("Point the camera at a document") }
        if controller.isAutoCaptureEnabled && controller.isAwaitingNextPage { return Text("Show the next page") }
        if controller.isAutoCaptureEnabled && detection.isTooSmall { return Text("Move closer") }
        return Text("Hold steady…")
    }

    /// The hint capsule, or for 3 s after a photo (while that photo is still in the session) an
    /// Undo button in the same capsule (an interruption message wins over both).
    @ViewBuilder
    private var hintLabel: some View {
        if controller.interruption?.message == nil, undoableShot != nil {
            Button(action: undo) {
                Label("Undo", systemImage: "arrow.uturn.backward")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
                    // Inside the label, so the tap target is at least 44 pt tall.
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Undo last photo"))
            .accessibilityIdentifier("camera.undo")
        } else {
            hintCapsule
                .padding(.vertical, 10)
        }
    }

    private var hintCapsule: some View {
        (hintText ?? Text(verbatim: " "))
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.primary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial, in: Capsule())
            .opacity(hintText == nil ? 0 : 1)
            .animation(.easeInOut(duration: 0.2), value: hintText)
            .accessibilityIdentifier("camera.hint")
    }

    // MARK: Bars

    private var topBar: some View {
        HStack(spacing: 20) {
            Button(action: cancel) {
                Text("Cancel")
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityIdentifier("camera.cancel")
            Spacer()
            Button {
                flashMode = flashMode.next
            } label: {
                Image(systemName: flashMode.systemImage)
                    .font(.title3)
                    .frame(minWidth: 44, minHeight: 44)
            }
            .accessibilityLabel(Text("Flash"))
            .accessibilityValue(Text(flashMode.accessibilityValue))
            .accessibilityIdentifier("camera.flash")
            Button {
                autoCapture.toggle()
            } label: {
                Text("Auto")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(autoCapture ? Color.black : Color.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(autoCapture ? Color.yellow : Color.clear))
                    .overlay(Capsule().stroke(Color.primary.opacity(autoCapture ? 0 : 0.6), lineWidth: 1))
                    .frame(minHeight: 44)
            }
            .accessibilityLabel(Text("Auto-capture"))
            .accessibilityValue(Text(autoCapture ? "On" : "Off"))
            .accessibilityAddTraits(.isToggle)
            .accessibilityHint(Text("Takes the photo automatically when the document is held steady."))
            .accessibilityIdentifier("camera.auto")
        }
        .tint(.primary)
        .padding(.horizontal)
        .padding(.top, 4)
    }

    private var bottomBar: some View {
        HStack {
            thumbnail
                .frame(maxWidth: .infinity, alignment: .leading)
            ShutterButton(
                progress: controller.autoCaptureProgress,
                isEnabled: controller.isCaptureAvailable,
                action: { controller.takePhoto() }
            )
            Button(action: onDone) {
                Text("Done")
                    .font(.headline)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .disabled(!canFinish)
            // Outside the button: the bar keeps three equal columns, only the label is tappable.
            .frame(maxWidth: .infinity, alignment: .trailing)
            .accessibilityIdentifier("camera.done")
        }
        .tint(.primary)
        .padding(.horizontal, 24)
        .padding(.bottom, 12)
    }

    @ViewBuilder
    private var thumbnail: some View {
        if pages.count > 0 {
            Button {
                isPagesSheetPresented = true
            } label: {
                ZStack {
                    if let image = pages.latestThumbnail {
                        Image(decorative: image, scale: 1)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Color.secondary.opacity(0.3)
                        ProgressView()
                    }
                }
                .frame(width: 52, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.white.opacity(0.8), lineWidth: 1))
                .overlay(alignment: .topTrailing) {
                    Text(pages.count, format: .number)
                        .font(.caption2.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(Color.onAccent)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.accentColor))
                        .offset(x: 8, y: -8)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Scanned Pages"))
            .accessibilityValue(Text("\(pages.count) pages"))
            .accessibilityHint(Text("Shows the pages taken so far."))
            .accessibilityIdentifier("camera.thumbnail")
        } else {
            Color.clear.frame(width: 52, height: 52)
                .accessibilityHidden(true)
        }
    }

    // MARK: Actions

    /// At least one page, and no photo still on its way (it would miss the review).
    private var canFinish: Bool {
        pages.count > 0 && controller.capturesInFlight == 0
    }

    private func cancel() {
        if pages.count > 0 { isCancelDialogPresented = true } else { onCancel() }
    }

    /// Finish Scanning in the pages sheet: closes the sheet; `finishAfterPagesSheetIfRequested`
    /// ends shooting once it is gone (auto-capture stays paused until then).
    private func requestFinishFromPagesSheet() {
        finishesAfterPagesSheet = true
        isPagesSheetPresented = false
    }

    /// The pages sheet's `onDismiss`: runs Done if Finish Scanning closed it.
    private func finishAfterPagesSheetIfRequested() {
        guard finishesAfterPagesSheet else { return }
        finishesAfterPagesSheet = false
        if canFinish { onDone() }
    }

    /// Removes the photo just taken. The auto-capture state is left alone: while the sheet is still
    /// in view, `isAwaitingNextPage` keeps it from being shot again automatically, and the user
    /// retakes it with the shutter.
    private func undo() {
        guard let id = undoableShot else { return }
        undoTask?.cancel()
        undoableShotID = nil
        onDelete(id)
        undoCount += 1
    }

    /// Speaks a detection change once it has settled (VoiceOver only).
    private func scheduleDetectionAnnouncement() {
        guard isVoiceOverEnabled else { return }
        detectionAnnouncementTask?.cancel()
        detectionAnnouncementTask = Task {
            try? await Task.sleep(for: Self.detectionAnnouncementDelay)
            guard !Task.isCancelled, controller.status == .running else { return }
            // The settled state at fire time: true → false → true within the delay says nothing.
            let hasDocument = controller.liveDetection != nil
            guard hasDocument != announcedDocument else { return }
            announcedDocument = hasDocument
            if hasDocument {
                announce(String(localized: "Document detected"), interrupting: false)
            } else {
                announce(String(localized: "No document detected"), interrupting: false)
            }
        }
    }

    private func announce(_ text: String, interrupting: Bool) {
        var message = AttributedString(text)
        message.accessibilitySpeechAnnouncementPriority = interrupting ? .high : .default
        AccessibilityNotification.Announcement(message).post()
    }

    private func didCapture() {
        // Auto-capture and shutter taps alike; high priority so a detection change right after
        // can't cut it off.
        if isVoiceOverEnabled { announce(String(localized: "Captured"), interrupting: true) }
        flashOpacity = 0.85
        Task {
            try? await Task.sleep(for: .milliseconds(40))
            withAnimation(.easeOut(duration: 0.3)) { flashOpacity = 0 }
        }
        capturedHintTask?.cancel()
        showsCapturedHint = true
        capturedHintTask = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            showsCapturedHint = false
        }
    }
}
