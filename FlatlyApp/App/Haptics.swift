import UIKit

/// Tiny wrapper around UIKit's feedback generators so call sites read as intent, not API.
/// All methods are no-ops on devices without a Taptic Engine.
@MainActor
enum Haptics {
    /// A task finished successfully (pages saved, signature placed).
    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    /// Something was destroyed (page or document deleted).
    static func warning() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }

    /// A light confirmation that an edit was applied (filter, rotation, crop, edges).
    static func lightImpact() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}
