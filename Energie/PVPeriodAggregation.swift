//
//  PVPeriodAggregation.swift
//  Energie
//
//  Created by Tobias Florian on 30.09.26.
//

import Foundation

/// One aggregated period (month or year) for the history charts (F3.4).
struct PVPeriodTotal: Identifiable, Equatable {
    var id: Date { periodStart }

    let periodStart: Date
    let producedWh: Double
    let consumedWh: Double
    let importedWh: Double
    let exportedWh: Double
    let batteryChargedWh: Double
    let batteryDischargedWh: Double
    /// Whether this period is still ongoing (current month/year) — charts can use this to, for
    /// example, style the running period differently since its total is necessarily partial.
    let isRunning: Bool
}

/// Aggregates locally stored `PVDailySample` rows into months/years — pure logic, no additional
/// API calls (see BACKLOG.md F3.4/"Engineering-Konventionen": pure, testable, no IO).
enum PVPeriodAggregation {
    /// Always exactly 12 entries (current month + 11 previous), including empty months.
    static func lastTwelveMonths(_ samples: [PVDailySample], now: Date, calendar: Calendar = .current) -> [PVPeriodTotal] {
        let currentMonthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
        let monthStarts = (0..<12).reversed().compactMap { offset in
            calendar.date(byAdding: .month, value: -offset, to: currentMonthStart)
        }
        return monthStarts.map { monthStart in
            let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart) ?? monthStart
            return total(of: samples, from: monthStart, to: monthEnd, isRunning: monthStart == currentMonthStart)
        }
    }

    /// One entry per calendar year from the earliest known day (daily rows or already-pruned
    /// `PVYearlySample` archives, whichever is earlier) through the current year. A year that
    /// was partially pruned (F3.6) has its archived and still-raw portions summed, so the total
    /// stays correct even though the underlying rows now live in two places.
    static func years(
        _ samples: [PVDailySample],
        archivedYears: [PVYearlySample] = [],
        now: Date,
        calendar: Calendar = .current
    ) -> [PVPeriodTotal] {
        let currentYearStart = calendar.date(from: calendar.dateComponents([.year], from: now)) ?? now
        let earliestFromDaily = samples.map(\.date).min().flatMap {
            calendar.date(from: calendar.dateComponents([.year], from: $0))
        }
        let earliestFromArchive = archivedYears.map(\.yearStart).min()
        let earliestYearStart = [earliestFromDaily, earliestFromArchive].compactMap { $0 }.min() ?? currentYearStart

        var yearStarts: [Date] = []
        var yearStart = earliestYearStart
        while yearStart <= currentYearStart {
            yearStarts.append(yearStart)
            guard let next = calendar.date(byAdding: .year, value: 1, to: yearStart) else { break }
            yearStart = next
        }

        return yearStarts.map { yearStart in
            let yearEnd = calendar.date(byAdding: .year, value: 1, to: yearStart) ?? yearStart
            let fromDailyRows = total(of: samples, from: yearStart, to: yearEnd, isRunning: yearStart == currentYearStart)
            let archived = archivedYears.first { calendar.isDate($0.yearStart, equalTo: yearStart, toGranularity: .year) }

            return PVPeriodTotal(
                periodStart: yearStart,
                producedWh: fromDailyRows.producedWh + (archived?.producedWh ?? 0),
                consumedWh: fromDailyRows.consumedWh + (archived?.consumedWh ?? 0),
                importedWh: fromDailyRows.importedWh + (archived?.importedWh ?? 0),
                exportedWh: fromDailyRows.exportedWh + (archived?.exportedWh ?? 0),
                batteryChargedWh: fromDailyRows.batteryChargedWh + (archived?.batteryChargedWh ?? 0),
                batteryDischargedWh: fromDailyRows.batteryDischargedWh + (archived?.batteryDischargedWh ?? 0),
                isRunning: yearStart == currentYearStart
            )
        }
    }

    static func total(of samples: [PVDailySample], from start: Date, to end: Date, isRunning: Bool) -> PVPeriodTotal {
        let samplesInRange = samples.filter { $0.date >= start && $0.date < end }
        return PVPeriodTotal(
            periodStart: start,
            producedWh: samplesInRange.reduce(0) { $0 + $1.producedWh },
            consumedWh: samplesInRange.reduce(0) { $0 + $1.consumedWh },
            importedWh: samplesInRange.reduce(0) { $0 + $1.importedWh },
            exportedWh: samplesInRange.reduce(0) { $0 + $1.exportedWh },
            batteryChargedWh: samplesInRange.reduce(0) { $0 + $1.batteryChargedWh },
            batteryDischargedWh: samplesInRange.reduce(0) { $0 + $1.batteryDischargedWh },
            isRunning: isRunning
        )
    }
}
