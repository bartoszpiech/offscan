#if DEBUG
import Foundation

/// Folders of the demo library.
enum DemoFolder: CaseIterable, Sendable {
    case home, health

    func name(_ language: DemoLanguage) -> String {
        switch self {
        case .home: language.t("Home", "Dom")
        case .health: language.t("Health", "Zdrowie")
        }
    }
}
#endif
