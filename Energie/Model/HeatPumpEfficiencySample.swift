//
//  HeatPumpEfficiencySample.swift
//  Energie
//
//  Created by Tobias Florian on 03.10.26.
//

import Foundation
import SwiftData

/// One periodic energy snapshot (electrical consumption + thermal production, and the derived
/// efficiency ratio) for the heat pump. `.day`/`.week` rows are upserted on every poll
/// (overwritten until the day ends); `.month`/`.year` rows are written once, at the first poll
/// after their boundary — see `HeatPumpEfficiencyTracker` for exactly when. Ported from the
/// macOS sibling project's `EfficiencySample`.
///
/// `period`/`boundaryDate` gained declaration-site defaults for CloudKit compatibility (F0.2):
/// CloudKit-backed SwiftData models require **every** non-optional property to have a default at
/// its declaration, not just in `init` — the same trap F8.2 already documents for plain
/// lightweight migration, now a hard requirement rather than just a best practice.
@Model
final class HeatPumpEfficiencySample {
    var period: String = HeatPumpEfficiencyPeriod.day.rawValue
    var boundaryDate: Date = Date.distantPast
    var consumedKWh: Double = 0
    var producedKWh: Double = 0

    init(period: HeatPumpEfficiencyPeriod, boundaryDate: Date, consumedKWh: Double, producedKWh: Double) {
        self.period = period.rawValue
        self.boundaryDate = boundaryDate
        self.consumedKWh = consumedKWh
        self.producedKWh = producedKWh
    }

    var efficiency: Double {
        consumedKWh > 0 ? producedKWh / consumedKWh : 0
    }
}
