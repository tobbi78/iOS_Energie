//
//  PVHistoryPruner.swift
//  Energie
//
//  Created by Tobias Florian on 30.09.26.
//

import Foundation

/// Pure grouping/eligibility logic for folding old daily rows into yearly sums (F3.6). Kept
/// separate from `SolarModel` so it can be unit-tested without SwiftData (see BACKLOG.md
/// "Engineering-Konventionen").
enum PVHistoryPruner {
    /// Daily rows older than this get aggregated away.
    static let maxDailyRowAgeDays = 365

    static func isEligibleForPruning(date: Date, now: Date, calendar: Calendar = .current) -> Bool {
        guard let cutoff = calendar.date(byAdding: .day, value: -maxDailyRowAgeDays, to: calendar.startOfDay(for: now)) else {
            return false
        }
        return date < cutoff
    }

    /// Groups samples by the start of their calendar year.
    static func groupByYear(_ samples: [PVDailySample], calendar: Calendar = .current) -> [Date: [PVDailySample]] {
        Dictionary(grouping: samples) { sample in
            calendar.date(from: calendar.dateComponents([.year], from: sample.date)) ?? sample.date
        }
    }
}
