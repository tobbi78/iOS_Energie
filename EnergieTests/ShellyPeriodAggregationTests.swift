//
//  ShellyPeriodAggregationTests.swift
//  EnergieTests
//
//  Created by Tobias Florian on 15.10.26.
//

import Foundation
import Testing
@testable import Energie

/// F14.3 — stacked-bar aggregation for the Shelly history charts.
@MainActor
struct ShellyPeriodAggregationTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private let devices = [
        ShellyDevice(id: "a", name: "Waschmaschine", model: nil),
        ShellyDevice(id: "b", name: "Kühlschrank", model: nil),
    ]

    @Test func seriesKeepSavedOrderAndColorSlots() {
        let series = ShellyPeriodAggregation.series(for: devices)
        #expect(series.map(\.id) == ["a", "b"])
        #expect(series.map(\.colorSlot) == [0, 1])
    }

    @Test func morePlugsThanColorsFoldIntoOther() {
        let many = (0..<10).map { ShellyDevice(id: "d\($0)", name: "Steckdose \($0)", model: nil) }
        let series = ShellyPeriodAggregation.series(for: many)
        #expect(series.count == ShellyPeriodAggregation.maxColorSlots)
        #expect(series.last?.id == ShellyHistorySeries.otherID)
        #expect(series.last?.colorSlot == nil)
    }

    @Test func otherBucketSumsTheFoldedPlugs() {
        let many = (0..<10).map { ShellyDevice(id: "d\($0)", name: "Steckdose \($0)", model: nil) }
        let samples = many.map { ShellyDailySample(deviceID: $0.id, date: day(2026, 10, 15), energyWh: 100) }

        let points = ShellyPeriodAggregation.lastThirtyDays(samples, devices: many, now: day(2026, 10, 15), calendar: calendar)
        let other = points.filter { $0.seriesID == ShellyHistorySeries.otherID && $0.periodStart == day(2026, 10, 15) }
        #expect(other.map(\.energyWh) == [300])
        #expect(ShellyPeriodAggregation.totalWh(points) == 1000)
    }

    @Test func lastThirtyDaysCoversEveryDayForEverySeries() {
        let samples = [ShellyDailySample(deviceID: "a", date: day(2026, 10, 15), energyWh: 500)]

        let points = ShellyPeriodAggregation.lastThirtyDays(samples, devices: devices, now: day(2026, 10, 15), calendar: calendar)

        #expect(points.count == 30 * 2)
        #expect(points.first?.periodStart == day(2026, 9, 16))
        #expect(points.last?.periodStart == day(2026, 10, 15))
        #expect(ShellyPeriodAggregation.totalWh(points) == 500)
    }

    @Test func lastTwelveMonthsSumsDaysPerMonthAndSeries() {
        let samples = [
            ShellyDailySample(deviceID: "a", date: day(2026, 10, 1), energyWh: 100),
            ShellyDailySample(deviceID: "a", date: day(2026, 10, 15), energyWh: 200),
            ShellyDailySample(deviceID: "b", date: day(2026, 10, 2), energyWh: 50),
            ShellyDailySample(deviceID: "a", date: day(2026, 9, 30), energyWh: 70),
            // Outside the 12-month window.
            ShellyDailySample(deviceID: "a", date: day(2025, 10, 31), energyWh: 999),
        ]

        let points = ShellyPeriodAggregation.lastTwelveMonths(samples, devices: devices, now: day(2026, 10, 20), calendar: calendar)

        #expect(points.count == 12 * 2)
        #expect(points.first?.periodStart == day(2025, 11, 1))
        let october = points.filter { $0.periodStart == day(2026, 10, 1) }
        #expect(october.first { $0.seriesID == "a" }?.energyWh == 300)
        #expect(october.first { $0.seriesID == "b" }?.energyWh == 50)
        #expect(points.first { $0.periodStart == day(2026, 9, 1) && $0.seriesID == "a" }?.energyWh == 70)
        #expect(ShellyPeriodAggregation.totalWh(points) == 420)
    }

    @Test func yearsStartAtEarliestRecordedYear() {
        let samples = [
            ShellyDailySample(deviceID: "a", date: day(2024, 6, 1), energyWh: 10),
            ShellyDailySample(deviceID: "b", date: day(2026, 1, 1), energyWh: 20),
        ]

        let points = ShellyPeriodAggregation.years(samples, devices: devices, now: day(2026, 10, 15), calendar: calendar)

        #expect(Set(points.map(\.periodStart)) == [day(2024, 1, 1), day(2025, 1, 1), day(2026, 1, 1)])
        #expect(ShellyPeriodAggregation.totalWh(points) == 30)
    }

    @Test func removedPlugsAreIgnored() {
        let samples = [
            ShellyDailySample(deviceID: "a", date: day(2026, 10, 15), energyWh: 100),
            ShellyDailySample(deviceID: "gone", date: day(2023, 1, 1), energyWh: 5000),
        ]

        let years = ShellyPeriodAggregation.years(samples, devices: devices, now: day(2026, 10, 15), calendar: calendar)

        #expect(Set(years.map(\.periodStart)) == [day(2026, 1, 1)])
        #expect(ShellyPeriodAggregation.totalWh(years) == 100)
    }

    @Test func duplicateDeviceDayRowsCountOnlyTheLargerOne() {
        let samples = [
            ShellyDailySample(deviceID: "a", date: day(2026, 10, 15), energyWh: 300),
            ShellyDailySample(deviceID: "a", date: day(2026, 10, 15), energyWh: 200),
        ]

        let points = ShellyPeriodAggregation.lastThirtyDays(samples, devices: devices, now: day(2026, 10, 15), calendar: calendar)

        #expect(ShellyPeriodAggregation.totalWh(points) == 300)
    }
}
