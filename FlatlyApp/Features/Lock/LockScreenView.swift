import SwiftUI
import LocalAuthentication

/// Full-screen cover shown while the app is locked. While the scene is inactive (`isShielded`) it
/// is an opaque privacy shield instead: no unlock button and no material showing shapes through.
struct LockScreenView: View {
    @Environment(AppLockManager.self) private var lock
    @ScaledMetric(relativeTo: .largeTitle) private var glyphSize: CGFloat = 72

    var body: some View {
        ZStack {
            if lock.isShielded {
                Color(.systemBackground)
                    .ignoresSafeArea()
            } else {
                Rectangle()
                    .fill(.ultraThickMaterial)
                    .ignoresSafeArea()
            }

            VStack(spacing: 16) {
                Spacer()
                Image(systemName: "doc.viewfinder")
                    .font(.system(size: glyphSize, weight: .regular))
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                Text(verbatim: "Offscan")
                    .font(.largeTitle.bold())
                    .accessibilityAddTraits(.isHeader)
                // A Control Center pull while unlocked shows the shield without claiming a lock.
                if lock.isLocked {
                    Text("Your documents are locked.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                Spacer()

                // Kept in the layout (just hidden) while shielded, so nothing jumps when the
                // shield drops on return to the app.
                VStack(spacing: 16) {
                    if let message = lock.errorMessage {
                        Text(message)
                            .font(.callout)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .accessibilityIdentifier("lock.errorMessage")
                    }

                    Button {
                        Task { await lock.authenticate() }
                    } label: {
                        Label(unlockTitle, systemImage: unlockSymbol)
                            .font(.headline)
                            .onAccentForeground()
                            .frame(maxWidth: 360)
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .controlSize(.large)
                    .disabled(lock.isAuthenticating)
                    .accessibilityIdentifier("lock.unlockButton")
                }
                .opacity(lock.isShielded ? 0 : 1)
                .allowsHitTesting(!lock.isShielded)
                .accessibilityHidden(lock.isShielded)
            }
            .padding(32)
        }
    }

    private var unlockTitle: LocalizedStringKey {
        // Biometrics not enrolled or unavailable: the passcode is asked for instead.
        guard lock.canUseBiometrics else { return "Unlock" }
        return switch lock.biometryType {
        case .faceID: "Unlock with Face ID"
        case .touchID: "Unlock with Touch ID"
        case .opticID: "Unlock with Optic ID"
        default: "Unlock"
        }
    }

    private var unlockSymbol: String {
        guard lock.canUseBiometrics else { return "lock.open" }
        return switch lock.biometryType {
        case .faceID: "faceid"
        case .touchID: "touchid"
        case .opticID: "opticid"
        default: "lock.open"
        }
    }
}

#if DEBUG
struct LockScreenView_Previews: PreviewProvider {
    static var previews: some View {
        LockScreenView()
            .environment(AppLockManager())
    }
}
#endif
