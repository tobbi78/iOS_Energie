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

    // MARK: - Monthly limit (F6.4)

    @Test func defaultsToOneThousand() {
        let settings = EnphaseBudgetSettings(userDefaults: UserDefaults(suiteName: UUID().uuidString)!)
        #expect(settings.monthlyLimit == EnphaseBudgetSettings.defaultMonthlyLimit)
    }

    @Test func persistsAnUpdatedMonthlyLimit() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let settings = EnphaseBudgetSettings(userDefaults: defaults)

        settings.setMonthlyLimit(500)
        #expect(settings.monthlyLimit == 500)

        let reloaded = EnphaseBudgetSettings(userDefaults: defaults)
        #expect(reloaded.monthlyLimit == 500)
    }

    @Test func clampsMonthlyLimitBelowMinimum() {
        let settings = EnphaseBudgetSettings(userDefaults: UserDefaults(suiteName: UUID().uuidString)!)
        settings.setMonthlyLimit(50)
        #expect(settings.monthlyLimit == EnphaseBudgetSettings.minimumMonthlyLimit)
    }

    @Test func clampsMonthlyLimitAboveMaximum() {
        let settings = EnphaseBudgetSettings(userDefaults: UserDefaults(suiteName: UUID().uuidString)!)
        settings.setMonthlyLimit(5000)
        #expect(settings.monthlyLimit == EnphaseBudgetSettings.maximumMonthlyLimit)
    }

    // F6.4: reserve must never exceed half of the limit — lowering the limit below the
    // already-configured reserve has to pull the reserve down with it instead of leaving it
    // inconsistently large.
    @Test func loweringTheLimitReducesAnOversizedReserve() {
        let settings = EnphaseBudgetSettings(userDefaults: UserDefaults(suiteName: UUID().uuidString)!)
        settings.setMonthlyLimit(1000)
        settings.setMonthlyReserve(100)
        #expect(settings.monthlyReserve == 100)

        settings.setMonthlyLimit(150)
        #expect(settings.monthlyReserve == 75)
    }

    @Test func reserveIsClampedToHalfTheCurrentLimit() {
        let settings = EnphaseBudgetSettings(userDefaults: UserDefaults(suiteName: UUID().uuidString)!)
        settings.setMonthlyLimit(200)
        settings.setMonthlyReserve(100)
        #expect(settings.monthlyReserve == 100)

        settings.setMonthlyReserve(101)
        #expect(settings.monthlyReserve == 100)
    }
}
