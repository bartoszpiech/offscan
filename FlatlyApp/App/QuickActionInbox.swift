import Observation

/// Hands a Home Screen quick action from UIKit (`AppDelegate` on a cold launch, `SceneDelegate`
/// while running) to SwiftUI. A shared instance, because UIKit creates the scene delegate itself
/// and it can't reach SwiftUI state; injected with `.environment(QuickActionInbox.shared)`.
///
/// Only the root `LibraryView` consumes the action, and only while the app is unlocked, so the
/// camera never opens behind the lock screen.
@MainActor
@Observable
final class QuickActionInbox {
    static let shared = QuickActionInbox()

    /// Action waiting for the library to handle it; cleared by the consumer.
    var pending: QuickAction?
}
