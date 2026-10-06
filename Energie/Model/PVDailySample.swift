//
//  PVDailySample.swift
//  Energie
//
//  Created by Tobias Florian on 30.09.26.
//

import Foundation
import SwiftData

extension EnergieSchemaV1 {

/// One row per calendar day of PV data, upserted on every poll (see BACKLOG.md Epic 3).
///
/// Synced via CloudKit (Epic 0) and versioned through `EnergieSchemaV1` (F8.1). All properties
/// have defaults at their declaration, not just in `init`, so that CloudKit/lightweight
/// migration never hits the trap documented in BACKLOG.md F8.2.
@Model
final class PVDailySample {
    var date: Date = Date.distantPast
    var producedWh: Double = 0
    var consumedWh: Double = 0
    var importedWh: Double = 0
    var exportedWh: Double = 0
    var batterySocPercent: Double?
    var batteryChargedWh: Double = 0
    var batteryDischargedWh: Double = 0
    /// `false` while these are today's live-polled, not-yet-final values (see BACKLOG.md F3.3).
    /// The daily finalize pass that flips this to `true` is a later Epic 3 branch, not part of
    /// this first slice.
    var isFinal: Bool = false

    init(
        date: Date,
        producedWh: Double = 0,
        consumedWh: Double = 0,
        importedWh: Double = 0,
        exportedWh: Double = 0,
        batterySocPercent: Double? = nil,
        batteryChargedWh: Double = 0,
        batteryDischargedWh: Double = 0,
        isFinal: Bool = false
    ) {
        self.date = date
        self.producedWh = producedWh
        self.consumedWh = consumedWh
        self.importedWh = importedWh
        self.exportedWh = exportedWh
        self.batterySocPercent = batterySocPercent
        self.batteryChargedWh = batteryChargedWh
        self.batteryDischargedWh = batteryDischargedWh
        self.isFinal = isFinal
    }

    /// Autarkiegrad: share of consumption covered without drawing from the grid. `nil` when
    /// there was no consumption to relate the import to.
    var selfSufficiencyRate: Double? {
        consumedWh > 0 ? (consumedWh - importedWh) / consumedWh : nil
    }

    func estimatedFeedInRevenue(tariffPerKWh: Double) -> Double {
        exportedWh / 1000 * tariffPerKWh
    }

    /// Copies every live-polled metric from `other` onto `self` — used by
    /// `SolarModel.upsertToday(_:)` when today's row already exists, so a future new metric only
    /// needs to be added in one place instead of at every call site. `date` and `isFinal` are
    /// deliberately excluded: upserting today's row never changes either.
    func update(from other: PVDailySample) {
        producedWh = other.producedWh
        consumedWh = other.consumedWh
        importedWh = other.importedWh
        exportedWh = other.exportedWh
        batterySocPercent = other.batterySocPercent
        batteryChargedWh = other.batteryChargedWh
        batteryDischargedWh = other.batteryDischargedWh
    }
}

}
