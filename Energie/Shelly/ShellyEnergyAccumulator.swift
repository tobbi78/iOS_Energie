//
//  ShellyEnergyAccumulator.swift
//  Energie
//
//  Created by Tobias Florian on 15.10.26.
//

import Foundation

/// Pure counter-difference logic for the Shelly plugs' own history (BACKLOG.md F14.2) — no
/// SwiftData, so it's unit-testable on its own (see "Engineering-Konventionen", same as
/// `PVHistoryPruner`/`PVPeriodAggregation`). `ShellyHistoryRecorder` applies its result to the
/// stored `ShellyDailySample` rows.
///
/// `aenergy.total` is cumulative since the device's last reboot, and polling only runs while the
/// app is in the foreground (`ShellyModel`), so two readings can be hours or days apart. Rather
/// than credit a whole overnight/multi-day gap to the day of the next poll, the delta is spread
/// over every calendar day in `[previousAt, now]` proportionally to how much of the interval
/// falls on it — an estimate per day, but the shares always add up to exactly the measured delta.
/// The overlap computation follows the removed F12.3 `ShellyDailyEnergyTracker`, generalized from
/// "today's share only" to every day of the gap.
enum ShellyEnergyAccumulator {
    /// Splits the consumption since the previous reading across calendar days.
    ///
    /// - Returns: Start of day → Wh attributed to that day. Days with no overlap are omitted;
    ///   empty when there's nothing to attribute:
    ///   - no previous reading yet — `total` only becomes the baseline (F12.3 lesson: the first
    ///     reading can't say anything about consumption, so it isn't reported as 0 either),
    ///   - `now <= previousAt` (clock skew, or a duplicate call with a stale `now`) — there's no
    ///     positive time span to spread a delta across, and double-counting an interval would be
    ///     worse than momentarily under-counting it,
    ///   - a zero delta.
    ///
    /// `total < previousTotal` means the device rebooted (`aenergy.total` restarts at 0): the new
    /// counter value itself is the consumption since the reboot, never a negative difference.
    static func distribute(
        previousTotal: Double?,
        previousAt: Date?,
        total: Double,
        now: Date,
        calendar: Calendar = .current
    ) -> [Date: Double] {
        guard let previousTotal, let previousAt, now > previousAt else { return [:] }

        let delta = total >= previousTotal ? total - previousTotal : total
        guard delta > 0 else { return [:] }

        let span = now.timeIntervalSince(previousAt)
        var shares: [Date: Double] = [:]
        var dayStart = calendar.startOfDay(for: previousAt)
        while dayStart < now {
            guard let nextDayStart = calendar.date(byAdding: .day, value: 1, to: dayStart) else { break }
            let overlap = min(now, nextDayStart).timeIntervalSince(max(previousAt, dayStart))
            if overlap > 0 {
                shares[dayStart] = delta * overlap / span
            }
            dayStart = nextDayStart
        }
        return shares
    }
}
