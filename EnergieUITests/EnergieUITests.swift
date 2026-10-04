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

    @MainActor
    func testAppLaunchesOnStartTabWithAllThreeTabsPresent() throws {
        let app = XCUIApplication()
        app.launch()

        // The floating "Liquid Glass" tab bar isn't reliably exposed to XCUITest as
        // XCUIElementTypeTabBar (its items resolve to an undocumented accessibility type,
        // inconsistently reported as Button/Other/Cell depending on the query path) — query the
        // tab buttons directly on `app` instead of scoping through `app.tabBars`, which returns
        // zero matches on this tab bar style.
        XCTAssertTrue(app.buttons["Start"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["PV-Anlage"].exists)
        XCTAssertTrue(app.buttons["Wärmepumpe"].exists)
        // "Start" is the default/first tab — its own content should already be visible.
        XCTAssertTrue(app.navigationBars["Start"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testHomeSectionHeadersNavigateToTheirTabs() throws {
        let app = XCUIApplication()
        app.launch()
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
    /// not already signed in, or its detail screens (`PVHistoryChartsView`, settings) when a
    /// prior manual test session left it signed in — either way, real `body` code runs.
    @MainActor
    func testPVAnlageTabRendersWhicheverStateItIsInAndDetailScreensIfReady() throws {
        let app = XCUIApplication()
        app.launch()
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

        // .ready (or .error/.rateLimited, which still show the "Mehr" menu's sibling toolbar
        // button in this app) — drill into the detail screens via the "Mehr" menu.
        let moreButton = app.navigationBars["PV-Anlage"].buttons["Mehr"]
        guard moreButton.waitForExistence(timeout: 3) else { return }
        moreButton.tap()
        app.buttons["Verlauf"].tap()
        XCTAssertTrue(app.navigationBars["Verlauf"].waitForExistence(timeout: 5))
        app.navigationBars["Verlauf"].buttons["PV-Anlage"].tap()

        moreButton.tap()
        app.buttons["Einstellungen"].tap()
        XCTAssertTrue(app.navigationBars["Einstellungen"].waitForExistence(timeout: 5))
    }

    /// Exercises `HeatPumpView`'s three non-ready states, or all five detail screens
    /// (`DetailSectionComponents`-based Heizkreise/Warmwasser/Effizienz/Verdichter plus
    /// Einstellungen) when already signed in.
    @MainActor
    func testWaermepumpeTabRendersWhicheverStateItIsInAndDetailScreensIfReady() throws {
        let app = XCUIApplication()
        app.launch()
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

        for screen in ["Heizkreise", "Warmwasser", "Effizienz & Verbrauch", "Verdichter & Kältekreis", "Einstellungen"] {
            moreButton.tap()
            app.buttons[screen].tap()
            XCTAssertTrue(app.navigationBars[screen].waitForExistence(timeout: 5), "Expected \(screen) to appear")
            app.navigationBars[screen].buttons["Wärmepumpe"].tap()
        }
    }

    @MainActor
    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
