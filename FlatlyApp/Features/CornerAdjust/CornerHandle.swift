import SwiftUI

/// Visual for a corner-adjust handle: a 24-pt circle (corners) or a short capsule aligned with
/// its edge (edge midpoints), inside a 44×44-pt hit area.
struct CornerHandle: View {
    enum Style { case corner, edge }

    var style: Style
    var isActive: Bool
    /// Rotation for edge handles so the capsule lies along the edge.
    var angle: Angle = .zero

    static let hitSize: CGFloat = 44

    var body: some View {
        Group {
            switch style {
            case .corner:
                Circle()
                    .fill(Color.accentColor.opacity(isActive ? 0.9 : 0.35))
                    .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                    .frame(width: 24, height: 24)
            case .edge:
                Capsule()
                    .fill(Color.accentColor.opacity(isActive ? 0.9 : 0.5))
                    .overlay(Capsule().strokeBorder(.white, lineWidth: 2))
                    .frame(width: 26, height: 10)
                    .rotationEffect(angle)
            }
        }
        .scaleEffect(isActive ? 1.2 : 1)
        .shadow(color: .black.opacity(0.4), radius: 2)
        .animation(.easeOut(duration: 0.15), value: isActive)
        .frame(width: Self.hitSize, height: Self.hitSize)
        .contentShape(Rectangle())
    }
}
