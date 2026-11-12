import SwiftUI

/// Dismissible tip shown above the page grid right after a scan or import: points out that pages
/// can be tapped to adjust their edges or filter.
struct EditHintBanner: View {
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "hand.tap")
                .font(.title3)
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text("Tap a page to adjust its edges or filter")
                .font(.subheadline)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Dismiss"))
            .accessibilityIdentifier("document.editHint.dismiss")
        }
        .padding(.leading, 14)
        .padding(.vertical, 2)
        .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("document.editHint")
    }
}
