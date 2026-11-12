import XCTest

/// Smoke tests for the library screen. The app is launched with `FLATLY_UI_TESTING=1`, which
/// switches it to an in-memory store and disables the app lock, so every run starts empty.
final class FlatlyUITests: XCTestCase {
    private let timeout: TimeInterval = 10

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: - Tests

    @MainActor
    func testLaunchShowsEmptyLibrary() throws {
        let app = launchApp()
        XCTAssertTrue(
            element(in: app, id: "library.emptyState").waitForExistence(timeout: timeout),
            "The empty library state should be visible on a fresh launch."
        )
        XCTAssertTrue(
            element(in: app, id: "library.empty.importPhotos").waitForExistence(timeout: timeout),
            "The empty library should offer importing from Photos."
        )
        XCTAssertTrue(
            element(in: app, id: "library.empty.importFiles").waitForExistence(timeout: timeout),
            "The empty library should offer importing from Files."
        )
    }

    @MainActor
    func testSettingsOpensAndCloses() throws {
        let app = launchApp()
        let settingsButton = element(in: app, id: "settings.button")
        XCTAssertTrue(settingsButton.waitForExistence(timeout: timeout))
        settingsButton.tap()

        let lockToggle = element(in: app, id: "settings.lockToggle")
        let aboutText = app.staticTexts["About"].firstMatch
        let settingsShown = lockToggle.waitForExistence(timeout: timeout) || aboutText.exists
        XCTAssertTrue(settingsShown, "Settings should show the lock toggle or the About section.")

        let doneButton = app.buttons["Done"].firstMatch
        XCTAssertTrue(doneButton.waitForExistence(timeout: timeout))
        doneButton.tap()

        XCTAssertTrue(waitForDisappearance(of: doneButton), "Settings should be dismissed after tapping Done.")
        XCTAssertTrue(settingsButton.waitForExistence(timeout: timeout))
    }

    @MainActor
    func testAddMenuListsAllSources() throws {
        let app = launchApp()
        let addMenu = element(in: app, id: "library.addMenu")
        XCTAssertTrue(addMenu.waitForExistence(timeout: timeout))
        addMenu.tap()

        let sources = ["Scan with Camera", "Import from Photos", "Import from Files"]
        for title in sources {
            // The empty state has import buttons with the same titles: look at the menu only.
            let item = app.buttons.matching(NSPredicate(format: "label == %@ AND NOT (identifier BEGINSWITH %@)", title, "library.empty.")).firstMatch
            XCTAssertTrue(
                item.waitForExistence(timeout: timeout),
                "The add menu should offer \"\(title)\"."
            )
        }

        dismissMenu(in: app)
        XCTAssertTrue(
            waitForDisappearance(of: app.buttons[sources[0]].firstMatch),
            "The add menu should close without starting a scan."
        )
    }

    @MainActor
    func testStartupFailureShowsErrorScreen() throws {
        let app = launchApp(extraEnvironment: ["FLATLY_SIMULATE_STARTUP_FAILURE": "1"])
        XCTAssertTrue(
            element(in: app, id: "startupError.retry").waitForExistence(timeout: timeout),
            "A library that can't be opened should show the startup error screen, not crash."
        )
        XCTAssertFalse(element(in: app, id: "startupError.details").exists, "The error code should stay hidden until asked for.")
        element(in: app, id: "startupError.showDetails").tap()
        XCTAssertTrue(
            element(in: app, id: "startupError.details").waitForExistence(timeout: timeout),
            "Show Details should reveal the error code."
        )
    }

    /// The "Scan Document" Home Screen quick action (simulated in DEBUG with FLATLY_QUICK_ACTION)
    /// opens the scanner; the simulator has no camera, so that is the "Camera Not Available" screen.
    @MainActor
    func testScanQuickActionOpensScanner() throws {
        let app = launchApp(extraEnvironment: ["FLATLY_QUICK_ACTION": "scan"])
        XCTAssertTrue(
            element(in: app, id: "scan.unavailable").waitForExistence(timeout: timeout),
            "The scan quick action should open the scanner."
        )
        element(in: app, id: "scan.close").tap()
        XCTAssertTrue(
            element(in: app, id: "library.emptyState").waitForExistence(timeout: timeout),
            "Closing the scanner should return to the library."
        )
    }

    // MARK: - Helpers

    @MainActor
    private func launchApp(extraEnvironment: [String: String] = [:]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["FLATLY_UI_TESTING"] = "1"
        app.launchEnvironment.merge(extraEnvironment) { _, new in new }
        // Pin the UI language so string-based queries ("Done", "About", menu titles) are stable.
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        return app
    }

    /// Finds an element by accessibility identifier regardless of its element type
    /// (SwiftUI may expose a `Menu` as a button, a `Toggle` as a switch, etc.).
    @MainActor
    private func element(in app: XCUIApplication, id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    @MainActor
    private func dismissMenu(in app: XCUIApplication) {
        let cancel = app.buttons["Cancel"].firstMatch
        if cancel.exists && cancel.isHittable {
            cancel.tap()
        } else {
            // Tap the empty left half of the screen, outside the menu (which opens from the top
            // right). The status bar does not work: on iOS 26 a tap there leaves the menu open.
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.55)).tap()
        }
    }

    @MainActor
    private func waitForDisappearance(of element: XCUIElement) -> Bool {
        let gone = NSPredicate(format: "exists == false")
        let expectation = XCTNSPredicateExpectation(predicate: gone, object: element)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }
}
