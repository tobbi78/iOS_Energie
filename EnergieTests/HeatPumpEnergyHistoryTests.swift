//
//  HeatPumpEnergyHistoryTests.swift
//  EnergieTests
//
//  Created by Tobias Florian on 11.10.26.
//

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

struct HeatPumpHistoryGranularityTests {
    @Test(arguments: [
        (HeatPumpHistoryGranularity.day, "Tage", "day", HeatPumpEfficiencyPeriod.day),
        (HeatPumpHistoryGranularity.week, "Wochen", "week", HeatPumpEfficiencyPeriod.week),
        (HeatPumpHistoryGranularity.month, "Monate", "month", HeatPumpEfficiencyPeriod.month),
        (HeatPumpHistoryGranularity.year, "Jahre", "year", HeatPumpEfficiencyPeriod.year),
    ])
    func labelsAndMappings(
        granularity: HeatPumpHistoryGranularity,
        displayName: String,
        arrayProperty: String,
        samplePeriod: HeatPumpEfficiencyPeriod
    ) {
        #expect(granularity.displayName == displayName)
        #expect(granularity.consumptionArrayProperty == arrayProperty)
        #expect(granularity.samplePeriod == samplePeriod)
        #expect(granularity.id == granularity.rawValue)
    }

    @Test func onlyMonthAndYearNeedALiveProductionProperty() {
        #expect(HeatPumpHistoryGranularity.day.currentProductionProperty == nil)
        #expect(HeatPumpHistoryGranularity.week.currentProductionProperty == nil)
        #expect(HeatPumpHistoryGranularity.month.currentProductionProperty == "currentMonth")
        #expect(HeatPumpHistoryGranularity.year.currentProductionProperty == "currentYear")
    }

    @Test func dayAnchorsStepBackOneCalendarDayAtATime() {
        let now = date(2026, 10, 11, 14, 0)
        #expect(HeatPumpHistoryGranularity.day.anchorDate(index: 0, now: now, calendar: testCalendar) == date(2026, 10, 11, 0, 0))
        #expect(HeatPumpHistoryGranularity.day.anchorDate(index: 3, now: now, calendar: testCalendar) == date(2026, 10, 8, 0, 0))
    }

    @Test func weekAnchorsStepBackInSevenDayBlocksNotCalendarWeeks() {
        let now = date(2026, 10, 11, 14, 0)
        #expect(HeatPumpHistoryGranularity.week.anchorDate(index: 0, now: now, calendar: testCalendar) == date(2026, 10, 11, 0, 0))
        #expect(HeatPumpHistoryGranularity.week.anchorDate(index: 1, now: now, calendar: testCalendar) == date(2026, 10, 4, 0, 0))
    }

    @Test func monthAnchorsStepBackToTheFirstOfEachMonth() {
        let now = date(2026, 10, 11, 14, 0)
        #expect(HeatPumpHistoryGranularity.month.anchorDate(index: 0, now: now, calendar: testCalendar) == date(2026, 10, 1, 0, 0))
        #expect(HeatPumpHistoryGranularity.month.anchorDate(index: 1, now: now, calendar: testCalendar) == date(2026, 9, 1, 0, 0))
    }

    @Test func yearAnchorsStepBackToTheFirstOfEachYear() {
        let now = date(2026, 10, 11, 14, 0)
        #expect(HeatPumpHistoryGranularity.year.anchorDate(index: 0, now: now, calendar: testCalendar) == date(2026, 1, 1, 0, 0))
        #expect(HeatPumpHistoryGranularity.year.anchorDate(index: 1, now: now, calendar: testCalendar) == date(2025, 1, 1, 0, 0))
    }
}

struct HeatPumpEnergyBucketTests {
    @Test func efficiencyIsProducedOverConsumed() {
        let bucket = HeatPumpEnergyBucket(date: Date(), isCurrent: false, consumedKWh: 10, producedKWh: 35)
        #expect(bucket.efficiency == 3.5)
    }

    @Test func efficiencyIsNilWithoutBothValues() {
        #expect(HeatPumpEnergyBucket(date: Date(), isCurrent: false, consumedKWh: nil, producedKWh: 35).efficiency == nil)
        #expect(HeatPumpEnergyBucket(date: Date(), isCurrent: false, consumedKWh: 10, producedKWh: nil).efficiency == nil)
    }

    @Test func efficiencyIsNilWithZeroConsumption() {
        #expect(HeatPumpEnergyBucket(date: Date(), isCurrent: false, consumedKWh: 0, producedKWh: 35).efficiency == nil)
    }
}

struct HeatPumpEnergyHistoryTests {
    private let now = date(2026, 10, 11, 14, 0)

    private func consumptionFeature(day: [Double]? = nil, week: [Double]? = nil, month: [Double]? = nil, year: [Double]? = nil) -> ViessmannFeatureDTO {
        var properties: [String: ViessmannFeatureValue] = [:]
        if let day { properties["day"] = .numberArray(day) }
        if let week { properties["week"] = .numberArray(week) }
        if let month { properties["month"] = .numberArray(month) }
        if let year { properties["year"] = .numberArray(year) }
        return feature("heating.power.consumption.total", properties)
    }

    @Test func dayBucketsUseConsumptionArrayDirectlyAndSamplesForProduction() {
        let features = [consumptionFeature(day: [2.0, 1.8, 2.1])]
        let samples = [
            HeatPumpEfficiencySample(period: .day, boundaryDate: date(2026, 10, 11, 0, 0), consumedKWh: 2.0, producedKWh: 8.0),
            HeatPumpEfficiencySample(period: .day, boundaryDate: date(2026, 10, 10, 0, 0), consumedKWh: 1.8, producedKWh: 7.0),
            // 2026-10-09 has no sample — that bucket's production must be nil, not 0.
        ]

        let buckets = HeatPumpEnergyHistory.buckets(granularity: .day, features: features, samples: samples, now: now, calendar: testCalendar)

        #expect(buckets.map(\.date) == [date(2026, 10, 9, 0, 0), date(2026, 10, 10, 0, 0), date(2026, 10, 11, 0, 0)])
        #expect(buckets.map(\.consumedKWh) == [2.1, 1.8, 2.0])

        let today = buckets[2]
        #expect(today.isCurrent)
        #expect(today.producedKWh == 8.0)
        #expect(today.efficiency == 4.0)

        let yesterday = buckets[1]
        #expect(!yesterday.isCurrent)
        #expect(yesterday.producedKWh == 7.0)

        let missing = buckets[0]
        #expect(missing.producedKWh == nil)
        #expect(missing.efficiency == nil)
    }

    @Test func weekBucketsStepBackInSevenDayBlocks() {
        let features = [consumptionFeature(week: [13.5, 10.7])]
        let samples = [
            HeatPumpEfficiencySample(period: .week, boundaryDate: date(2026, 10, 11, 0, 0), consumedKWh: 13.5, producedKWh: 50.0),
        ]

        let buckets = HeatPumpEnergyHistory.buckets(granularity: .week, features: features, samples: samples, now: now, calendar: testCalendar)

        #expect(buckets.map(\.date) == [date(2026, 10, 4, 0, 0), date(2026, 10, 11, 0, 0)])
        #expect(buckets[1].isCurrent)
        #expect(buckets[1].producedKWh == 50.0)
        // 2026-10-04 has no `.week` sample recorded yet.
        #expect(buckets[0].producedKWh == nil)
    }

    @Test func monthIndexZeroUsesLiveCurrentMonthProduction() {
        let features = [
            consumptionFeature(month: [20.5]),
            feature("heating.heat.production.summary.heating", ["currentMonth": .number(42.0)]),
            feature("heating.heat.production.summary.dhw", ["currentMonth": .number(8.0)]),
        ]

        let buckets = HeatPumpEnergyHistory.buckets(granularity: .month, features: features, samples: [], now: now, calendar: testCalendar)

        #expect(buckets.count == 1)
        #expect(buckets[0].isCurrent)
        #expect(buckets[0].consumedKWh == 20.5)
        #expect(buckets[0].producedKWh == 50.0)
    }

    @Test func monthIndexOneMapsSampleCapturedTheFollowingMonthToThePreviousMonth() {
        let features = [consumptionFeature(month: [20.5, 49.1])]
        // Captured just after October started — represents September's total.
        let samples = [
            HeatPumpEfficiencySample(period: .month, boundaryDate: date(2026, 10, 1, 6, 10), consumedKWh: 49.1, producedKWh: 180.0),
        ]

        let buckets = HeatPumpEnergyHistory.buckets(granularity: .month, features: features, samples: samples, now: now, calendar: testCalendar)

        let september = buckets[0]
        #expect(september.date == date(2026, 9, 1, 0, 0))
        #expect(september.producedKWh == 180.0)

        let october = buckets[1]
        #expect(october.isCurrent)
        // Live branch always runs for the current month; with no production features in this
        // fixture, HeatPumpEfficiencyDataSource.sum legitimately returns 0, not nil.
        #expect(october.producedKWh == 0)
    }

    @Test func yearIndexOneMapsSampleCapturedTheFollowingYearToThePreviousYear() {
        let features = [consumptionFeature(year: [694.4, 1092.6])]
        let samples = [
            HeatPumpEfficiencySample(period: .year, boundaryDate: date(2026, 1, 1, 6, 10), consumedKWh: 1092.6, producedKWh: 4000.0),
        ]

        let buckets = HeatPumpEnergyHistory.buckets(granularity: .year, features: features, samples: samples, now: now, calendar: testCalendar)

        #expect(buckets[0].date == date(2025, 1, 1, 0, 0))
        #expect(buckets[0].producedKWh == 4000.0)
    }

    @Test func emptyConsumptionArrayProducesNoBuckets() {
        let buckets = HeatPumpEnergyHistory.buckets(granularity: .day, features: [], samples: [], now: now, calendar: testCalendar)
        #expect(buckets.isEmpty)
    }

    @Test func bucketsAreSortedOldestFirst() {
        let features = [consumptionFeature(day: [1, 2, 3, 4])]
        let buckets = HeatPumpEnergyHistory.buckets(granularity: .day, features: features, samples: [], now: now, calendar: testCalendar)
        #expect(buckets.map(\.date) == buckets.map(\.date).sorted())
    }
}
