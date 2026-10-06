//
//  EnergieUITests.swift
//  EnergieUITests
//
//  Created by Tobias Florian on 30.09.26.
//

import XCTest

/// UI tests drive the real app, so they're the only practical way to exercise SwiftUI `body`
/// code (HeatPumpView/SolarView/PVHistoryChartsView/DetailSectionComponents/ErrorView) for code
/// coverage — plain unit tests can't call a View's `body` as an assertable unit. Tests branch on
/// whatever sign-in state the simulator happens to be in (fresh install vs. an already
/// signed-in session left over from manual testing) rather than assuming one, since that state
/// isn't something a UI test controls without a dedicated test-mode launch hook this project
/// doesn't have yet.
final class EnergieUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Launches the app and waits out the `LaunchView` overlay (F10.1) before handing back
    /// control — otherwise taps meant for the tab bar/content below can land on the overlay
    /// instead, since it sits on top of the `TabView` for up to ~2.5s after launch.
    @MainActor
    @discardableResult
    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.otherElements["launchScreen"].waitForNonExistence(timeout: 5))
        return app
    }

    @MainActor
    func testLaunchScreenAppearsAndDismissesIntoStartTab() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.otherElements["launchScreen"].exists)
        XCTAssertTrue(app.otherElements["launchScreen"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars["Start"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testAppLaunchesOnStartTabWithAllFourTabsPresent() throws {
        let app = launchApp()

        // The floating "Liquid Glass" tab bar isn't reliably exposed to XCUITest as
        // XCUIElementTypeTabBar (its items resolve to an undocumented accessibility type,
        // inconsistently reported as Button/Other/Cell depending on the query path) — query the
        // tab buttons directly on `app` instead of scoping through `app.tabBars`, which returns
        // zero matches on this tab bar style.
        XCTAssertTrue(app.buttons["Start"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["PV-Anlage"].exists)
        XCTAssertTrue(app.buttons["Wärmepumpe"].exists)
        XCTAssertTrue(app.buttons["Einstellungen"].exists)
        // "Start" is the default/first tab — its own content should already be visible.
        XCTAssertTrue(app.navigationBars["Start"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testHomeSectionHeadersNavigateToTheirTabs() throws {
        let app = launchApp()
        XCTAssertTrue(app.navigationBars["Start"].waitForExistence(timeout: 5))

        app.staticTexts["PV-Anlage"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["PV-Anlage"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["PV-Anlage"].firstMatch.isSelected)

        app.buttons["Start"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Start"].waitForExistence(timeout: 5))
        app.staticTexts["Wärmepumpe"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Wärmepumpe"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Wärmepumpe"].firstMatch.isSelected)
    }

    /// Exercises `SolarView`'s three non-ready states (credentials form / sign-in prompt) when
    /// not already signed in, or its "Verlauf" detail screen (`PVHistoryChartsView`) when a
    /// prior manual test session left it signed in — either way, real `body` code runs.
    /// `PVSettingsScreen` is exercised separately via the "Einstellungen" tab, not here.
    @MainActor
    func testPVAnlageTabRendersWhicheverStateItIsInAndDetailScreensIfReady() throws {
        let app = launchApp()
        app.buttons["PV-Anlage"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["PV-Anlage"].waitForExistence(timeout: 5))

        if app.buttons["Weiter"].waitForExistence(timeout: 3) {
            // .needsCredentials
            XCTAssertTrue(app.staticTexts["Enphase-Zugangsdaten"].exists)
            return
        }
        if app.buttons["Anmelden"].waitForExistence(timeout: 3) {
            // .needsSignIn
            XCTAssertTrue(app.staticTexts["Mit Enphase verbinden"].exists)
            return
        }

        // .ready (or .error/.rateLimited, which still show the toolbar's "Verlauf" button).
        let historyButton = app.navigationBars["PV-Anlage"].buttons["Verlauf"]
        guard historyButton.waitForExistence(timeout: 3) else { return }
        historyButton.tap()
        XCTAssertTrue(app.navigationBars["Verlauf"].waitForExistence(timeout: 5))
        app.navigationBars["Verlauf"].buttons["PV-Anlage"].tap()
    }

    /// Exercises `HeatPumpView`'s three non-ready states, or all four diagnostic detail screens
    /// (`DetailSectionComponents`-based Heizkreise/Warmwasser/Effizienz/Verdichter) when already
    /// signed in. `HeatPumpSettingsScreen` is exercised separately via the "Einstellungen" tab,
    /// not here.
    @MainActor
    func testWaermepumpeTabRendersWhicheverStateItIsInAndDetailScreensIfReady() throws {
        let app = launchApp()
        app.buttons["Wärmepumpe"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Wärmepumpe"].waitForExistence(timeout: 5))

        if app.buttons["Weiter"].waitForExistence(timeout: 3) {
            // .needsCredentials
            XCTAssertTrue(app.staticTexts["Viessmann-Zugangsdaten"].exists)
            return
        }
        if app.buttons["Anmelden"].waitForExistence(timeout: 3) {
            // .needsSignIn
            XCTAssertTrue(app.staticTexts["Mit Viessmann verbinden"].exists)
            return
        }

        let moreButton = app.navigationBars["Wärmepumpe"].buttons["Mehr"]
        guard moreButton.waitForExistence(timeout: 3) else { return }

        for screen in ["Heizkreise", "Warmwasser", "Effizienz & Verbrauch", "Verdichter & Kältekreis"] {
            moreButton.tap()
            app.buttons[screen].tap()
            XCTAssertTrue(app.navigationBars[screen].waitForExistence(timeout: 5), "Expected \(screen) to appear")
            app.navigationBars[screen].buttons["Wärmepumpe"].tap()
        }
    }

    /// Exercises the consolidated "Einstellungen" tab (`SettingsView`) and, through it, both
    /// `PVSettingsScreen` and `HeatPumpSettingsScreen` — the single place either source's
    /// settings now live, replacing the former per-tab "Mehr" > "Einstellungen" entries.
    @MainActor
    func testEinstellungenTabNavigatesToBothSettingsScreens() throws {
        let app = launchApp()
        XCTAssertTrue(app.buttons["Einstellungen"].firstMatch.waitForExistence(timeout: 5))
        app.buttons["Einstellungen"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Einstellungen"].waitForExistence(timeout: 5))

        // Tapping the row's own text, not `.buttons[...]`, since that label is ambiguous with
        // the bottom tab bar's identically-labeled button (same reasoning as
        // testHomeSectionHeadersNavigateToTheirTabs) — a plain `.firstMatch` on the button query
        // can land on the tab bar instead of this list row and switch tabs rather than push.
        app.staticTexts["PV-Anlage"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["PV-Anlage"].waitForExistence(timeout: 5))
        app.navigationBars["PV-Anlage"].buttons["Einstellungen"].tap()

        app.staticTexts["Wärmepumpe"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Wärmepumpe"].waitForExistence(timeout: 5))
        app.navigationBars["Wärmepumpe"].buttons["Einstellungen"].tap()
    }

    @MainActor
    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
