import SwiftUI
import UIKit

extension Color {
    /// Foreground for text and glyphs drawn on an `accentColor` fill (prominent buttons, badges,
    /// handles). White on the light-mode accent #263B80 (10.4:1). Deep navy #131A33 on the bright
    /// dark-mode accent #A9B8F5 (8.9:1), where the system's white label reaches only 1.9:1.
    /// Keep in sync with AccentColor.colorset. Resolved from the environment's colour scheme, so it
    /// also works under a forced `.dark` (the camera).
    static let onAccent = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0x13 / 255.0, green: 0x1A / 255.0, blue: 0x33 / 255.0, alpha: 1)
            : .white
    })
}
