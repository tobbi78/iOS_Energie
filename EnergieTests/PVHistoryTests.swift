//
//  PVHistoryTests.swift
//  EnergieTests
//
//  Created by Tobias Florian on 30.09.26.
//

import Foundation
import Testing
@testable import Energie

private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
    Calendar.current.date(from: DateComponents(year: year, month: month, day: day))!
}

struct PVHistoryTests {

    // MARK: - Lifetime DTO decoding (F3.2/F3.3)

    @Test func energyLifetimeResolvesDailyDatesFromStartDate() throws {
        let json = """
        { "start_date": "2026-01-01", "production": [10, 20, 30] }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(EnphaseEnergyLifetimeResponse.self, from: json)
        let values = decoded.dailyValues
        #expect(values.count == 3)
        #expect(values[0].date == date(2026, 1, 1))
        #expect(values[0].value == 10)
        #expect(values[2].date == date(2026, 1, 3))
        #expect(values[2].value == 30)
    }

    @Test func batteryLifetimeDecodesChargeAndDischargeSeparately() throws {
        let json = """
        { "start_date": "2026-01-01", "charge": [5, 6], "discharge": [1, 2] }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(EnphaseBatteryLifetimeResponse.self, from: json)
        #expect(decoded.dailyChargedValues.map(\.value) == [5, 6])
        #expect(decoded.dailyDischargedValues.map(\.value) == [1, 2])
    }

    // MARK: - Backfill gap detection (F3.2)

    @Test func backfillStartDayUsesOperationalAtWhenKnown() {
        let start = PVBackfillPlanner.backfillStartDay(operationalAt: date(2024, 3, 1), today: date(2026, 9, 30))
        #expect(start == date(2024, 3, 1))
    }

    @Test func backfillStartDayFallsBackToThirtyDaysWithoutOperationalAt() {
        let today = date(2026, 9, 30)
        let start = PVBackfillPlanner.backfillStartDay(operationalAt: nil, today: today)
        let expected = Calendar.current.date(byAdding: .day, value: -30, to: today)!
        #expect(start == expected)
    }

    @Test func missingDaysExcludesTodayAndExistingDays() {
        let start = date(2026, 9, 27)
        let today = date(2026, 9, 30)
        let existing: Set<Date> = [date(2026, 9, 28)]

        let missing = PVBackfillPlanner.missingDays(existingDays: existing, from: start, today: today)

        #expect(missing == [date(2026, 9, 27), date(2026, 9, 29)])
    }

    @Test func missingDaysIsEmptyWhenStartIsNotBeforeToday() {
        let today = date(2026, 9, 30)
        #expect(PVBackfillPlanner.missingDays(existingDays: [], from: today, today: today).isEmpty)
    }

    // MARK: - Period aggregation (F3.4)

    @Test func lastTwelveMonthsAlwaysReturnsTwelveEntriesWithRunningFlagOnLast() {
        let now = date(2026, 9, 30)
        let months = PVPeriodAggregation.lastTwelveMonths([], now: now)

        #expect(months.count == 12)
        #expect(months.last?.isRunning == true)
        #expect(months.dropLast().allSatisfy { !$0.isRunning })
    }

    @Test func lastTwelveMonthsSumsSamplesIntoTheirMonth() {
        let now = date(2026, 9, 30)
        let samples = [
            PVDailySample(date: date(2026, 9, 1), producedWh: 100),
            PVDailySample(date: date(2026, 9, 15), producedWh: 50),
            PVDailySample(date: date(2026, 8, 1), producedWh: 999),
        ]

        let months = PVPeriodAggregation.lastTwelveMonths(samples, now: now)
        #expect(months.last?.producedWh == 150)
    }

    @Test func yearsMergesArchivedTotalsWithRemainingDailyRows() {
        let now = date(2026, 9, 30)
        let daily = [PVDailySample(date: date(2026, 1, 10), producedWh: 40)]
        let archived = [PVYearlySample(yearStart: date(2026, 1, 1), producedWh: 1000)]

        let years = PVPeriodAggregation.years(daily, archivedYears: archived, now: now)

        let currentYear = years.first { Calendar.current.isDate($0.periodStart, equalTo: now, toGranularity: .year) }
        #expect(currentYear?.producedWh == 1040)
        #expect(currentYear?.isRunning == true)
    }

    @Test func yearsCoversEarliestArchivedYearEvenWithoutDailyRows() {
        let now = date(2026, 9, 30)
        let archived = [PVYearlySample(yearStart: date(2023, 1, 1), producedWh: 500)]

        let years = PVPeriodAggregation.years([], archivedYears: archived, now: now)

        #expect(years.first?.periodStart == date(2023, 1, 1))
        #expect(years.first?.producedWh == 500)
    }

    // MARK: - Pruning (F3.6)

    @Test func isEligibleForPruningOnlyForRowsOlderThanAYear() {
        let now = date(2026, 9, 30)
        #expect(PVHistoryPruner.isEligibleForPruning(date: date(2024, 1, 1), now: now))
        #expect(!PVHistoryPruner.isEligibleForPruning(date: date(2026, 9, 1), now: now))
    }

    @Test func groupByYearGroupsAcrossCalendarYears() {
        let samples = [
            PVDailySample(date: date(2023, 5, 1)),
            PVDailySample(date: date(2023, 11, 1)),
            PVDailySample(date: date(2024, 2, 1)),
        ]

        let groups = PVHistoryPruner.groupByYear(samples)
        #expect(groups[date(2023, 1, 1)]?.count == 2)
        #expect(groups[date(2024, 1, 1)]?.count == 1)
    }
}
