import UIKit

/// Home Screen quick actions declared in Info.plist (`UIApplicationShortcutItems` in project.yml).
enum QuickAction: String, Sendable {
    /// "Scan Document": opens the camera from the library root.
    case scan = "flatly.quickaction.scan"

    init?(shortcutItem: UIApplicationShortcutItem) {
        self.init(rawValue: shortcutItem.type)
    }
}
