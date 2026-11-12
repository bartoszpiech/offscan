import UIKit

/// Receives Home Screen quick actions while the app is running (warm launch). SwiftUI still owns
/// the window; this delegate declares none.
final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    func windowScene(
        _ windowScene: UIWindowScene,
        performActionFor shortcutItem: UIApplicationShortcutItem,
        completionHandler: @escaping (Bool) -> Void
    ) {
        guard let action = QuickAction(shortcutItem: shortcutItem) else {
            completionHandler(false)
            return
        }
        // Something is presented over the app (a sheet, the camera, an alert): leave it alone and
        // just bring the app to the front. The lock window has its own level and is ignored here.
        let main = windowScene.windows.first { $0.windowLevel == .normal }
        if main?.rootViewController?.presentedViewController != nil {
            completionHandler(false)
            return
        }
        QuickActionInbox.shared.pending = action
        completionHandler(true)
    }
}
