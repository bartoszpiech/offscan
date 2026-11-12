import SwiftUI

/// The document's page count and creation date (plus "Recognizing text…" while OCR is pending),
/// shown above the page grid so the navigation bar only has to fit the title. No fixed sizes or
/// line limits: it wraps at large Dynamic Type sizes.
struct DocumentSummaryHeader: View {
    let pageCount: Int
    let createdAt: Date
    let isRecognizingText: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text("\(pageCount) pages")
                Text(verbatim: "·")
                    .accessibilityHidden(true)
                Text(createdAt.formatted(date: .abbreviated, time: .omitted))
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("document.pageCount")

            if isRecognizingText {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Recognizing text…")
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("document.ocrIndicator")
            }
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
