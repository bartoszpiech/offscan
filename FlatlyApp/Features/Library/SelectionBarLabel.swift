import SwiftUI

/// An icon over a short caption, for the library's Select-mode bottom bar (Share, Move, Merge,
/// Delete). A `Label` renders icon-only in the iOS 26 bottom bar, so this spells out the caption.
///
/// Like UIKit tab and tool bars it stops growing, at `.xLarge`, so it fits the bar item (about
/// 44 pt tall); larger text sizes get the Large Content Viewer, which the button sets up. It has no
/// colours of its own: it inherits the toolbar's (or the button's) tint, so a disabled button still
/// dims and Delete stays red.
struct SelectionBarLabel: View {
    let title: Text
    let systemImage: String

    var body: some View {
        VStack(spacing: 2) {
            Image(systemName: systemImage)
                .font(.body)
                .imageScale(.medium)
                .accessibilityHidden(true)
            title
                .font(.caption2)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(minWidth: 44)
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
    }
}
