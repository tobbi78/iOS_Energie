//
//  PVYearlySample.swift
//  Energie
//
//  Created by Tobias Florian on 30.09.26.
//

import Foundation
import SwiftData

/// Yearly totals that daily rows older than a year get folded into (F3.6, "Datenaufbewahrung/
/// Pruning" in BACKLOG.md) — keeps the local database from growing without bound while still
/// showing a full yearly history in the charts. All properties have defaults at their
/// declaration (see BACKLOG.md F8.2).
@Model
final class PVYearlySample {
    var yearStart: Date = Date.distantPast
    var producedWh: Double = 0
    var consumedWh: Double = 0
    var importedWh: Double = 0
    var exportedWh: Double = 0
    var batteryChargedWh: Double = 0
    var batteryDischargedWh: Double = 0

    init(
        yearStart: Date,
        producedWh: Double = 0,
        consumedWh: Double = 0,
        importedWh: Double = 0,
        exportedWh: Double = 0,
        batteryChargedWh: Double = 0,
        batteryDischargedWh: Double = 0
    ) {
        self.yearStart = yearStart
        self.producedWh = producedWh
        self.consumedWh = consumedWh
        self.importedWh = importedWh
        self.exportedWh = exportedWh
        self.batteryChargedWh = batteryChargedWh
        self.batteryDischargedWh = batteryDischargedWh
    }

    /// Creates a new yearly archive by copying every metric from an aggregated `PVPeriodTotal` —
    /// used by `SolarModel.pruneOldDailySamplesIfNeeded()` when a given year has no existing
    /// archive yet, so a future new metric only needs to be added in one place.
    convenience init(yearStart: Date, total: PVPeriodTotal) {
        self.init(
            yearStart: yearStart,
            producedWh: total.producedWh,
            consumedWh: total.consumedWh,
            importedWh: total.importedWh,
            exportedWh: total.exportedWh,
            batteryChargedWh: total.batteryChargedWh,
            batteryDischargedWh: total.batteryDischargedWh
        )
    }

    /// Adds every metric from `total` onto `self` — used by the same pruning pass to fold
    /// another year's worth of pruned daily rows into an already-existing yearly archive.
    func accumulate(_ total: PVPeriodTotal) {
        producedWh += total.producedWh
        consumedWh += total.consumedWh
        importedWh += total.importedWh
        exportedWh += total.exportedWh
        batteryChargedWh += total.batteryChargedWh
        batteryDischargedWh += total.batteryDischargedWh
    }
}
