import Foundation
import LocalAuthentication
import Observation

/// Optional app lock (Face ID / Touch ID with device-passcode fallback).
///
/// The enabled flag lives in `UserDefaults` under `appLockEnabled`. When enabled the app starts
/// locked and re-locks whenever the scene goes to the background; `LockScreenView` covers the UI
/// until `authenticate()` succeeds. While the scene is inactive (app switcher, Control Center) the
/// UI is covered by an opaque privacy shield (`isShielded`), so the app-switcher card and the
/// snapshot iOS saves show no document content. Under UI tests (`FLATLY_UI_TESTING=1`) the lock always starts
/// disabled and the setting is not persisted.
///
/// The scene callbacks (`shieldIfEnabled`, `sceneDidEnterBackground`, `sceneDidBecomeActive`) are
/// called twice per transition, from `LockWindowPresenter` (UIScene notifications, which keep coming
/// while a full-screen cover is up) and from RootView (scene phase); they are idempotent.
@MainActor
@Observable
final class AppLockManager {
    static let enabledDefaultsKey = "appLockEnabled"

    /// Whether the user turned the lock on.
    private(set) var isEnabled: Bool
    /// Whether the UI is currently covered by the lock screen.
    private(set) var isLocked: Bool
    /// True while the scene is inactive or in the background with the lock enabled. The lock window
    /// then covers the UI with an opaque privacy shield, so the app-switcher card and the snapshot
    /// iOS saves show no document content.
    private(set) var isShielded = false
    /// Biometry hardware available on this device (also set when not enrolled).
    private(set) var biometryType: LABiometryType = .none
    /// True when biometrics are available and enrolled.
    private(set) var canUseBiometrics = false
    /// True when the device can authenticate its owner at all (biometrics or passcode).
    private(set) var canAuthenticate = false
    /// True while the system authentication prompt is showing.
    private(set) var isAuthenticating = false
    /// User-facing message describing the last failed authentication, if any.
    private(set) var errorMessage: String?

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let persistsSetting: Bool
    /// The automatic unlock prompt is shown once per return to the foreground, so cancelling it
    /// doesn't immediately re-trigger it (the prompt itself makes the scene inactive and then active).
    @ObservationIgnored private var didAutoPrompt = false

    init(defaults: UserDefaults = .standard, environment: [String: String] = ProcessInfo.processInfo.environment) {
        let uiTesting = environment["FLATLY_UI_TESTING"] == "1"
        let enabled = uiTesting ? false : defaults.bool(forKey: Self.enabledDefaultsKey)
        self.defaults = defaults
        self.persistsSetting = !uiTesting
        self.isEnabled = enabled
        self.isLocked = enabled
        refreshBiometryState()
    }

    /// Re-reads biometry availability (enrolment can change while the app is running).
    func refreshBiometryState() {
        let context = LAContext()
        var error: NSError?
        canUseBiometrics = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
        biometryType = context.biometryType
        var passcodeError: NSError?
        canAuthenticate = canUseBiometrics || LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: &passcodeError)
    }

    /// Called when the scene enters the background, from LockWindowPresenter (UIScene notification)
    /// and RootView (scene phase); calling it twice is harmless. Locks the UI if the lock is enabled
    /// and re-arms the automatic unlock prompt for the next return to the foreground.
    func sceneDidEnterBackground() {
        didAutoPrompt = false
        lockIfEnabled()
    }

    /// Called when the scene becomes active, from LockWindowPresenter's UIScene notification and
    /// RootView's scene phase: removes the privacy shield, re-reads biometry availability and, while
    /// locked, shows the unlock prompt once per return to the foreground. Safe to call twice: the
    /// flag and `authenticate()`'s `isAuthenticating` guard keep it to one prompt.
    func sceneDidBecomeActive() {
        unshield()
        refreshBiometryState()
        guard isLocked, !didAutoPrompt else { return }
        didAutoPrompt = true
        Task { await self.authenticate() }
    }

    /// Locks the UI if the lock is enabled. Called by `sceneDidEnterBackground()`.
    func lockIfEnabled() {
        guard isEnabled else { return }
        isLocked = true
        // The background snapshot is always opaque, even if the inactive shield was skipped because
        // a Face ID prompt was up when the user went home (the system cancels that prompt).
        isShielded = true
        errorMessage = nil
    }

    /// Covers the UI with the privacy shield if the lock is enabled. Called when the scene becomes
    /// inactive (app switcher, Control Center, Notification Center), from LockWindowPresenter
    /// (UIScene will-deactivate notification) and RootView (scene phase). Does nothing while the
    /// system authentication prompt is showing, because that prompt also makes the scene inactive.
    func shieldIfEnabled() {
        guard isEnabled, !isAuthenticating else { return }
        isShielded = true
    }

    /// Removes the privacy shield. Called by `sceneDidBecomeActive()`.
    func unshield() {
        isShielded = false
    }

    /// Asks the user to authenticate (biometrics, falling back to the device passcode) and unlocks
    /// on success. Never throws; failures are reported through `errorMessage`.
    @discardableResult
    func authenticate() async -> Bool {
        guard isLocked else { return true }
        guard !isAuthenticating else { return false }
        let reason = String(localized: "Unlock your documents.", comment: "Reason shown in the Face ID / passcode prompt when unlocking the app")
        switch await evaluate(reason: reason) {
        case .success:
            isLocked = false
            return true
        case .noPasscode:
            // Without a device passcode nothing can authenticate the owner; keeping the lock would
            // trap the user outside their own documents, so turn it off.
            errorMessage = nil
            storeEnabled(false)
            isLocked = false
            return true
        case .failed:
            return false
        }
    }

    /// Turns the lock on or off. Both directions require device-owner authentication (biometrics
    /// or passcode); turning it off is also allowed when the device has no passcode, so the owner
    /// can never be locked out. Returns whether the change was applied.
    func setEnabled(_ enabled: Bool) async -> Bool {
        if !enabled {
            guard isEnabled else {
                // Already off: nothing to confirm.
                isLocked = false
                errorMessage = nil
                return true
            }
            guard !isAuthenticating else { return false }
            let reason = String(localized: "Confirm it’s you to turn off the app lock.", comment: "Reason shown in the Face ID / passcode prompt when disabling the app lock")
            switch await evaluate(reason: reason) {
            case .success, .noPasscode:
                // .noPasscode: without a device passcode nothing can authenticate the owner, so
                // allow turning the lock off rather than trapping them.
                storeEnabled(false)
                isLocked = false
                isShielded = false
                // Clears the "Set a device passcode…" message evaluate() sets for .noPasscode.
                errorMessage = nil
                return true
            case .failed:
                // errorMessage was set by evaluate() (nil when the user cancelled).
                return false
            }
        }
        guard !isEnabled else { return true }
        guard !isAuthenticating else { return false }
        let reason = String(localized: "Confirm it’s you to turn on the app lock.", comment: "Reason shown in the Face ID / passcode prompt when enabling the app lock")
        guard await evaluate(reason: reason) == .success else { return false }
        storeEnabled(true)
        return true
    }

    // MARK: Private

    private enum Outcome { case success, noPasscode, failed }

    private func evaluate(reason: String) async -> Outcome {
        isAuthenticating = true
        errorMessage = nil
        defer { isAuthenticating = false }

        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            let code = error.flatMap { $0.domain == LAErrorDomain ? LAError.Code(rawValue: $0.code) : nil }
            errorMessage = Self.message(for: code)
            return code == .passcodeNotSet ? .noPasscode : .failed
        }
        do {
            let success = try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
            return success ? .success : .failed
        } catch let error as LAError {
            errorMessage = Self.message(for: error.code)
            return .failed
        } catch {
            errorMessage = Self.message(for: nil)
            return .failed
        }
    }

    private func storeEnabled(_ enabled: Bool) {
        isEnabled = enabled
        if persistsSetting { defaults.set(enabled, forKey: Self.enabledDefaultsKey) }
    }

    /// Message for a failed authentication; nil when the user simply cancelled.
    private static func message(for code: LAError.Code?) -> String? {
        switch code {
        case .userCancel?, .systemCancel?, .appCancel?:
            return nil
        case .passcodeNotSet?:
            return String(localized: "Set a device passcode in the Settings app to use the app lock.")
        case .biometryLockout?:
            return String(localized: "Biometrics are locked after too many attempts. Use your device passcode.")
        case .authenticationFailed?:
            return String(localized: "Authentication failed. Please try again.")
        default:
            return String(localized: "Authentication isn’t available right now. Please try again.")
        }
    }
}
