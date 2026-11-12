import UIKit

/// Application delegate (`@UIApplicationDelegateAdaptor`), only for Home Screen quick actions:
/// a cold launch from a quick action delivers it with the scene's connection options, and the
/// scene delegate class set here receives the ones chosen while the app is running.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        if let item = options.shortcutItem, let action = QuickAction(shortcutItem: item) {
            QuickActionInbox.shared.pending = action
        }
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }
}
