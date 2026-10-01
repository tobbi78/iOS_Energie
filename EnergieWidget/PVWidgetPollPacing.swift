//
//  PVWidgetPollPacing.swift
//  EnergieWidget
//
//  Created by Tobias Florian on 01.10.26.
//
//  Spreads the remaining Enphase monthly request budget evenly over the rest of the month
//  instead of polling on a fixed short interval (F4.2 — originally deferred in BACKLOG.md for
//  lack of a recurring poll loop to pace; the widget's TimelineProvider is that loop).
//
//  One widget poll costs `requestsPerPoll` requests (summary + consumption + import + battery,
//  see PVWidgetDataSource). At a naive fixed 30-minute cadence that's ~5,760 requests/month —
//  nearly 6x the 1000/month limit. This paces polls so the budget actually lasts the month.
//

import Foundation

enum PVWidgetPollPacing {
    static let requestsPerPoll = 4
    /// Matches EnphaseRequestBudget's default reserve, kept here too so pacing and the hard
    /// gate agree on how much budget is actually "available" for live polling.
    static let monthlyReserve = 20
    /// Never poll more often than this, even with a nearly-untouched budget.
    static let minimumInterval: TimeInterval = 15 * 60
    /// Used when the remaining budget is already used up (or on a date-math edge case) — matches
    /// the "alle 4-5 Stunden" fallback described in BACKLOG.md's original F4.2 design.
    static let fallbackInterval: TimeInterval = 4 * 60 * 60

    /// How long to wait before the next poll, given how much of the monthly budget is already
    /// used. Evenly divides the remaining budget (minus reserve) across the time left in the
    /// current calendar month.
    static func nextPollDelay(
        usedThisMonth: Int,
        monthlyLimit: Int,
        now: Date,
        calendar: Calendar = .current
    ) -> TimeInterval {
        let usableBudget = max(0, monthlyLimit - monthlyReserve - usedThisMonth)
        let remainingPolls = usableBudget / requestsPerPoll
        guard remainingPolls > 0 else { return fallbackInterval }

        guard let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: now)),
              let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart) else {
            return fallbackInterval
        }

        let secondsRemainingInMonth = monthEnd.timeIntervalSince(now)
        guard secondsRemainingInMonth > 0 else { return minimumInterval }

        let idealInterval = secondsRemainingInMonth / Double(remainingPolls)
        return max(minimumInterval, idealInterval)
    }
}
