import SwiftUI

/// Large processed page image that can be pinch-zoomed (1×–5×) and panned; double-tap toggles zoom.
/// Pages away from the editor's selection show their thumbnail instead (`showsFullImage`).
struct ZoomablePageView: View {
    let page: ScanPage
    /// False for pages away from the selection: they show the 400 px thumbnail instead of decoding
    /// the full page, so swiping through a long document does not keep one 2000 px image per
    /// visited page alive.
    var showsFullImage = true
    @Binding var scale: CGFloat

    @GestureState private var pinch: CGFloat = 1

    private static let range: ClosedRange<CGFloat> = 1...5

    var body: some View {
        GeometryReader { geo in
            let effective = clamp(scale * pinch)
            ScrollView([.horizontal, .vertical], showsIndicators: effective > 1.01) {
                // One view for both sizes, so its state carries over when the kind changes.
                PageImageView(page: page, kind: showsFullImage ? .processed : .thumb, maxDimension: showsFullImage ? 2000 : nil)
                    .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
                    .padding()
                    .frame(width: geo.size.width * effective, height: geo.size.height * effective)
            }
            .scrollDisabled(effective <= 1.01)
            .simultaneousGesture(
                MagnifyGesture()
                    .updating($pinch) { value, state, _ in state = value.magnification }
                    .onEnded { value in scale = clamp(scale * value.magnification) }
            )
            .onTapGesture(count: 2) {
                withAnimation(.easeInOut) { scale = scale > 1.01 ? 1 : 2.5 }
            }
        }
        .background(Color(.systemGroupedBackground))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Page \(page.index + 1)"))
        .accessibilityAddTraits(.isImage)
        .accessibilityZoomAction { action in
            switch action.direction {
            case .zoomIn: scale = clamp(scale * 1.5)
            case .zoomOut: scale = clamp(scale / 1.5)
            @unknown default: break
            }
        }
        .accessibilityIdentifier("editor.pageImage")
    }

    private func clamp(_ value: CGFloat) -> CGFloat {
        min(max(value, Self.range.lowerBound), Self.range.upperBound)
    }
}
