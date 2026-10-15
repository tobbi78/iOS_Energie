//
//  ShellyHistoryRecorder.swift
//  Energie
//
//  Created by Tobias Florian on 15.10.26.
//

import Foundation
import SwiftData

/// Folds each polled `aenergy.total` reading into the stored `ShellyDailySample` rows
/// (BACKLOG.md F14.2). The arithmetic lives in `ShellyEnergyAccumulator`; this type only reads
/// the current baseline from SwiftData and writes the result back.
@MainActor
final class ShellyHistoryRecorder {
    private let modelContext: ModelContext
    private let calendar: Calendar

    init(modelContext: ModelContext, calendar: Calendar = .current) {
        self.modelContext = modelContext
        self.calendar = calendar
    }

    /// Records one reading for `deviceID`. Call only for devices that are online and report an
    /// `aenergy.total` — there's nothing meaningful to record otherwise.
    ///
    /// The baseline is the row with the newest `lastCounterAt` across all of the device's rows,
    /// not necessarily today's — after a gap, it sits on the last day the app polled. The very
    /// first reading creates today's row with 0 Wh plus the baseline, so the history visibly
    /// starts on the day of setup (F14.3).
    func record(deviceID: String, total: Double, at now: Date) {
        let rows = deduplicatedRows(for: deviceID)
        let baseline = rows
            .compactMap { row in row.lastCounterAt.map { (row: row, at: $0) } }
            .max { $0.at < $1.at }

        // Clock running backwards (or a stale duplicate call): only the counter value moves, so
        // the next legitimate reading still diffs against the latest known value — the baseline
        // timestamp stays put rather than regressing (same rule as `ShellyEnergyAccumulator`).
        if let baseline, now <= baseline.at {
            baseline.row.lastCounterWh = total
            return
        }

        var rowsByDay = rows.reduce(into: [Date: ShellyDailySample]()) { result, row in
            result[calendar.startOfDay(for: row.date)] = row
        }
        func row(for day: Date) -> ShellyDailySample {
            if let existing = rowsByDay[day] {
                return existing
            }
            let created = ShellyDailySample(deviceID: deviceID, date: day)
            modelContext.insert(created)
            rowsByDay[day] = created
            return created
        }

        let shares = ShellyEnergyAccumulator.distribute(
            previousTotal: baseline?.row.lastCounterWh,
            previousAt: baseline?.at,
            total: total,
            now: now,
            calendar: calendar
        )
        for (day, wh) in shares {
            row(for: day).energyWh += wh
        }

        let today = row(for: calendar.startOfDay(for: now))
        today.lastCounterWh = total
        today.lastCounterAt = now
    }

    /// The device's rows with at most one per calendar day. Without `@Attribute(.unique)`
    /// (not allowed with CloudKit, F0.2), two devices polling before CloudKit has synced can each
    /// insert their own row for the same day. Their energy can't be reconciled exactly (the
    /// intervals may or may not overlap), so the row with the larger `energyWh` wins —
    /// conservative: slightly under-counting beats double-counting. The newest counter baseline
    /// among the duplicates is carried over onto the survivor so the next delta stays correct.
    private func deduplicatedRows(for deviceID: String) -> [ShellyDailySample] {
        let descriptor = FetchDescriptor<ShellyDailySample>(predicate: #Predicate { $0.deviceID == deviceID })
        guard let rows = try? modelContext.fetch(descriptor) else { return [] }

        let groups = Dictionary(grouping: rows) { calendar.startOfDay(for: $0.date) }
        return groups.values.compactMap { group -> ShellyDailySample? in
            guard let survivor = group.max(by: { $0.energyWh < $1.energyWh }) else { return nil }
            guard group.count > 1 else { return survivor }

            let newestBaseline = group
                .compactMap { row in row.lastCounterAt.map { (row: row, at: $0) } }
                .max { $0.at < $1.at }
            if let newestBaseline, newestBaseline.row !== survivor {
                survivor.lastCounterWh = newestBaseline.row.lastCounterWh
                survivor.lastCounterAt = newestBaseline.at
            }
            for duplicate in group where duplicate !== survivor {
                modelContext.delete(duplicate)
            }
            return survivor
        }
    }
}
