import SwiftUI
import UIKit
import Observation

/// Shows `LockScreenView` in a dedicated window above the app's window while locked or shielded.
///
/// A plain SwiftUI overlay on the root view would sit *below* any presented sheet or full-screen
/// cover (camera, export, settings…), leaving them usable while locked. A separate window at
/// alert level covers everything in the scene. Attach it as a zero-size background of the root view.
///
/// A `.fullScreenCover` detaches the root view from its window, and SwiftUI may stop updating it
/// meanwhile. So the coordinator keeps the last window scene its view was in (falling back to the
/// app's connected scene), observes `AppLockManager` directly instead of relying on
/// `updateUIView`, and drives the lock from UIScene notifications: shield on will-deactivate, lock
/// synchronously on did-enter-background (before the app-switcher snapshot), unshield and the
/// once-per-foreground unlock prompt on did-activate. RootView's scene-phase handler calls the same
/// idempotent methods as a second trigger.
struct LockWindowPresenter: UIViewRepresentable {
    let lock: AppLockManager
    /// `lock.isLocked || lock.isShielded`. The coordinator reads the lock itself; this property
    /// only makes SwiftUI call `updateUIView` on changes, as a second trigger.
    let isPresented: Bool

    func makeCoordinator() -> Coordinator { Coordinator(lock: lock) }

    func makeUIView(context: Context) -> SceneTrackingView {
        let view = SceneTrackingView()
        view.isUserInteractionEnabled = false
        let coordinator = context.coordinator
        view.onWindowSceneChange = { scene in
            // Keep the last real scene: the view leaves its window under a full-screen cover.
            if let scene { coordinator.windowScene = scene }
            coordinator.sync()
        }
        return view
    }

    func updateUIView(_ uiView: SceneTrackingView, context: Context) {
        context.coordinator.sync()
    }

    static func dismantleUIView(_ uiView: SceneTrackingView, coordinator: Coordinator) {
        coordinator.tearDown()
    }

    @MainActor
    final class Coordinator {
        let lock: AppLockManager
        weak var windowScene: UIWindowScene?
        private var overlayWindow: UIWindow?
        private var isTornDown = false
        private var observers: [NSObjectProtocol] = []

        init(lock: AppLockManager) {
            self.lock = lock
            let center = NotificationCenter.default
            observers.append(center.addObserver(
                forName: UIScene.willDeactivateNotification, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.handleWillDeactivate() }
            })
            observers.append(center.addObserver(
                forName: UIScene.didEnterBackgroundNotification, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.handleDidEnterBackground() }
            })
            observers.append(center.addObserver(
                forName: UIScene.didActivateNotification, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.handleDidActivate() }
            })
            observeLock()
        }

        /// The lock window should be up: locked, or covered by the privacy shield.
        private var shouldPresent: Bool { lock.isLocked || lock.isShielded }

        func sync() {
            guard !isTornDown else { return }
            if shouldPresent {
                if overlayWindow == nil, let scene = windowScene ?? Self.fallbackScene() { present(in: scene) }
            } else {
                dismiss()
            }
        }

        /// Stops observing and removes the window (the root view went away).
        func tearDown() {
            isTornDown = true
            for observer in observers { NotificationCenter.default.removeObserver(observer) }
            observers = []
            dismiss()
        }

        /// Re-syncs on every change of the lock state, independent of SwiftUI updating the root.
        private func observeLock() {
            guard !isTornDown else { return }
            withObservationTracking {
                _ = lock.isLocked
                _ = lock.isShielded
            } onChange: { [weak self] in
                // `onChange` fires before the new value is set: read it on the next main-actor turn.
                Task { @MainActor [weak self] in
                    guard let self, !self.isTornDown else { return }
                    self.sync()
                    self.observeLock()
                }
            }
        }

        /// Covers the UI with the privacy shield as the scene becomes inactive (app switcher,
        /// Control Center), whatever RootView's scene-phase handling does.
        private func handleWillDeactivate() {
            lock.shieldIfEnabled()
            sync()
        }

        /// Locks before the app-switcher snapshot, whatever RootView's scene-phase handling does.
        private func handleDidEnterBackground() {
            lock.sceneDidEnterBackground()
            sync()
        }

        /// Unshields and shows the once-per-foreground unlock prompt when the scene becomes active,
        /// even while a full-screen cover keeps SwiftUI from updating RootView.
        private func handleDidActivate() {
            lock.sceneDidBecomeActive()
            sync()
        }

        /// The app is single-scene; used when the root view never reported one.
        private static func fallbackScene() -> UIWindowScene? {
            UIApplication.shared.connectedScenes.lazy
                .compactMap { $0 as? UIWindowScene }
                .first { $0.activationState != .unattached }
        }

        private func present(in scene: UIWindowScene) {
            let host = UIHostingController(rootView: LockScreenView().environment(lock))
            host.view.backgroundColor = .clear
            host.view.accessibilityViewIsModal = true
            let window = UIWindow(windowScene: scene)
            window.windowLevel = .alert + 1
            window.rootViewController = host
            window.makeKeyAndVisible()
            overlayWindow = window
        }

        private func dismiss() {
            guard let window = overlayWindow else { return }
            overlayWindow = nil
            window.isHidden = true
            window.rootViewController = nil
            window.windowScene?.windows.first { !$0.isHidden && $0.windowLevel == .normal }?.makeKey()
        }
    }

    /// Reports the window scene it is installed in.
    final class SceneTrackingView: UIView {
        var onWindowSceneChange: (@MainActor (UIWindowScene?) -> Void)?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            onWindowSceneChange?(window?.windowScene)
        }
    }
}
