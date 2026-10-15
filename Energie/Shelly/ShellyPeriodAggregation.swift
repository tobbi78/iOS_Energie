//
//  ShellyPeriodAggregation.swift
//  Energie
//
//  Created by Tobias Florian on 15.10.26.
//

import Foundation

/// One stacked series in the Shelly history charts (F14.3) — a saved plug, or the "Weitere"
/// bucket once there are more plugs than categorical colors.
nonisolated struct ShellyHistorySeries: Identifiable, Equatable {
    static let otherID = "__other__"

    let id: String
    let name: String
    /// Index into the fixed categorical palette (`Color.shellySeries(slot:)`), in the order the
    /// plugs are saved — so a plug keeps its color as long as the list order doesn't change
    /// ("color follows the entity, never its rank"). `nil` for the "Weitere" bucket.
    let colorSlot: Int?
}

/// One segment of one stacked bar: a series' energy in a given period.
nonisolated struct ShellyPeriodPoint: Identifiable, Equatable {
    let periodStart: Date
    let seriesID: String
    let seriesName: String
    let energyWh: Double

    /// Stable identity across updates (F10.6 lesson), so Swift Charts can animate bars instead of
    /// redrawing them.
    var id: String { "\(seriesID)-\(periodStart.timeIntervalSinceReferenceDate)" }
}

/// Aggregates stored `ShellyDailySample` rows into the stacked-bar data for the Shelly history
/// charts (F14.3) — pure logic, no IO, analogous to `PVPeriodAggregation`.
///
/// Every period in the range gets a point for every series, zero included, so the x-axis always
/// spans the full range even while the history is still young (it only starts on the day of
/// setup — there's no backfill, unlike Enphase).
enum ShellyPeriodAggregation {
    /// The categorical palette has eight validated slots; past that, the first seven plugs keep
    /// their own color and the rest fold into "Weitere" instead of cycling colors.
    static let maxColorSlots = 8

    static func series(for devices: [ShellyDevice]) -> [ShellyHistorySeries] {
        guard devices.count > maxColorSlots else {
            return devices.enumerated().map { ShellyHistorySeries(id: $1.id, name: $1.name, colorSlot: $0) }
        }
        let named = devices.prefix(maxColorSlots - 1).enumerated().map {
            ShellyHistorySeries(id: $1.id, name: $1.name, colorSlot: $0)
        }
        return named + [ShellyHistorySeries(id: ShellyHistorySeries.otherID, name: "Weitere", colorSlot: nil)]
    }

    /// Today plus the 29 days before it.
    static func lastThirtyDays(
        _ samples: [ShellyDailySample],
        devices: [ShellyDevice],
        now: Date,
        calendar: Calendar = .current
    ) -> [ShellyPeriodPoint] {
        let today = calendar.startOfDay(for: now)
        let dayStarts = (0..<30).reversed().compactMap { calendar.date(byAdding: .day, value: -$0, to: today) }
        return points(samples, devices: devices, periodStarts: dayStarts, component: .day, calendar: calendar)
    }

    /// The current month plus the 11 before it.
    static func lastTwelveMonths(
        _ samples: [ShellyDailySample],
        devices: [ShellyDevice],
        now: Date,
        calendar: Calendar = .current
    ) -> [ShellyPeriodPoint] {
        let currentMonthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
        let monthStarts = (0..<12).reversed().compactMap {
            calendar.date(byAdding: .month, value: -$0, to: currentMonthStart)
        }
        return points(samples, devices: devices, periodStarts: monthStarts, component: .month, calendar: calendar)
    }

    /// One period per calendar year, from the year of the earliest recorded day of a saved plug
    /// through the current year.
    static func years(
        _ samples: [ShellyDailySample],
        devices: [ShellyDevice],
        now: Date,
        calendar: Calendar = .current
    ) -> [ShellyPeriodPoint] {
        let savedIDs = Set(devices.map(\.id))
        let currentYearStart = calendar.date(from: calendar.dateComponents([.year], from: now)) ?? now
        let earliestYearStart = samples
            .filter { savedIDs.contains($0.deviceID) }
            .map(\.date)
            .min()
            .flatMap { calendar.date(from: calendar.dateComponents([.year], from: $0)) }
            ?? currentYearStart

        var yearStarts: [Date] = []
        var yearStart = earliestYearStart
        while yearStart <= currentYearStart {
            yearStarts.append(yearStart)
            guard let next = calendar.date(byAdding: .year, value: 1, to: yearStart) else { break }
            yearStart = next
        }
        return points(samples, devices: devices, periodStarts: yearStarts, component: .year, calendar: calendar)
    }

    /// Sum of all points' energy (Wh) — the headline figure above each chart.
    static func totalWh(_ points: [ShellyPeriodPoint]) -> Double {
        points.reduce(0) { $0 + $1.energyWh }
    }

    private static func points(
        _ samples: [ShellyDailySample],
        devices: [ShellyDevice],
        periodStarts: [Date],
        component: Calendar.Component,
        calendar: Calendar
    ) -> [ShellyPeriodPoint] {
        let series = series(for: devices)
        // Device ID -> series ID. Rows of plugs that are no longer saved map to nothing and are
        // ignored (kept in the store, just not charted).
        let seriesIDByDevice = devices.reduce(into: [String: String]()) { result, device in
            result[device.id] = series.contains { $0.id == device.id } ? device.id : ShellyHistorySeries.otherID
        }

        // Rows not yet merged by `ShellyHistoryRecorder` after a CloudKit sync race could hold
        // the same device/day twice; take the larger one, same conservative rule as the recorder.
        var energyByDeviceDay: [String: [Date: Double]] = [:]
        for sample in samples where seriesIDByDevice[sample.deviceID] != nil {
            let day = calendar.startOfDay(for: sample.date)
            energyByDeviceDay[sample.deviceID, default: [:]][day] = max(
                energyByDeviceDay[sample.deviceID]?[day] ?? 0,
                sample.energyWh
            )
        }

        var sums: [String: [Date: Double]] = [:]
        for (deviceID, days) in energyByDeviceDay {
            guard let seriesID = seriesIDByDevice[deviceID] else { continue }
            for (day, wh) in days {
                guard let periodStart = calendar.dateInterval(of: component, for: day)?.start else { continue }
                sums[seriesID, default: [:]][periodStart, default: 0] += wh
            }
        }

        return periodStarts.flatMap { periodStart in
            series.map { series in
                ShellyPeriodPoint(
                    periodStart: periodStart,
                    seriesID: series.id,
                    seriesName: series.name,
                    energyWh: sums[series.id]?[periodStart] ?? 0
                )
            }
        }
    }
}
