//
//  HeatPumpEfficiencyTests.swift
//  EnergieTests
//
//  Created by Tobias Florian on 03.10.26.
//
//  Ported from the macOS sibling project's EfficiencyTests.swift
//  (https://github.com/tobbi78/Dashboard_Waermepumpe) — same pure logic, renamed types.

import Foundation
import Testing
@testable import Energie

/// A fixed Gregorian calendar in Europe/Berlin, so bucket boundaries don't depend on the machine
/// running the tests.
private let testCalendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
    return calendar
}()

private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12, _ minute: Int = 0) -> Date {
    testCalendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
}

private func feature(_ name: String, _ properties: [String: ViessmannFeatureValue]) -> ViessmannFeatureDTO {
    ViessmannFeatureDTO(
        feature: name,
        isEnabled: true,
        isReady: true,
        timestamp: nil,
        properties: properties.mapValues { ViessmannFeaturePropertyDTO(type: nil, value: $0, unit: nil) }
    )
}

struct HeatPumpEfficiencyPeriodTests {
    @Test(arguments: [
        (HeatPumpEfficiencyPeriod.day, "Heute", "currentDay"),
        (HeatPumpEfficiencyPeriod.week, "Letzte 7 Tage", "lastSevenDays"),
        (HeatPumpEfficiencyPeriod.month, "Letzter Monat", "lastMonth"),
        (HeatPumpEfficiencyPeriod.year, "Letztes Jahr", "lastYear"),
    ])
    func labelsAndSourceProperties(period: HeatPumpEfficiencyPeriod, displayName: String, sourceProperty: String) {
        #expect(period.displayName == displayName)
        #expect(period.sourceProperty == sourceProperty)
        #expect(period.id == period.rawValue)
    }

    @Test func dayAndWeekAreContinuousMonthAndYearAreNot() {
        #expect(HeatPumpEfficiencyPeriod.day.isContinuous)
        #expect(HeatPumpEfficiencyPeriod.week.isContinuous)
        #expect(!HeatPumpEfficiencyPeriod.month.isContinuous)
        #expect(!HeatPumpEfficiencyPeriod.year.isContinuous)
    }
}

struct HeatPumpEfficiencyDataSourceTests {
    let features = [
        feature("heating.power.consumption.summary.heating", ["lastSevenDays": .number(10)]),
        feature("heating.power.consumption.summary.dhw", ["lastSevenDays": .number(5)]),
        feature("heating.power.consumption.summary.cooling", ["lastSevenDays": .number(0)]),
        feature("heating.heat.production.summary.heating", ["lastSevenDays": .number(40)]),
        feature("heating.heat.production.summary.dhw", ["lastSevenDays": .number(10)]),
        // The heating rod is an auxiliary heat source and must not count as consumption.
        feature("heatingRod.power.consumption.summary.heating", ["lastSevenDays": .number(100)]),
    ]

    @Test func sumOnlyCountsListedFeatures() {
        let consumed = HeatPumpEfficiencyDataSource.sum(
            features: features,
            featureNames: HeatPumpEfficiencyDataSource.consumptionFeatures,
            property: "lastSevenDays"
        )
        #expect(consumed == 15)
    }

    @Test func sumIgnoresMissingProperties() {
        let sum = HeatPumpEfficiencyDataSource.sum(
            features: features,
            featureNames: HeatPumpEfficiencyDataSource.consumptionFeatures,
            property: "lastYear"
        )
        #expect(sum == 0)
    }

    @Test func liveEfficiencyIsProducedOverConsumed() {
        let efficiency = HeatPumpEfficiencyDataSource.liveEfficiency(features: features, period: .week)
        #expect(efficiency.map { abs($0 - 50.0 / 15.0) < 1e-9 } == true)
    }

    @Test func liveEfficiencyIsNilWithoutConsumption() {
        #expect(HeatPumpEfficiencyDataSource.liveEfficiency(features: features, period: .month) == nil)
        #expect(HeatPumpEfficiencyDataSource.liveEfficiency(features: [], period: .week) == nil)
    }
}

/// `.day`/`.week` don't go through `periodsNeedingSnapshot` at all — they're upserted
/// unconditionally on every poll. This only concerns the one-time `.month`/`.year` snapshots.
struct HeatPumpEfficiencyTrackerTests {
    @Test func noSnapshotBeforeSixAM() {
        let now = date(2026, 9, 25, 5, 59)
        let due = HeatPumpEfficiencyTracker.periodsNeedingSnapshot(now: now, lastSnapshotDates: [:], calendar: testCalendar)
        #expect(due.isEmpty)
    }

    @Test func monthAndYearDueWithoutPreviousSnapshots() {
        let now = date(2026, 9, 25, 6, 0)
        let due = HeatPumpEfficiencyTracker.periodsNeedingSnapshot(now: now, lastSnapshotDates: [:], calendar: testCalendar)
        #expect(due == [.month, .year])
    }

    @Test func nothingDueWithinSameMonthAndYear() {
        let last = date(2026, 9, 24, 6, 10)
        let now = date(2026, 9, 25, 23, 50)
        let due = HeatPumpEfficiencyTracker.periodsNeedingSnapshot(
            now: now,
            lastSnapshotDates: [.month: last, .year: last],
            calendar: testCalendar
        )
        #expect(due.isEmpty)
    }

    @Test func newMonthNeedsMonthOnly() {
        let last = date(2026, 9, 30, 6, 10)
        let now = date(2026, 10, 1, 6, 10)
        let due = HeatPumpEfficiencyTracker.periodsNeedingSnapshot(
            now: now,
            lastSnapshotDates: [.month: last, .year: last],
            calendar: testCalendar
        )
        #expect(due == [.month])
    }

    @Test func sameMonthNumberInDifferentYearStillNeedsMonth() {
        // Same month number, different year — must not be mistaken for "same month".
        let last = date(2025, 9, 25, 6, 10)
        let now = date(2026, 9, 25, 6, 10)
        let due = HeatPumpEfficiencyTracker.periodsNeedingSnapshot(
            now: now,
            lastSnapshotDates: [.month: last],
            calendar: testCalendar
        )
        #expect(due == [.month, .year])
    }

    @Test func newYearNeedsMonthAndYear() {
        let last = date(2026, 12, 31, 6, 10)
        let now = date(2027, 1, 1, 6, 10)
        let due = HeatPumpEfficiencyTracker.periodsNeedingSnapshot(
            now: now,
            lastSnapshotDates: [.month: last, .year: last],
            calendar: testCalendar
        )
        #expect(due == [.month, .year])
    }
}

struct HeatPumpEfficiencySampleTests {
    @Test func efficiencyIsProducedOverConsumed() {
        let sample = HeatPumpEfficiencySample(period: .month, boundaryDate: Date(), consumedKWh: 20, producedKWh: 70)
        #expect(sample.period == "month")
        #expect(sample.efficiency == 3.5)
    }

    @Test func efficiencyIsZeroWithoutConsumption() {
        let sample = HeatPumpEfficiencySample(period: .week, boundaryDate: Date(), consumedKWh: 0, producedKWh: 10)
        #expect(sample.efficiency == 0)
    }
}
