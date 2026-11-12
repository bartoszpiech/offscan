import SwiftUI

/// Dims the content and shows a spinner with a label (and an optional Cancel button) while a
/// long operation runs. Apply with `.progressOverlay(isWorking, label: "…")`.
struct ProgressOverlay: ViewModifier {
    let isPresented: Bool
    let label: LocalizedStringKey
    var onCancel: (() -> Void)?

    func body(content: Content) -> some View {
        content
            .disabled(isPresented)
            .overlay {
                if isPresented {
                    ZStack {
                        Color.black.opacity(0.25)
                            .ignoresSafeArea()
                            .accessibilityHidden(true)
                        VStack(spacing: 12) {
                            ProgressView()
                                .controlSize(.large)
                            Text(label)
                                .font(.headline)
                                .multilineTextAlignment(.center)
                            if let onCancel {
                                Button("Cancel", role: .cancel, action: onCancel)
                                    .buttonStyle(.bordered)
                                    .accessibilityIdentifier("progress.cancelButton")
                            }
                        }
                        .padding(24)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .padding(32)
                        .accessibilityElement(children: .contain)
                        .accessibilityAddTraits(.isModal)
                    }
                    .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: isPresented)
    }
}

extension View {
    /// Shows a modal progress overlay while `isPresented` is true.
    func progressOverlay(_ isPresented: Bool, label: LocalizedStringKey, onCancel: (() -> Void)? = nil) -> some View {
        modifier(ProgressOverlay(isPresented: isPresented, label: label, onCancel: onCancel))
    }
}
