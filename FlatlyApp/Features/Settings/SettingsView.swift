import SwiftUI
import FlatlyCore

/// App settings, presented as a sheet from the library.
struct SettingsView: View {
    @Environment(AppLockManager.self) private var lock
    @Environment(\.dismiss) private var dismiss
    /// Read by the scan/import flows to build the default `PageRenderRecipe`.
    @AppStorage("defaultFilter") private var defaultFilter: ScanFilter = .color
    /// Read by `ScanCaptureSheet` to choose between Offscan's camera and Apple's scanner.
    @AppStorage("cameraMode") private var cameraMode: CameraMode = .flatly
    /// Read by `CameraCaptureFlow`: show every page in the corner editor after scanning.
    @AppStorage("reviewEdgesAfterScan") private var reviewEdgesAfterScan = false

    @State private var lockToggle = false
    @State private var isUpdatingLock = false
    @State private var lockError: String?

    var body: some View {
        NavigationStack {
            Form {
                privacySection
                securitySection
                scanningSection
                advancedSection
                aboutSection
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("settings.doneButton")
                }
            }
            .onAppear {
                lock.refreshBiometryState()
                lockToggle = lock.isEnabled
            }
            .onChange(of: lockToggle) { _, newValue in
                updateLock(newValue)
            }
        }
    }

    // MARK: Sections

    /// First, so the promise is visible without scrolling.
    private var privacySection: some View {
        Section {
            Label("Everything is processed on your device. Offscan never connects to the internet.", systemImage: "lock.shield")
            Label("No ads, no subscriptions.", systemImage: "heart")
        } header: {
            Text("Privacy")
        }
    }

    private var securitySection: some View {
        Section {
            Toggle(isOn: $lockToggle) {
                Text(lockToggleTitle)
            }
            // Turning the lock off stays possible even when the device can no longer authenticate:
            // AppLockManager then applies it without a prompt (no passcode).
            .disabled(isUpdatingLock || (!lock.canAuthenticate && !lock.isEnabled))
            .accessibilityIdentifier("settings.lockToggle")
        } header: {
            Text("Security")
        } footer: {
            if let lockError {
                Text(lockError)
            } else if !lock.canAuthenticate {
                Text("Set a device passcode to use the app lock.")
            } else if !lock.canUseBiometrics {
                Text("Offscan locks when you leave the app and unlocks with your device passcode.")
            } else {
                Text("Offscan locks when you leave the app. Your device passcode works as a fallback.")
            }
        }
    }

    private var scanningSection: some View {
        Section {
            Picker("Default filter", selection: $defaultFilter) {
                ForEach(ScanFilter.allCases, id: \.self) { filter in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(filter.displayName)
                        Text(filter.summary)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                    .tag(filter)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
            .accessibilityIdentifier("settings.defaultFilterPicker")
        } header: {
            Text("Default filter")
        } footer: {
            Text("Applied to new scans and imports. You can change it for each page later.")
        }
    }

    /// Technical choices most people never change: which camera Scan opens and, for Offscan's
    /// camera, edge review. Every section has a header, so the spacing between them is even.
    private var advancedSection: some View {
        Section {
            Picker("Camera", selection: $cameraMode) {
                ForEach(CameraMode.allCases, id: \.self) { mode in
                    // Each option explains itself, like the default-filter rows.
                    VStack(alignment: .leading, spacing: 2) {
                        Text(mode.displayName)
                        Text(mode.summary)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                    .tag(mode)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
            .accessibilityIdentifier("settings.cameraModePicker")
            // Only for Offscan's camera (Apple's scanner has its own review).
            if cameraMode == .flatly {
                Toggle("Review edges after scanning", isOn: $reviewEdgesAfterScan)
                    .accessibilityIdentifier("settings.reviewEdgesToggle")
            }
        } header: {
            Text("Advanced")
        } footer: {
            if cameraMode == .flatly {
                Text("When off, pages with a detected document are saved right away. You can still adjust a page's edges later.")
            }
        }
    }

    private var aboutSection: some View {
        Section {
            LabeledContent("Version", value: versionString)
        } header: {
            Text("About")
        }
    }

    // MARK: Helpers

    private var lockToggleTitle: LocalizedStringKey {
        // Without biometrics the device passcode is what unlocks Offscan: name it plainly.
        guard lock.canUseBiometrics else { return "Require Passcode" }
        return switch lock.biometryType {
        case .faceID: "Require Face ID"
        case .touchID: "Require Touch ID"
        case .opticID: "Require Optic ID"
        default: "Require authentication"
        }
    }

    private var versionString: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "—"
        guard let build = info?["CFBundleVersion"] as? String else { return version }
        return "\(version) (\(build))"
    }

    private func updateLock(_ enabled: Bool) {
        guard enabled != lock.isEnabled else { return }
        isUpdatingLock = true
        lockError = nil
        Task {
            let applied = await lock.setEnabled(enabled)
            if !applied {
                lockError = lock.errorMessage
                lockToggle = lock.isEnabled
            }
            isUpdatingLock = false
        }
    }
}

#if DEBUG
struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
            .environment(AppLockManager())
    }
}
#endif
