import SwiftUI

/// The camera's large round shutter. While a steady sheet counts down to an auto-capture, a ring
/// around it fills with `progress` (0...1).
struct ShutterButton: View {
    let progress: Double
    let isEnabled: Bool
    let action: () -> Void

    @ScaledMetric(relativeTo: .largeTitle) private var diameter: CGFloat = 72

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.9), lineWidth: 4)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.12), value: progress)
                Circle()
                    .fill(Color.white)
                    .padding(8)
            }
            .frame(width: diameter, height: diameter)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.4)
        .accessibilityLabel(Text("Take Photo"))
        .accessibilityIdentifier("camera.shutter")
    }
}
