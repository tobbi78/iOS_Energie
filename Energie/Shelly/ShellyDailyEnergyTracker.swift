//
//  ShellyDailyEnergyTracker.swift
//  Energie
//
//  Created by Tobias Florian on 14.10.26.
//

import Foundation

/// Snapshot of what's known about one plug's energy counter as of the last successful status
/// fetch (F12.3). `aenergy.total` (SHELLY_API_WERTE.md) is cumulative since the device's last
/// reboot, not a daily figure — this is the running state `ShellyDailyEnergyTracker` folds each
/// new reading into to derive "today's" consumption.
nonisolated struct ShellyEnergyReading: Codable, Equatable {
    /// Start of the calendar day `todayWh` currently accumulates for. Compared against the
    /// current day on the next reading to decide whether to reset `todayWh` to 0.
    var dayStart: Date
    /// Energy attributed to `dayStart`'s day so far (Wh).
    var todayWh: Double
    /// The raw counter value this reading was computed from — kept so the next reading can take
    /// a difference, and so a reboot (counter dropping below this) can be recognized.
    var lastTotal: Double
    /// When `lastTotal` was observed — the other end of the interval a later reading's delta
    /// gets split across, for F12.3's "no background poll yet" day-boundary estimate.
    var lastTimestamp: Date
}

/// Derives a "today" energy figure (Wh) per plug from `Switch.GetStatus`'s cumulative
/// `aenergy.total` (F12.3) — `ShellyDeviceStatus` has no daily counter at all (unlike Enphase's
/// `energy_today`), so the app has to build one itself from successive readings.
///
/// There's no background poll yet (F16.1 is still open — see `ShellyPlugStatusLoader`'s doc
/// comment), so a reading can be arbitrarily far from the previous one, possibly spanning
/// midnight or several days. Rather than discard the overnight gap (undercounting "today") or
/// credit all of it to today (overcounting after a long pause), the delta since the last reading
/// is split proportionally by how much of the `[lastTimestamp, now]` interval falls on each side
/// of the day boundary — the best estimate available without a continuous counter.
///
/// Pure, testable computation lives in `nextReading(for:total:now:calendar:)`; the `@Observable`
/// class below only adds persistence, following `ShellyDeviceList`'s App-Group-`UserDefaults`
/// pattern (so a future widget, F16.3, can read the same per-device totals).
enum ShellyDailyEnergyTracker {
    /// Computes the next `ShellyEnergyReading` for one device from its previous reading (`nil`
    /// if this is the first ever reading), the freshly fetched `total` (Wh), and `now`.
    ///
    /// - A missing `previous` reading makes `total` the new baseline with `todayWh == 0` — there
    ///   is nothing to take a difference against yet.
    /// - `total < previous.lastTotal` means the device rebooted (`aenergy.total` resets to 0 on
    ///   restart, BACKLOG F12.3) — the counter dropping is itself the consumption since the
    ///   reboot, which is never negative, so `total` itself becomes the delta rather than
    ///   `total - previous.lastTotal`.
    /// - `now <= previous.lastTimestamp` (clock skew, or a second concurrent refresh) adds no
    ///   consumption at all — there's no positive time span to split a delta across, and
    ///   double-counting the same interval would be worse than momentarily under-counting it.
    ///   Only `lastTotal` is updated so the next legitimate reading still diffs against the
    ///   latest known counter value; `dayStart`/`todayWh`/`lastTimestamp` carry over unchanged.
    /// - Otherwise, the delta is split across `[previous.lastTimestamp, now)` proportionally to
    ///   how much of that interval falls before vs. after the most recent midnight crossed by
    ///   it, carrying over `todayWh` from `previous` only if `previous.dayStart` is still today.
    static func nextReading(
        for previous: ShellyEnergyReading?,
        total: Double,
        now: Date,
        calendar: Calendar = .current
    ) -> ShellyEnergyReading {
        let today = calendar.startOfDay(for: now)

        guard let previous else {
            return ShellyEnergyReading(dayStart: today, todayWh: 0, lastTotal: total, lastTimestamp: now)
        }
        guard now > previous.lastTimestamp else {
            // Clock running backwards, or a duplicate call with a stale `now` — only the counter
            // itself is updated so the next legitimate reading still diffs against the latest
            // known value; `todayWh`/`dayStart` carry over untouched, and `lastTimestamp` stays
            // at `previous.lastTimestamp` rather than regressing, so that reading's `[lastTimestamp,
            // now)` interval is never computed against an earlier point than it already was.
            return ShellyEnergyReading(
                dayStart: previous.dayStart,
                todayWh: previous.todayWh,
                lastTotal: total,
                lastTimestamp: previous.lastTimestamp
            )
        }

        let delta = total >= previous.lastTotal ? total - previous.lastTotal : total
        let todaysShare = delta * overlapFraction(
            intervalStart: previous.lastTimestamp,
            intervalEnd: now,
            dayStart: today,
            calendar: calendar
        )

        let carriedOverTodayWh = calendar.isDate(previous.dayStart, inSameDayAs: today) ? previous.todayWh : 0
        return ShellyEnergyReading(
            dayStart: today,
            todayWh: carriedOverTodayWh + todaysShare,
            lastTotal: total,
            lastTimestamp: now
        )
    }

    /// Fraction of `[intervalStart, intervalEnd]` that falls on `dayStart`'s calendar day —
    /// `0` if the interval never reaches that day, `1` if it's entirely within it, otherwise the
    /// proportional overlap. `intervalEnd > intervalStart` is guaranteed by the caller.
    private static func overlapFraction(
        intervalStart: Date,
        intervalEnd: Date,
        dayStart: Date,
        calendar: Calendar
    ) -> Double {
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return 1 }
        let overlapStart = max(intervalStart, dayStart)
        let overlapEnd = min(intervalEnd, dayEnd)
        guard overlapEnd > overlapStart else { return 0 }

        let totalSpan = intervalEnd.timeIntervalSince(intervalStart)
        guard totalSpan > 0 else { return 1 }
        return overlapEnd.timeIntervalSince(overlapStart) / totalSpan
    }
}

/// Persists the latest `ShellyEnergyReading` per device ID so F12.3's "today" figure survives
/// app relaunches (otherwise every cold start would re-baseline at `todayWh == 0`). `@Observable`/
/// `@MainActor` like `ShellyDeviceList`, and backed by the same shared App Group `UserDefaults`
/// rather than plain `.standard`, for the same future-widget reason (F16.3).
@Observable
@MainActor
final class ShellyDailyEnergyTrackerStore {
    static let readingsKey = "ShellyDailyEnergyTrackerStore.readings"

    private let userDefaults: UserDefaults
    private let calendar: Calendar
    private(set) var readings: [String: ShellyEnergyReading]

    init(userDefaults: UserDefaults = SharedAppGroup.userDefaults, calendar: Calendar = .current) {
        self.userDefaults = userDefaults
        self.calendar = calendar
        if let data = userDefaults.data(forKey: Self.readingsKey),
           let decoded = try? JSONDecoder().decode([String: ShellyEnergyReading].self, from: data) {
            readings = decoded
        } else {
            readings = [:]
        }
    }

    /// Folds a freshly fetched `total` (Wh) for `deviceID` into its running reading and persists
    /// the result. Call only for devices that are online and report a known `aenergy.total` —
    /// there's nothing meaningful to record otherwise.
    func record(deviceID: String, total: Double, at now: Date) {
        readings[deviceID] = ShellyDailyEnergyTracker.nextReading(
            for: readings[deviceID],
            total: total,
            now: now,
            calendar: calendar
        )
        persist()
    }

    /// Today's consumption (Wh) for `deviceID`, or `nil` if there's no reading yet, or the last
    /// recorded reading is for an earlier day (e.g. the app wasn't opened at all today) — in
    /// that case "today" simply isn't known rather than being presented as 0.
    func energyToday(deviceID: String, now: Date) -> Double? {
        guard let reading = readings[deviceID], calendar.isDate(reading.dayStart, inSameDayAs: now) else {
            return nil
        }
        return reading.todayWh
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(readings) else { return }
        userDefaults.set(data, forKey: Self.readingsKey)
    }
}
