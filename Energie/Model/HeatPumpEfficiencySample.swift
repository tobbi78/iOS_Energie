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
@Model
final class HeatPumpEfficiencySample {
    var period: String
    var boundaryDate: Date
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
