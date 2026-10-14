//
//  ShellyDailyEnergyTrackerTests.swift
//  EnergieTests
//
//  Created by Tobias Florian on 14.10.26.
//

import Foundation
import Testing
@testable import Energie

private func dateTime(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
    Calendar.current.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
}

@Suite
struct ShellyDailyEnergyTrackerTests {

    // MARK: - `nextReading` (pure computation)

    @Test func firstReadingEverBaselinesWithoutConsumption() {
        let now = dateTime(2026, 10, 14, 10, 0)
        let reading = ShellyDailyEnergyTracker.nextReading(for: nil, total: 1234, now: now)

        #expect(reading.todayWh == 0)
        #expect(reading.lastTotal == 1234)
        #expect(reading.lastTimestamp == now)
        #expect(Calendar.current.isDate(reading.dayStart, inSameDayAs: now))
    }

    @Test func deltaOnTheSameDayAccumulates() {
        let first = ShellyDailyEnergyTracker.nextReading(for: nil, total: 100, now: dateTime(2026, 10, 14, 10, 0))
        let second = ShellyDailyEnergyTracker.nextReading(for: first, total: 150, now: dateTime(2026, 10, 14, 11, 0))

        #expect(second.todayWh == 50)
        #expect(second.lastTotal == 150)
    }

    @Test func counterDropBelowLastTotalIsTreatedAsARebootNotNegativeConsumption() {
        let first = ShellyDailyEnergyTracker.nextReading(for: nil, total: 500, now: dateTime(2026, 10, 14, 10, 0))
        // Device rebooted; `aenergy.total` reset to 0 and has since climbed back to 20.
        let second = ShellyDailyEnergyTracker.nextReading(for: first, total: 20, now: dateTime(2026, 10, 14, 11, 0))

        #expect(second.todayWh == 20)
        #expect(second.lastTotal == 20)
    }

    @Test func deltaAcrossMidnightIsSplitProportionallyByTime() {
        // 22:00 → 02:00 next day, 400 Wh total: 2 of the 4 hours fall after midnight → 200 Wh today.
        let first = ShellyDailyEnergyTracker.nextReading(for: nil, total: 0, now: dateTime(2026, 10, 14, 22, 0))
        let second = ShellyDailyEnergyTracker.nextReading(for: first, total: 400, now: dateTime(2026, 10, 15, 2, 0))

        #expect(second.todayWh == 200)
        #expect(Calendar.current.isDate(second.dayStart, inSameDayAs: dateTime(2026, 10, 15, 0, 0)))
    }

    @Test func multiDayGapAttributesOnlyTheTodaysPortionOfTheInterval() {
        // 3 days (72h) apart, 720 Wh total, with the reading landing 6h into the final day →
        // 6/72 of the delta (60 Wh) counts as "today".
        let first = ShellyDailyEnergyTracker.nextReading(for: nil, total: 0, now: dateTime(2026, 10, 12, 6, 0))
        let second = ShellyDailyEnergyTracker.nextReading(for: first, total: 720, now: dateTime(2026, 10, 15, 6, 0))

        #expect(second.todayWh == 60)
    }

    @Test func newCalendarDayResetsTodayWhBeforeAddingTheNewShare() {
        let first = ShellyDailyEnergyTracker.nextReading(for: nil, total: 100, now: dateTime(2026, 10, 14, 20, 0))
        let yesterday = ShellyDailyEnergyTracker.nextReading(for: first, total: 150, now: dateTime(2026, 10, 14, 22, 0))
        #expect(yesterday.todayWh == 50)

        // 22:00 Oct 14 → 02:00 Oct 15 (4h), 40 Wh: only the 2h after midnight (half) counts for
        // the new day — `yesterday`'s accumulated 50 Wh must not carry over into it.
        let today = ShellyDailyEnergyTracker.nextReading(for: yesterday, total: 190, now: dateTime(2026, 10, 15, 2, 0))
        #expect(today.todayWh == 20)
        #expect(Calendar.current.isDate(today.dayStart, inSameDayAs: dateTime(2026, 10, 15, 0, 0)))
    }

    @Test func clockRunningBackwardsOnlyUpdatesTheCounter() {
        let first = ShellyDailyEnergyTracker.nextReading(for: nil, total: 100, now: dateTime(2026, 10, 14, 11, 0))
        let backwards = ShellyDailyEnergyTracker.nextReading(for: first, total: 105, now: dateTime(2026, 10, 14, 10, 0))

        #expect(backwards.todayWh == first.todayWh)
        #expect(backwards.dayStart == first.dayStart)
        #expect(backwards.lastTimestamp == first.lastTimestamp)
        #expect(backwards.lastTotal == 105)
    }

    // MARK: - `ShellyDailyEnergyTrackerStore` (persistence)

    @Test @MainActor func energyTodayIsNilBeforeTheFirstReading() {
        let store = ShellyDailyEnergyTrackerStore(userDefaults: UserDefaults(suiteName: UUID().uuidString)!)
        #expect(store.energyToday(deviceID: "a1b2c3", now: dateTime(2026, 10, 14, 12, 0)) == nil)
    }

    @Test @MainActor func energyTodayIsNilWhenTheLastReadingWasOnAnEarlierDay() {
        let store = ShellyDailyEnergyTrackerStore(userDefaults: UserDefaults(suiteName: UUID().uuidString)!)
        store.record(deviceID: "a1b2c3", total: 100, at: dateTime(2026, 10, 13, 20, 0))

        #expect(store.energyToday(deviceID: "a1b2c3", now: dateTime(2026, 10, 14, 12, 0)) == nil)
    }

    @Test @MainActor func recordAccumulatesAndSurvivesANewStoreInstance() {
        let userDefaults = UserDefaults(suiteName: UUID().uuidString)!
        let store = ShellyDailyEnergyTrackerStore(userDefaults: userDefaults)
        store.record(deviceID: "a1b2c3", total: 100, at: dateTime(2026, 10, 14, 10, 0))
        store.record(deviceID: "a1b2c3", total: 140, at: dateTime(2026, 10, 14, 11, 0))

        let reloaded = ShellyDailyEnergyTrackerStore(userDefaults: userDefaults)
        #expect(reloaded.energyToday(deviceID: "a1b2c3", now: dateTime(2026, 10, 14, 12, 0)) == 40)
    }

    @Test @MainActor func devicesAreTrackedIndependently() {
        let store = ShellyDailyEnergyTrackerStore(userDefaults: UserDefaults(suiteName: UUID().uuidString)!)
        store.record(deviceID: "a", total: 100, at: dateTime(2026, 10, 14, 10, 0))
        store.record(deviceID: "a", total: 150, at: dateTime(2026, 10, 14, 11, 0))
        store.record(deviceID: "b", total: 10, at: dateTime(2026, 10, 14, 10, 0))

        #expect(store.energyToday(deviceID: "a", now: dateTime(2026, 10, 14, 12, 0)) == 50)
        #expect(store.energyToday(deviceID: "b", now: dateTime(2026, 10, 14, 12, 0)) == 0)
    }
}
