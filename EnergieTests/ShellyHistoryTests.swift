//
//  ShellyHistoryTests.swift
//  EnergieTests
//
//  Created by Tobias Florian on 15.10.26.
//

import Foundation
import SwiftData
import Testing
@testable import Energie

/// F14.2 — counter-difference distribution (`ShellyEnergyAccumulator`) and how
/// `ShellyHistoryRecorder` applies it to stored rows.
@MainActor
struct ShellyHistoryTests {
    /// Fixed Gregorian/UTC calendar so day boundaries don't depend on the machine's time zone.
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    private func startOfDay(_ day: Int) -> Date {
        date(day, 0)
    }

    // MARK: - ShellyEnergyAccumulator

    @Test func firstReadingOnlyBecomesTheBaseline() {
        let shares = ShellyEnergyAccumulator.distribute(
            previousTotal: nil, previousAt: nil, total: 1234, now: date(15, 10), calendar: calendar
        )
        #expect(shares.isEmpty)
    }

    @Test func deltaWithinOneDayGoesEntirelyToThatDay() {
        let shares = ShellyEnergyAccumulator.distribute(
            previousTotal: 1000, previousAt: date(15, 10), total: 1100, now: date(15, 11), calendar: calendar
        )
        #expect(shares == [startOfDay(15): 100])
    }

    @Test func rebootUsesNewCounterValueAsDelta() {
        let shares = ShellyEnergyAccumulator.distribute(
            previousTotal: 5000, previousAt: date(15, 10), total: 30, now: date(15, 11), calendar: calendar
        )
        #expect(shares == [startOfDay(15): 30])
    }

    @Test func clockRunningBackwardsAttributesNothing() {
        let shares = ShellyEnergyAccumulator.distribute(
            previousTotal: 1000, previousAt: date(15, 11), total: 1100, now: date(15, 10), calendar: calendar
        )
        #expect(shares.isEmpty)
    }

    @Test func gapAcrossMidnightIsSplitByTime() {
        // 22:00 -> 02:00: half the interval before midnight, half after.
        let shares = ShellyEnergyAccumulator.distribute(
            previousTotal: 0, previousAt: date(14, 22), total: 400, now: date(15, 2), calendar: calendar
        )
        #expect(shares == [startOfDay(14): 200, startOfDay(15): 200])
    }

    @Test func multiDayGapSpreadsOverEveryDayAndSumsToDelta() throws {
        // 12:00 on the 12th -> 12:00 on the 15th: half a day, two full days, half a day.
        let shares = ShellyEnergyAccumulator.distribute(
            previousTotal: 100, previousAt: date(12, 12), total: 700, now: date(15, 12), calendar: calendar
        )
        #expect(shares.count == 4)
        #expect(abs(try #require(shares[startOfDay(12)]) - 100) < 0.0001)
        #expect(abs(try #require(shares[startOfDay(13)]) - 200) < 0.0001)
        #expect(abs(try #require(shares[startOfDay(14)]) - 200) < 0.0001)
        #expect(abs(try #require(shares[startOfDay(15)]) - 100) < 0.0001)
        #expect(abs(shares.values.reduce(0, +) - 600) < 0.0001)
    }

    // MARK: - ShellyHistoryRecorder

    /// `cloudKitDatabase: .none` explicitly — see SolarModelTests.makeContext for why.
    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: ShellyDailySample.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        )
        return ModelContext(container)
    }

    private func rows(_ context: ModelContext, deviceID: String = "plug") throws -> [ShellyDailySample] {
        try context.fetch(FetchDescriptor<ShellyDailySample>(
            predicate: #Predicate { $0.deviceID == deviceID },
            sortBy: [SortDescriptor(\.date)]
        ))
    }

    @Test func firstRecordCreatesTodaysRowWithBaselineOnly() throws {
        let context = try makeContext()
        let recorder = ShellyHistoryRecorder(modelContext: context, calendar: calendar)

        recorder.record(deviceID: "plug", total: 1000, at: date(15, 10))

        let stored = try rows(context)
        #expect(stored.count == 1)
        #expect(stored.first?.date == startOfDay(15))
        #expect(stored.first?.energyWh == 0)
        #expect(stored.first?.lastCounterWh == 1000)
        #expect(stored.first?.lastCounterAt == date(15, 10))
    }

    @Test func successiveRecordsAccumulateIntoTodaysRow() throws {
        let context = try makeContext()
        let recorder = ShellyHistoryRecorder(modelContext: context, calendar: calendar)

        recorder.record(deviceID: "plug", total: 1000, at: date(15, 10))
        recorder.record(deviceID: "plug", total: 1050, at: date(15, 11))
        recorder.record(deviceID: "plug", total: 1120, at: date(15, 12))

        let stored = try rows(context)
        #expect(stored.count == 1)
        #expect(stored.first?.energyWh == 120)
        #expect(stored.first?.lastCounterWh == 1120)
    }

    @Test func gapCreatesRowsForEveryDayAndMovesBaselineToToday() throws {
        let context = try makeContext()
        let recorder = ShellyHistoryRecorder(modelContext: context, calendar: calendar)

        recorder.record(deviceID: "plug", total: 0, at: date(13, 12))
        recorder.record(deviceID: "plug", total: 480, at: date(15, 12))

        let stored = try rows(context)
        #expect(stored.map(\.date) == [startOfDay(13), startOfDay(14), startOfDay(15)])
        #expect(stored.map(\.energyWh) == [120, 240, 120])
        #expect(stored.last?.lastCounterWh == 480)
        #expect(stored.last?.lastCounterAt == date(15, 12))
    }

    @Test func devicesAreRecordedIndependently() throws {
        let context = try makeContext()
        let recorder = ShellyHistoryRecorder(modelContext: context, calendar: calendar)

        recorder.record(deviceID: "a", total: 100, at: date(15, 10))
        recorder.record(deviceID: "b", total: 9000, at: date(15, 10))
        recorder.record(deviceID: "a", total: 150, at: date(15, 11))
        recorder.record(deviceID: "b", total: 9010, at: date(15, 11))

        #expect(try rows(context, deviceID: "a").map(\.energyWh) == [50])
        #expect(try rows(context, deviceID: "b").map(\.energyWh) == [10])
    }

    @Test func clockRunningBackwardsOnlyUpdatesCounterValue() throws {
        let context = try makeContext()
        let recorder = ShellyHistoryRecorder(modelContext: context, calendar: calendar)

        recorder.record(deviceID: "plug", total: 1000, at: date(15, 11))
        recorder.record(deviceID: "plug", total: 1010, at: date(15, 10))

        let stored = try rows(context)
        #expect(stored.first?.energyWh == 0)
        #expect(stored.first?.lastCounterWh == 1010)
        #expect(stored.first?.lastCounterAt == date(15, 11))
    }

    /// Two devices polled before CloudKit synced and each inserted their own row for today:
    /// the larger one survives (no double counting), and the newest baseline is carried over.
    @Test func duplicateRowsForSameDayAreMergedConservatively() throws {
        let context = try makeContext()
        context.insert(ShellyDailySample(
            deviceID: "plug", date: startOfDay(15), energyWh: 300, lastCounterWh: 1300, lastCounterAt: date(15, 9)
        ))
        context.insert(ShellyDailySample(
            deviceID: "plug", date: startOfDay(15), energyWh: 200, lastCounterWh: 1400, lastCounterAt: date(15, 10)
        ))
        let recorder = ShellyHistoryRecorder(modelContext: context, calendar: calendar)

        recorder.record(deviceID: "plug", total: 1450, at: date(15, 11))

        let stored = try rows(context)
        #expect(stored.count == 1)
        #expect(stored.first?.energyWh == 350)
        #expect(stored.first?.lastCounterWh == 1450)
    }
}
