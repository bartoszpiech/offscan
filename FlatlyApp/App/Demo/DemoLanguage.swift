#if DEBUG
import Foundation

/// Language of the demo library content (`DemoLibraryContent`): Polish when the app runs in Polish,
/// English otherwise. Demo documents are page content, not UI copy, so they are plain strings and
/// never go through `Localizable.xcstrings`.
enum DemoLanguage: Sendable {
    case english, polish

    /// The language the app is shown in.
    static var current: DemoLanguage {
        (Bundle.main.preferredLocalizations.first ?? "en").hasPrefix("pl") ? .polish : .english
    }

    /// Picks the English or the Polish variant.
    func t(_ english: String, _ polish: String) -> String {
        self == .polish ? polish : english
    }

    var locale: Locale {
        Locale(identifier: self == .polish ? "pl_PL" : "en_US")
    }

    /// "October 14, 2026" / "14 października 2026".
    func longDate(_ date: Date) -> String {
        formatted(date, format: self == .polish ? "d MMMM yyyy" : "MMMM d, yyyy")
    }

    /// "Oct 14, 2026" / "14.10.2026".
    func shortDate(_ date: Date) -> String {
        formatted(date, format: self == .polish ? "dd.MM.yyyy" : "MMM d, yyyy")
    }

    /// "4:07 PM" / "16:07".
    func time(_ date: Date) -> String {
        formatted(date, format: self == .polish ? "HH:mm" : "h:mm a")
    }

    /// "1,234.56" / "1234,56" (two decimals, local separators).
    func amount(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(2)).locale(locale))
    }

    /// "$1,234.56" / "1234,56 zł".
    func money(_ value: Double) -> String {
        self == .polish ? "\(amount(value)) zł" : "$\(amount(value))"
    }

    private func formatted(_ date: Date, format: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateFormat = format
        return formatter.string(from: date)
    }
}
#endif
