//
//  PVBackfillPlanner.swift
//  Energie
//
//  Created by Tobias Florian on 30.09.26.
//

import Foundation

/// Pure gap-detection logic for the PV history backfill (BACKLOG.md F3.2), kept free of
/// SwiftData/network so it can be unit-tested directly (see "Engineering-Konventionen" in
/// BACKLOG.md: pure logic types without UI/IO dependencies).
enum PVBackfillPlanner {
    /// Fallback window when the system's commissioning date (`operational_at`) isn't known yet.
    static let fallbackWindowDays = 30

    /// First day to request from the `_lifetime` endpoints.
    static func backfillStartDay(operationalAt: Date?, today: Date, calendar: Calendar = .current) -> Date {
        if let operationalAt {
            return calendar.startOfDay(for: operationalAt)
        }
        return calendar.date(byAdding: .day, value: -fallbackWindowDays, to: calendar.startOfDay(for: today))
            ?? calendar.startOfDay(for: today)
    }

    /// Days strictly before `today` that are missing from `existingDays` — today itself is
    /// deliberately excluded since the live poll (not backfill) owns today's row.
    static func missingDays(existingDays: Set<Date>, from startDay: Date, today: Date, calendar: Calendar = .current) -> [Date] {
        let startDay = calendar.startOfDay(for: startDay)
        let today = calendar.startOfDay(for: today)
        guard startDay < today else { return [] }

        var result: [Date] = []
        var day = startDay
        while day < today {
            if !existingDays.contains(day) {
                result.append(day)
            }
            day = calendar.date(byAdding: .day, value: 1, to: day) ?? today
        }
        return result
    }
}
