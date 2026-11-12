import SwiftUI

/// Grid cell for one page: thumbnail on a card with a page-number badge.
struct PageCardView: View {
    let page: ScanPage
    let number: Int

    var body: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Color(.secondarySystemGroupedBackground))
            .aspectRatio(3.0 / 4.0, contentMode: .fit)
            .overlay {
                PageImageView(page: page)
                    .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
                    .padding(8)
            }
            .overlay(alignment: .bottomTrailing) {
                Text(number, format: .number)
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.thinMaterial, in: Capsule())
                    .padding(6)
            }
            .overlay(alignment: .topTrailing) {
                if page.recipe.signature != nil {
                    Image(systemName: "signature")
                        .font(.caption)
                        .padding(5)
                        .background(.thinMaterial, in: Circle())
                        .padding(6)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Page \(number)"))
            .accessibilityAddTraits(.isButton)
    }
}
