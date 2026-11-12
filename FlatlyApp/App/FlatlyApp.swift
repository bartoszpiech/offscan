import SwiftUI
import FlatlyCore

@main
struct FlatlyApp: App {
    /// Home Screen quick actions (`QuickActionInbox`).
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    /// Nil when the library couldn't be opened at launch; `StartupErrorView` is shown instead.
    @State private var services: AppServices?
    /// Localized description of the startup failure plus its error domain and code, shown in small
    /// print on `StartupErrorView` on demand ("Show Details").
    @State private var startupError: String?
    @State private var imageCache = ImageCache()
    @State private var lock = AppLockManager()

    init() {
        do {
            _services = State(initialValue: try Self.makeServices())
            _startupError = State(initialValue: nil)
        } catch {
            _services = State(initialValue: nil)
            _startupError = State(initialValue: Self.startupDetails(for: error))
        }
        #if DEBUG
        // UI tests of the "Scan Document" quick action.
        if ProcessInfo.processInfo.environment["FLATLY_QUICK_ACTION"] == "scan" {
            QuickActionInbox.shared.pending = .scan
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            if let services {
                RootView()
                    .environment(services)
                    .environment(services.store)
                    .environment(imageCache)
                    .environment(lock)
                    .environment(QuickActionInbox.shared)
            } else {
                StartupErrorView(details: startupError, retry: retryStartup)
            }
        }
    }

    /// Opens the library: in-memory under UI tests (`FLATLY_UI_TESTING=1`), persistent otherwise.
    private static func makeServices() throws -> AppServices {
        let environment = ProcessInfo.processInfo.environment
        #if DEBUG
        // UI tests of the startup error screen.
        if environment["FLATLY_SIMULATE_STARTUP_FAILURE"] == "1" { throw CocoaError(.fileWriteOutOfSpace) }
        #endif
        return environment["FLATLY_UI_TESTING"] == "1" ? try AppServices.makeEphemeral() : try AppServices.makeDefault()
    }

    /// "Try Again" on the startup error screen.
    private func retryStartup() {
        do {
            services = try Self.makeServices()
            startupError = nil
        } catch {
            startupError = Self.startupDetails(for: error)
        }
    }

    /// User-facing summary of a startup failure: the localized description (system-localized for
    /// Cocoa/SwiftData errors, Localizable.xcstrings for FlatlyCoreError) plus the error domain and
    /// code, and those of the underlying error if there is one, for support. Never the raw
    /// `String(describing:)` dump, which is English debug text that includes file paths.
    private static func startupDetails(for error: any Error) -> String {
        let ns = error as NSError
        var code = "\(ns.domain) \(ns.code)"
        if let underlying = ns.userInfo[NSUnderlyingErrorKey] as? NSError {
            code += ", \(underlying.domain) \(underlying.code)"
        }
        return "\(error.localizedDescription) (\(code))"
    }
}
