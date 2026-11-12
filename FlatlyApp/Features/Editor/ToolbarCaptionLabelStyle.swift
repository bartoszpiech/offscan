import SwiftUI

/// Icon above a small caption, filling its share of a horizontal tool bar with a touch target of
/// at least 44 pt. The label's title stays the control's accessibility label. Icons share a
/// baseline thanks to the fixed icon slot (`ToolbarCaptionLabel`) plus the bar's top alignment.
struct ToolbarCaptionLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        ToolbarCaptionLabel(configuration: configuration)
    }
}

extension LabelStyle where Self == ToolbarCaptionLabelStyle {
    /// Icon over caption, for the editor's bottom tool bar.
    static var toolbarCaption: ToolbarCaptionLabelStyle { ToolbarCaptionLabelStyle() }
}
