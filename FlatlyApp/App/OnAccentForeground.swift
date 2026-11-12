import SwiftUI

/// Draws a `.borderedProminent` button's or menu's label in `Color.onAccent`, so it stays readable
/// on the bright dark-mode accent. Apply it to the label *content* (the prominent style overrides
/// modifiers on the button but respects the label's own style). A disabled control keeps the
/// system's dimmed style.
struct OnAccentForeground: ViewModifier {
    @Environment(\.isEnabled) private var isEnabled

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled {
            content.foregroundStyle(Color.onAccent)
        } else {
            content
        }
    }
}

extension View {
    /// Draws this button label in `Color.onAccent`. Use on the label content of every
    /// `.borderedProminent` control.
    func onAccentForeground() -> some View {
        modifier(OnAccentForeground())
    }
}
