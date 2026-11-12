import SwiftUI

/// Full-screen progress overlay used while captured or imported pages are processed,
/// e.g. "Processing page 2 of 5…". Shows a determinate bar when `fraction` is given, a Cancel
/// button when `onCancel` is given and a Stop button when `onStop` is given.
struct CaptureProgressView: View {
    let title: Text
    var fraction: Double?
    /// Shows a Cancel button (e.g. while imported PDF pages are prepared without review).
    var onCancel: (() -> Void)? = nil
    /// Shows a Stop button that keeps the pages processed so far (Apple-scanner batches).
    var onStop: (() -> Void)? = nil

    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground).ignoresSafeArea()
            VStack(spacing: 24) {
                VStack(spacing: 16) {
                    if let fraction {
                        ProgressView(value: fraction)
                            .progressViewStyle(.linear)
                            .frame(maxWidth: 240)
                    } else {
                        ProgressView().controlSize(.large)
                    }
                    title
                        .font(.headline)
                        .multilineTextAlignment(.center)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("capture.progress")

                // Outside the combined element, so VoiceOver still sees them as buttons.
                if let onCancel {
                    Button("Cancel", action: onCancel)
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("capture.progress.cancel")
                }
                if let onStop {
                    Button("Stop", action: onStop)
                        .buttonStyle(.bordered)
                        .accessibilityHint(Text("Keeps the pages processed so far."))
                        .accessibilityIdentifier("capture.stop")
                }
            }
            .padding()
        }
    }
}
