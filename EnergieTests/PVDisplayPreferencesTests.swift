//
//  PVDisplayPreferencesTests.swift
//  EnergieTests
//
//  Created by Tobias Florian on 30.09.26.
//

import Foundation
import Testing
@testable import Energie

@MainActor
struct PVDisplayPreferencesTests {

    @Test func defaultsToTheSuggestedTariff() {
        let preferences = PVDisplayPreferences(userDefaults: UserDefaults(suiteName: UUID().uuidString)!)
        #expect(preferences.feedInTariffPerKWh == PVDisplayPreferences.defaultFeedInTariffPerKWh)
    }

    @Test func persistsAnUpdatedTariff() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let preferences = PVDisplayPreferences(userDefaults: defaults)

        preferences.setFeedInTariffPerKWh(0.12)
        #expect(preferences.feedInTariffPerKWh == 0.12)

        let reloaded = PVDisplayPreferences(userDefaults: defaults)
        #expect(reloaded.feedInTariffPerKWh == 0.12)
    }

    @Test func ignoresNonPositiveTariffs() {
        let preferences = PVDisplayPreferences(userDefaults: UserDefaults(suiteName: UUID().uuidString)!)
        preferences.setFeedInTariffPerKWh(-1)
        #expect(preferences.feedInTariffPerKWh == PVDisplayPreferences.defaultFeedInTariffPerKWh)
    }
}
