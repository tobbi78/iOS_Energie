//
//  WatchSnapshotTests.swift
//  EnergieTests
//
//  Created by Tobias Florian on 04.10.26.
//

import Foundation
import Testing
@testable import Energie

struct WatchSnapshotTests {
    @Test func encodesAndDecodesRoundTrip() throws {
        let snapshot = WatchSnapshot(
            pvProducedTodayWh: 4200,
            pvSelfSufficiencyRate: 0.73,
            pvBatterySocPercent: 55,
            pvFetchedAt: Date(timeIntervalSince1970: 1_700_000_000),
            heatPumpPressureBar: 1.8,
            heatPumpOutsideTemperatureCelsius: 6.5,
            heatPumpPressureAlertActive: true,
            heatPumpFetchedAt: Date(timeIntervalSince1970: 1_700_000_100)
        )

        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(WatchSnapshot.self, from: data)

        #expect(decoded == snapshot)
    }

    @Test func emptyHasNoValuesAndNoAlert() {
        let empty = WatchSnapshot.empty
        #expect(empty.pvProducedTodayWh == nil)
        #expect(empty.pvSelfSufficiencyRate == nil)
        #expect(empty.pvBatterySocPercent == nil)
        #expect(empty.pvFetchedAt == nil)
        #expect(empty.heatPumpPressureBar == nil)
        #expect(empty.heatPumpOutsideTemperatureCelsius == nil)
        #expect(empty.heatPumpPressureAlertActive == false)
        #expect(empty.heatPumpFetchedAt == nil)
    }

    @Test func equatableDetectsASingleChangedField() {
        var snapshot = WatchSnapshot.empty
        snapshot.pvProducedTodayWh = 1000

        var changed = snapshot
        changed.heatPumpPressureAlertActive = true

        #expect(snapshot != changed)
        #expect(snapshot == snapshot)
    }
}
