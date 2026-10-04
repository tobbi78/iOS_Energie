//
//  EnphaseBudgetSettingsTests.swift
//  EnergieTests
//
//  Created by Tobias Florian on 04.10.26.
//

import Foundation
import Testing
@testable import Energie

@MainActor
struct EnphaseBudgetSettingsTests {
    @Test func defaultsToTwenty() {
        let settings = EnphaseBudgetSettings(userDefaults: UserDefaults(suiteName: UUID().uuidString)!)
        #expect(settings.monthlyReserve == EnphaseBudgetSettings.defaultReserve)
    }

    @Test func persistsAnUpdatedReserve() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let settings = EnphaseBudgetSettings(userDefaults: defaults)

        settings.setMonthlyReserve(50)
        #expect(settings.monthlyReserve == 50)

        let reloaded = EnphaseBudgetSettings(userDefaults: defaults)
        #expect(reloaded.monthlyReserve == 50)
    }

    @Test func clampsBelowMinimum() {
        let settings = EnphaseBudgetSettings(userDefaults: UserDefaults(suiteName: UUID().uuidString)!)
        settings.setMonthlyReserve(-10)
        #expect(settings.monthlyReserve == EnphaseBudgetSettings.minimumReserve)
    }

    @Test func clampsAboveMaximum() {
        let settings = EnphaseBudgetSettings(userDefaults: UserDefaults(suiteName: UUID().uuidString)!)
        settings.setMonthlyReserve(1000)
        #expect(settings.monthlyReserve == EnphaseBudgetSettings.maximumReserve)
    }
}
