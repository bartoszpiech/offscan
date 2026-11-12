import XCTest

/// Captures every main screen as a screenshot attachment kept on success ("01-library",
/// "02-add-menu", …), for the screenshot job in `.github/workflows/ios-build.yml`
/// (`scripts/ui-screenshots.sh`), which renames them to `<lang>-<appearance>-<name>.png`.
///
/// The app is launched with `FLATLY_UI_TESTING=1` (in-memory store, no app lock) and
/// `FLATLY_DEMO_DATA=1`, which makes DEBUG builds seed a demo library (`DemoLibrarySeeder`).
/// The UI language comes from `FLATLY_SCREENSHOT_LANG` (`en`, the default, or `pl`); xcodebuild
/// passes it to the test runner when it is set as `TEST_RUNNER_FLATLY_SCREENSHOT_LANG`. Light or
/// dark is the simulator's appearance (`xcrun simctl ui <device> appearance dark`).
///
/// Elements are found by accessibility identifier, or by the demo titles from
/// `DemoLibraryContent`, so the same tests run in both languages. Every test launches the app
/// afresh (seeding takes a few seconds) and captures one screen, or a few screens reached one
/// after another without going back. A screen is captured even when the element it waits for
/// never appears, and the test fails afterwards, so a broken screen still shows up in the
/// artifact.
final class ScreenshotTests: XCTestCase {
    private let timeout: TimeInterval = 20
    /// Seeding renders and processes ~15 pages; give a slow CI simulator time for it.
    private let seedTimeout: TimeInterval = 90
    private let language = Language.current

    /// The language the app is launched in.
    private enum Language: String {
        case en, pl

        static var current: Language {
            Language(rawValue: ProcessInfo.processInfo.environment["FLATLY_SCREENSHOT_LANG"] ?? "") ?? .en
        }

        var launchArguments: [String] {
            switch self {
            case .en: ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
            case .pl: ["-AppleLanguages", "(pl)", "-AppleLocale", "pl_PL"]
            }
        }

        func t(_ english: String, _ polish: String) -> String {
            self == .pl ? polish : english
        }
    }

    /// Title prefixes of demo documents and folders (see `DemoLibraryContent`).
    private var leaseTitle: String { language.t("Lease agreement", "Umowa najmu") }
    private var invoiceTitle: String { language.t("Invoice", "Faktura") }
    private var healthFolder: String { language.t("Health", "Zdrowie") }
    private var receiptTitle: String { language.t("Receipt", "Paragon") }
    private var libraryCardTitle: String { language.t("Library card", "Karta biblioteczna") }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: - Library

    @MainActor
    func test01LibraryAndFolder() throws {
        let app = launch()
        waitForLibrary(app)
        capture("01-library", in: app, after: ["library.documentCard"])
        let folder = element(id: "library.folderRow", labelPrefix: healthFolder, in: app)
        XCTAssertTrue(folder.waitForExistence(timeout: timeout), "The \(healthFolder) folder should be listed.")
        folder.tap()
        _ = app.navigationBars[healthFolder].waitForExistence(timeout: timeout)
        capture("04-folder", in: app, after: ["library.documentCard"])
    }

    @MainActor
    func test02AddMenu() throws {
        let app = launch()
        waitForLibrary(app)
        tap("library.addMenu", in: app)
        let scanItem = app.buttons.matching(predicate(id: "library.add.scan", label: language.t("Scan with Camera", "Skanuj aparatem"))).firstMatch
        let shown = scanItem.waitForExistence(timeout: timeout)
        settle()
        snapshot("02-add-menu")
        XCTAssertTrue(shown, "The add menu should list the scan item.")
    }

    @MainActor
    func test03Search() throws {
        let app = launch()
        waitForLibrary(app)
        let field = searchField(in: app)
        field.tap()
        field.typeText(language.t("total", "razem") + "\n")
        capture("03-search", in: app, after: ["library.searchScopeCaption", "library.searchResult"])
        XCTAssertTrue(element(id: "library.searchResult", in: app).exists, "Search results should be listed as rows.")
    }

    /// Select mode, then merging the invoice (2 pages) and the library card (2 pages).
    @MainActor
    func test17LibrarySelectAndMerge() throws {
        let app = launch()
        waitForLibrary(app)
        tap("library.selectButton", in: app)
        // Checked now, asserted after the capture, so a failure still produces the screenshot.
        let foldersHidden = waitForDisappearance(of: element(id: "library.folderRow", in: app), timeout: 5)
        tapCard(invoiceTitle, in: app)
        let mergeID = "library.bulk.merge"
        let merge = element(id: mergeID, in: app)
        let mergeDisabledForOne = merge.waitForExistence(timeout: timeout) && waitForDisabled(mergeID, in: app, timeout: 5)
        if !mergeDisabledForOne {
            // For the CI log: every element carrying the identifier, with its type and flags.
            print(app.descendants(matching: .any).matching(identifier: mergeID).debugDescription)
        }
        tapCard(libraryCardTitle, in: app)
        // The invoice was selected first, so its card is numbered 1 (its accessibility value says so).
        let invoiceCard = element(id: "library.documentCard", labelPrefix: invoiceTitle, in: app)
        let firstInSelection = language.t("number 1 in the selection", "numer 1 w zaznaczeniu")
        let numberedFirst = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value CONTAINS %@", firstInSelection), object: invoiceCard)
        let invoiceNumbered = XCTWaiter().wait(for: [numberedFirst], timeout: 5) == .completed
        let invoiceValue = invoiceCard.exists ? ((invoiceCard.value as? String) ?? "") : "(no card)"
        capture("17-library-select", in: app, after: [mergeID])
        XCTAssertTrue(invoiceNumbered, "The invoice card should be number 1 in the selection (value: \(invoiceValue)).")
        let mergeStatesForTwo = enabledStates(of: mergeID, in: app)
        let oneSelected = mergeDisabledForOne ? "some disabled" : "none disabled"
        print("Merge enabled states: one selected → \(oneSelected), two selected → \(mergeStatesForTwo)")
        XCTAssertTrue(foldersHidden, "Folders should hide in Select mode.")
        XCTAssertTrue(mergeDisabledForOne, "Merge should need two documents.")
        XCTAssertTrue(!mergeStatesForTwo.isEmpty && !mergeStatesForTwo.contains(false),
                      "Merge should be enabled with two documents selected.")
        tap("library.bulk.merge", in: app)
        // The dialog isn't captured: checked now, asserted after the next capture.
        let mergeTitled = app.staticTexts[language.t("Merge 2 documents?", "Połączyć 2 dokumenty?")].waitForExistence(timeout: timeout)
        let rawMarkup = rawMarkupCount(in: app)
        tap("library.confirmMerge", in: app)
        XCTAssertTrue(element(id: "document.pageCard.4", in: app).waitForExistence(timeout: timeout),
                      "The merged invoice should have 4 pages.")
        capture("18-merged-document", in: app, after: ["document.pageCard.4"])
        XCTAssertTrue(mergeTitled, "The Merge confirmation should be titled with the document count.")
        XCTAssertEqual(rawMarkup, 0, "No label may show raw inflection markup.")
    }

    /// Select mode, then deleting the receipt and the library card, which go to Recently Deleted.
    /// There the receipt is restored and the library card deleted for good (Delete All).
    @MainActor
    func test19LibraryBulkDelete() throws {
        let app = launch()
        waitForLibrary(app)
        tap("library.selectButton", in: app)
        tapCard(receiptTitle, in: app)
        tapCard(libraryCardTitle, in: app)
        tap("library.bulk.delete", in: app)
        capture("19-bulk-delete-confirm", in: app, after: ["library.confirmBulkDelete"])
        XCTAssertTrue(app.staticTexts[language.t("Delete 2 documents?", "Usunąć 2 dokumenty?")].waitForExistence(timeout: 5),
                      "The Delete confirmation should be titled with the document count.")
        assertNoRawMarkup(in: app)
        tap("library.confirmBulkDelete", in: app)
        XCTAssertTrue(waitForDisappearance(of: element(id: "library.documentCard", labelPrefix: receiptTitle, in: app), timeout: timeout),
                      "The receipt should be deleted.")
        XCTAssertTrue(element(id: "library.documentCard", labelPrefix: leaseTitle, in: app).exists,
                      "The lease should still be in the library.")

        // Recently Deleted is the last row of the Folders section.
        tap("library.recentlyDeletedRow", in: app)
        capture("28-recently-deleted", in: app, after: ["recentlyDeleted.row", "recentlyDeleted.restoreAll"])
        let rowID = "recentlyDeleted.row"
        // Distinct titles: a row may be exposed together with a wrapper carrying its identifier.
        let deletedTitles = Set(app.descendants(matching: .any).matching(identifier: rowID).allElementsBoundByIndex.map { $0.label })
        XCTAssertEqual(deletedTitles.count, 2, "Recently Deleted should list both documents (found \(deletedTitles)).")
        let daysLeft = language.t("30 days left", "Zostało 30 dni")
        let showsDaysLeft = NSPredicate(format: "value == %@ OR label CONTAINS %@", daysLeft, daysLeft)
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: rowID).matching(showsDaysLeft).firstMatch.exists,
                      "A document deleted just now should have 30 days left.")
        assertNoRawMarkup(in: app)

        // Restore the receipt.
        let receiptRow = element(id: rowID, labelPrefix: receiptTitle, in: app)
        XCTAssertTrue(receiptRow.waitForExistence(timeout: timeout), "The receipt should be in Recently Deleted.")
        receiptRow.tap()
        tap("recentlyDeleted.restore", in: app)
        XCTAssertTrue(waitForDisappearance(of: receiptRow, timeout: timeout), "The receipt should leave Recently Deleted.")
        let leftTitles = Set(app.descendants(matching: .any).matching(identifier: rowID).allElementsBoundByIndex.map { $0.label })
        XCTAssertEqual(leftTitles.count, 1, "Only the library card should be left (found \(leftTitles)).")

        // Delete the rest for good.
        tap("recentlyDeleted.deleteAll", in: app)
        tap("recentlyDeleted.confirmDeleteAll", in: app)
        XCTAssertTrue(element(id: "recentlyDeleted.emptyState", in: app).waitForExistence(timeout: timeout),
                      "Recently Deleted should be empty after Delete All.")

        // Back in the library: the receipt is back (in Recent, or the grid), and the empty
        // Recently Deleted row is gone.
        app.navigationBars.buttons.firstMatch.tap()
        let restored = NSPredicate(format: "identifier IN %@ AND label BEGINSWITH %@", ["library.documentCard", "library.recentCard"], receiptTitle)
        XCTAssertTrue(app.descendants(matching: .any).matching(restored).firstMatch.waitForExistence(timeout: timeout),
                      "The restored receipt should be back in the library.")
        XCTAssertTrue(waitForDisappearance(of: element(id: "library.recentlyDeletedRow", in: app), timeout: 5),
                      "Recently Deleted should be hidden once it is empty.")
    }

    // MARK: - Document and page editor

    @MainActor
    func test05DocumentAndText() throws {
        let app = launch()
        openDocument(leaseTitle, in: app)
        capture("05-document", in: app, after: ["document.pageCard.4", "document.addPagesTile"])
        tap("document.textButton", in: app)
        capture("12-ocr-text", in: app, after: ["ocr.textList", "ocr.page.1"])
        // Copy All and Share sit in the bottom bar; only the More menu is in the top bar.
        XCTAssertTrue(element(id: "ocr.copyButton", in: app).isHittable, "Copy All should be in the bottom bar.")
        XCTAssertTrue(element(id: "ocr.shareButton", in: app).isHittable, "Share should be in the bottom bar.")
        XCTAssertFalse(app.navigationBars.descendants(matching: .any).matching(identifier: "ocr.copyButton").firstMatch.exists,
                       "Copy must not be in the top bar.")
        // The pasteboard isn't read back: that would show the paste permission prompt.
        tap("ocr.copyButton", in: app)
        XCTAssertTrue(element(id: "ocr.copyButton", in: app).waitForExistence(timeout: timeout), "Copying should keep the screen up.")
    }

    /// Page editor, then the filter strip opened on it, then the crop screen.
    @MainActor
    func test06EditorFilterCrop() throws {
        let app = launch()
        openPage(1, ofDocument: leaseTitle, in: app)
        capture("06-page-editor", in: app, after: ["editor.pageImage"])
        tap("editor.filterButton", in: app)
        capture("07-filter-picker", in: app, after: ["editor.filter.blackAndWhite", "editor.filterCaption"])
        tap("editor.cropButton", in: app)
        capture("08-crop", in: app, after: ["crop.doneButton", "crop.area", "crop.instruction"])
        XCTAssertTrue(element(id: "crop.instruction", in: app).exists, "Crop should explain what its handles do.")
    }

    /// Apply to All: after Black & White on page 1, every page takes that filter.
    @MainActor
    func test06bFilterApplyToAll() throws {
        let app = launch()
        openPage(1, ofDocument: leaseTitle, in: app)
        tap("editor.filterButton", in: app)
        tap("editor.filter.blackAndWhite", in: app)
        capture("22-filter-apply-all", in: app, after: ["editor.applyFilterToAllButton"])
        tap("editor.applyFilterToAllButton", in: app)
        // Every page now matches, so the button goes away once the bulk apply finished.
        XCTAssertTrue(waitForDisappearance(of: element(id: "editor.applyFilterToAllButton", in: app), timeout: 60),
                      "Apply to All should finish and hide its button.")
        tap("editor.nextPageButton", in: app)
        let blackAndWhite = element(id: "editor.filter.blackAndWhite", in: app)
        XCTAssertTrue(blackAndWhite.waitForExistence(timeout: timeout))
        XCTAssertTrue(blackAndWhite.isSelected, "Page 2 should use Black & White after Apply to All.")
    }

    /// Page editor with the filter strip at the largest accessibility text size: the tool bar and
    /// strip stop growing at xxxLarge.
    @MainActor
    func test21EditorLargeText() throws {
        let app = launch(arguments: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        openPage(1, ofDocument: leaseTitle, in: app)
        tap("editor.filterButton", in: app)
        capture("21-editor-large-text", in: app, after: ["editor.filter.blackAndWhite", "editor.filterCaption"])
        // Four equal tiles spanning the row (names wrap instead of shrinking).
        let first = element(id: "editor.filter.original", in: app).frame
        let last = element(id: "editor.filter.blackAndWhite", in: app).frame
        XCTAssertEqual(first.width, last.width, accuracy: 2, "Filter tiles should be equal width.")
        XCTAssertGreaterThan(last.maxX, app.windows.firstMatch.frame.width * 0.85, "Filter tiles should span the row.")
    }

    /// The invoice's first page was imported from a desk photo, so this shows the photo with the
    /// detected outline.
    @MainActor
    func test09CornerAdjust() throws {
        let app = launch()
        openPage(1, ofDocument: invoiceTitle, in: app)
        tap("editor.adjustEdgesButton", in: app)
        capture("09-corner-adjust", in: app, after: ["corner.done", "corner.reset", "corner.instruction"])
        XCTAssertTrue(element(id: "corner.instruction", in: app).exists, "Adjust Edges should explain what its handles do.")
    }

    /// In demo mode the canvas starts with a sample signature (see `SignatureCanvasView`).
    @MainActor
    func test10SignatureCanvas() throws {
        let app = launch()
        openPage(1, ofDocument: leaseTitle, in: app)
        tap("editor.signButton", in: app)
        capture("10-signature-canvas", in: app, after: ["signature.doneButton"])
        let offersSaving = element(id: "signature.saveAsMineToggle", in: app).exists
        // Not tapped, so the screenshots keep showing the blue default.
        let offersInk = element(id: "signature.ink.blue", in: app).exists
        tap("signature.doneButton", in: app)
        capture("11-signature-placement", in: app, after: ["signature.overlay", "signature.placeButton"])
        XCTAssertTrue(offersSaving, "The canvas should offer to save the signature.")
        XCTAssertTrue(offersInk, "The canvas should offer ink colours.")
    }

    @MainActor
    func test13ExportSheet() throws {
        let app = launch()
        openExportSheet(leaseTitle, in: app)
        capture("13-export-sheet", in: app, after: ["export.formatPicker", "export.doneButton"])
    }

    /// The export sheet's PDF password screen before typing (iOS leaves secure-field text out of
    /// screen captures, so filled fields would look empty; the placeholders show what they are for),
    /// then both fields filled in and the sheet with the password set.
    @MainActor
    func test13cExportPassword() throws {
        let app = launch()
        openExportSheet(leaseTitle, in: app)
        tap("export.passwordRow", in: app)
        capture("29-export-password", in: app, after: ["export.password.field", "export.password.confirmField"])
        tap("export.password.field", in: app)
        element(id: "export.password.field", in: app).typeText("flatly")
        tap("export.password.confirmField", in: app)
        element(id: "export.password.confirmField", in: app).typeText("flatly")
        XCTAssertTrue(waitForEnabled("export.password.setButton", in: app, timeout: 5),
                      "Set Password should be enabled once both fields match.")
        tap("export.password.setButton", in: app)
        let row = element(id: "export.passwordRow", in: app)
        XCTAssertTrue(row.waitForExistence(timeout: timeout), "The export sheet should show the password row again.")
        let on = language.t("On", "Włączone")
        // A LabeledContent row: "On" may be its value rather than part of its label.
        let showsOn = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", on, on), object: row)
        XCTAssertTrue(XCTWaiter().wait(for: [showsOn], timeout: timeout) == .completed,
                      "The password row should say the password is on (label: \(row.label)).")
    }

    /// The document's More menu: Add Pages, Rename, Move to Folder…, Reorder, Export Options…, Delete.
    @MainActor
    func test13bDocumentMoreMenu() throws {
        let app = launch()
        openDocument(leaseTitle, in: app)
        tap("document.moreMenu", in: app)
        capture("23-document-more-menu", in: app, after: ["document.moveToFolderButton"])
    }

    // MARK: - Other screens

    @MainActor
    func test14Settings() throws {
        let app = launch()
        waitForLibrary(app)
        tap("settings.button", in: app)
        capture("14-settings", in: app, after: ["settings.doneButton", "settings.lockToggle"])
        // Scrolled down to the advanced settings (edge review, camera mode).
        let form = app.collectionViews.firstMatch
        for _ in 0..<3 where !(element(id: "settings.reviewEdgesToggle", in: app).exists && element(id: "settings.reviewEdgesToggle", in: app).isHittable) {
            form.swipeUp()
        }
        capture("27-settings-advanced", in: app, after: ["settings.reviewEdgesToggle", "settings.cameraModePicker"])
    }

    /// The simulator has no camera; with the demo library the Offscan camera runs on a demo still
    /// (`DemoCameraFeed`): a letter on a desk with the live outline and the stability ring.
    @MainActor
    func test15Camera() throws {
        let app = launch()
        waitForLibrary(app)
        tap("library.scanButton", in: app)
        let outlined = detectedViewfinder(in: app).waitForExistence(timeout: timeout)
        capture("15-camera", in: app, after: ["camera.viewfinder"])
        XCTAssertTrue(outlined, "The camera should outline the demo sheet.")
        XCTAssertFalse(element(id: "scan.unavailable", in: app).exists, "The demo feed should replace “Camera Not Available”.")
    }

    /// The demo camera after a shutter tap: the Scanned Pages sheet with the captured page.
    @MainActor
    func test15bCameraScannedPages() throws {
        let app = launch()
        waitForLibrary(app)
        tap("library.scanButton", in: app)
        let outlined = detectedViewfinder(in: app).waitForExistence(timeout: timeout)
        tap("camera.shutter", in: app)
        tap("camera.thumbnail", in: app)
        capture("26-scanned-pages", in: app, after: ["camera.pages.keepScanning", "camera.pages.finish"])
        XCTAssertTrue(outlined, "The camera should outline the demo sheet.")
        XCTAssertTrue(element(id: "camera.pages.delete", in: app).exists, "The sheet should list the captured page.")
    }

    /// Finish on the Scanned Pages sheet saves the scan and closes the camera. The demo detection
    /// is a segmentation, so the page is accepted without the corner review. No screenshot.
    @MainActor
    func test15cCameraFinishFromPagesSheet() throws {
        let app = launch()
        waitForLibrary(app)
        tap("library.scanButton", in: app)
        XCTAssertTrue(detectedViewfinder(in: app).waitForExistence(timeout: timeout), "The camera should outline the demo sheet.")
        tap("camera.shutter", in: app)
        tap("camera.thumbnail", in: app)
        let finish = element(id: "camera.pages.finish", in: app)
        let finishReady = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true AND enabled == true"), object: finish)
        XCTAssertTrue(XCTWaiter().wait(for: [finishReady], timeout: timeout) == .completed,
                      "The Scanned Pages sheet should offer Finish once the page is processed.")
        finish.tap()
        XCTAssertTrue(waitForDisappearance(of: element(id: "camera.viewfinder", in: app), timeout: timeout),
                      "Finish should save the scan and close the camera.")
    }

    @MainActor
    func test16EmptyLibrary() throws {
        let app = launch(demoData: false)
        capture("16-empty-library", in: app, after: ["library.emptyState"])
    }

    /// The library can't be opened at launch (simulated in DEBUG with FLATLY_SIMULATE_STARTUP_FAILURE),
    /// then the same screen with the error details shown.
    @MainActor
    func test20StartupError() throws {
        let app = launch(demoData: false, environment: ["FLATLY_SIMULATE_STARTUP_FAILURE": "1"])
        capture("20-startup-error", in: app, after: ["startupError.retry"])
        let detailsHidden = !element(id: "startupError.details", in: app).exists
        tap("startupError.showDetails", in: app)
        capture("24-startup-error-details", in: app, after: ["startupError.details"])
        XCTAssertTrue(detailsHidden, "The error code should stay hidden until asked for.")
    }

    /// The startup error screen at the largest accessibility text size: it scrolls.
    @MainActor
    func test20bStartupErrorLargeText() throws {
        let app = launch(
            demoData: false,
            environment: ["FLATLY_SIMULATE_STARTUP_FAILURE": "1"],
            arguments: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        )
        capture("25-startup-error-large-text", in: app, after: ["startupError.retry"])
    }

    // MARK: - Navigation

    /// Launches the app in the test language; `environment` and `arguments` are added on top.
    @MainActor
    private func launch(demoData: Bool = true, environment: [String: String] = [:], arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["FLATLY_UI_TESTING"] = "1"
        if demoData { app.launchEnvironment["FLATLY_DEMO_DATA"] = "1" }
        app.launchEnvironment.merge(environment) { _, new in new }
        app.launchArguments += language.launchArguments
        app.launchArguments += arguments
        app.launch()
        return app
    }

    /// Waits until the seeded documents are listed.
    @MainActor
    private func waitForLibrary(_ app: XCUIApplication) {
        // At accessibility text sizes the Recent strip and the folders push the grid off screen,
        // and lazy grid cells don't exist until shown: a Recent card counts too.
        let ids = ["library.documentCard", "library.recentCard"]
        let card = app.descendants(matching: .any).matching(NSPredicate(format: "identifier IN %@", ids)).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: seedTimeout), "The demo library should be seeded (FLATLY_DEMO_DATA=1).")
    }

    @MainActor
    private func openDocument(_ titlePrefix: String, in app: XCUIApplication) {
        waitForLibrary(app)
        var card = element(id: "library.documentCard", labelPrefix: titlePrefix, in: app)
        if !card.waitForExistence(timeout: 3) {
            card = element(id: "library.recentCard", labelPrefix: titlePrefix, in: app)
        }
        XCTAssertTrue(card.waitForExistence(timeout: timeout), "The document “\(titlePrefix)…” should be in the library.")
        card.tap()
        XCTAssertTrue(element(id: "document.pageCard.1", in: app).waitForExistence(timeout: timeout), "The document's pages should be shown.")
    }

    @MainActor
    private func openPage(_ number: Int, ofDocument titlePrefix: String, in app: XCUIApplication) {
        openDocument(titlePrefix, in: app)
        tap("document.pageCard.\(number)", in: app)
        XCTAssertTrue(element(id: "editor.filterButton", in: app).waitForExistence(timeout: timeout), "The page editor should open.")
    }

    /// Opens the document's export sheet from its More menu.
    @MainActor
    private func openExportSheet(_ titlePrefix: String, in app: XCUIApplication) {
        openDocument(titlePrefix, in: app)
        tap("document.moreMenu", in: app)
        let item = app.buttons.matching(predicate(id: "document.moreExportOptions", label: language.t("Export Options…", "Opcje eksportu…"))).firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: timeout), "The More menu should offer the export options.")
        item.tap()
    }

    /// Taps the library grid card whose title starts with `titlePrefix`.
    @MainActor
    private func tapCard(_ titlePrefix: String, in app: XCUIApplication) {
        let card = element(id: "library.documentCard", labelPrefix: titlePrefix, in: app)
        XCTAssertTrue(card.waitForExistence(timeout: timeout), "The document “\(titlePrefix)…” should be in the library.")
        card.tap()
    }

    /// The camera viewfinder once it reports a detected sheet (its accessibility value).
    @MainActor
    private func detectedViewfinder(in app: XCUIApplication) -> XCUIElement {
        let detected = NSPredicate(format: "identifier == %@ AND value == %@", "camera.viewfinder", language.t("Document detected", "Wykryto dokument"))
        return app.descendants(matching: .any).matching(detected).firstMatch
    }

    /// The library's search field. Depending on the iOS version it sits in the navigation bar
    /// (possibly scrolled away) or in a toolbar; reveal it if needed.
    @MainActor
    private func searchField(in app: XCUIApplication) -> XCUIElement {
        let field = app.searchFields.firstMatch
        if field.waitForExistence(timeout: 5), field.isHittable { return field }
        let list = app.scrollViews.firstMatch
        if list.exists { list.swipeDown() }
        if field.waitForExistence(timeout: 3), field.isHittable { return field }
        let searchButton = app.buttons.matching(predicate(id: "Search", label: language.t("Search", "Szukaj"))).firstMatch
        if searchButton.exists { searchButton.tap() }
        XCTAssertTrue(field.waitForExistence(timeout: timeout), "The library should have a search field.")
        return field
    }

    // MARK: - Helpers

    /// Finds an element by accessibility identifier regardless of its type (SwiftUI may expose a
    /// `Menu` as a button, a `ScrollView` as a scroll view, etc.).
    @MainActor
    private func element(id: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    /// An element with identifier `id` whose label starts with `labelPrefix` (document cards and
    /// folder rows are labelled with their title).
    @MainActor
    private func element(id: String, labelPrefix: String, in app: XCUIApplication) -> XCUIElement {
        let titled = NSPredicate(format: "label BEGINSWITH %@", labelPrefix)
        let button = app.buttons.matching(identifier: id).matching(titled).firstMatch
        if button.waitForExistence(timeout: 2) { return button }
        return app.descendants(matching: .any).matching(identifier: id).matching(titled).firstMatch
    }

    /// Fails if any element's label shows unresolved automatic grammar agreement markup
    /// ("Delete ^[2 document](inflect: true)?"), which confirmation dialog titles don't resolve.
    @MainActor
    private func assertNoRawMarkup(in app: XCUIApplication) {
        XCTAssertEqual(rawMarkupCount(in: app), 0, "No label may show raw inflection markup.")
    }

    /// How many elements' labels contain "^[" (unresolved inflection markup).
    @MainActor
    private func rawMarkupCount(in app: XCUIApplication) -> Int {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "^[")).count
    }

    private func predicate(id: String, label: String) -> NSPredicate {
        NSPredicate(format: "identifier == %@ OR label == %@", id, label)
    }

    @MainActor
    private func tap(_ id: String, in app: XCUIApplication) {
        let target = element(id: id, in: app)
        XCTAssertTrue(target.waitForExistence(timeout: timeout), "“\(id)” should appear.")
        target.tap()
    }

    /// Waits for any of `ids`, lets images load and animations finish, saves the screenshot, then
    /// fails the test if none of the elements appeared.
    @MainActor
    private func capture(_ name: String, in app: XCUIApplication, after ids: [String]) {
        let deadline = Date().addingTimeInterval(timeout)
        var shown = false
        while !shown && Date() < deadline {
            shown = ids.contains { element(id: $0, in: app).exists }
            if !shown { pause(0.5) }
        }
        waitForImages(in: app)
        settle()
        snapshot(name)
        XCTAssertTrue(shown, "\(name): none of \(ids) appeared.")
    }

    /// Waits (up to `timeout`) until no spinner is showing, i.e. thumbnails, pages and filter
    /// previews have loaded.
    @MainActor
    private func waitForImages(in app: XCUIApplication) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if app.activityIndicators.count == 0 && app.progressIndicators.count == 0 { return }
            pause(0.5)
        }
    }

    /// `isEnabled` of every element with identifier `id`. On iOS 26 a toolbar button with a custom
    /// label (the Select-mode bar's `SelectionBarLabel`) can be exposed together with a wrapper that
    /// carries the same identifier and always reports enabled, so `firstMatch` alone may not be the
    /// button whose state is checked.
    @MainActor
    private func enabledStates(of id: String, in app: XCUIApplication) -> [Bool] {
        app.descendants(matching: .any).matching(identifier: id).allElementsBoundByIndex.map { $0.isEnabled }
    }

    /// Polls until some element with identifier `id` reports disabled (true) or `timeout` passes.
    @MainActor
    private func waitForDisabled(_ id: String, in app: XCUIApplication, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            if enabledStates(of: id, in: app).contains(false) { return true }
            if Date() >= deadline { return false }
            pause(0.5)
        }
    }

    /// Polls until every element with identifier `id` reports enabled (true) or `timeout` passes
    /// (see `enabledStates`: a wrapper may report enabled even while the button is disabled).
    @MainActor
    private func waitForEnabled(_ id: String, in app: XCUIApplication, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            let states = enabledStates(of: id, in: app)
            if !states.isEmpty && !states.contains(false) { return true }
            if Date() >= deadline { return false }
            pause(0.5)
        }
    }

    @MainActor
    private func waitForDisappearance(of element: XCUIElement, timeout: TimeInterval) -> Bool {
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
        return XCTWaiter().wait(for: [gone], timeout: timeout) == .completed
    }

    /// Lets transitions and fades finish before a screenshot.
    @MainActor
    private func settle() {
        pause(1)
    }

    @MainActor
    private func pause(_ seconds: TimeInterval) {
        let never = XCTestExpectation(description: "pause")
        _ = XCTWaiter().wait(for: [never], timeout: seconds)
    }

    /// Saves a full-screen screenshot that is kept even when the test passes.
    @MainActor
    private func snapshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
