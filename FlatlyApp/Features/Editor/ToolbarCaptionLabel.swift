import SwiftUI

/// Body of `ToolbarCaptionLabelStyle`: the icon sits in a fixed-height, Dynamic-Type-scaled slot so
/// every tool's icon and first caption line share a baseline, whatever the symbol's height or the
/// caption's line count (with the bar's top alignment).
struct ToolbarCaptionLabel: View {
    let configuration: LabelStyleConfiguration
    @ScaledMetric(relativeTo: .title3) private var iconHeight: CGFloat = 28

    var body: some View {
        VStack(spacing: 4) {
            configuration.icon
                .font(.title3)
                .imageScale(.medium)
                .frame(height: iconHeight)
            configuration.title
                .font(.caption2)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .top)
        .contentShape(Rectangle())
    }
}
