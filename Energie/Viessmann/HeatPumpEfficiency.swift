//
//  HeatPumpEfficiency.swift
//  Energie
//
//  Created by Tobias Florian on 03.10.26.
//

import Foundation

/// The four energy windows shown for the heat pump. Named after the snapshot rhythm, not the
/// source property directly, since the display label and cadence are what the UI actually cares
/// about. Ported as-is from the macOS sibling project's `EfficiencyPeriod`
/// (https://github.com/tobbi78/Dashboard_Waermepumpe, `EfficiencyTracker.swift`).
enum HeatPumpEfficiencyPeriod: String, CaseIterable, Identifiable {
    case day, week, month, year

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .day: return "Heute"
        case .week: return "Letzte 7 Tage"
        case .month: return "Letzter Monat"
        case .year: return "Letztes Jahr"
        }
    }

    /// The Viessmann-precomputed rolling-window property that already matches this period — no
    /// need to sum our own daily deltas (see VIESSMANN_API_WERTE.md, "Stromverbrauch & Effizienz").
    var sourceProperty: String {
        switch self {
        case .day: return "currentDay"
        case .week: return "lastSevenDays"
        case .month: return "lastMonth"
        case .year: return "lastYear"
        }
    }

    /// `.day`/`.week` are upserted on every poll (their Viessmann value keeps climbing until the
    /// window rolls over, so there's no fixed "boundary" to gate on). `.month`/`.year` are
    /// captured once, at the first poll after their calendar boundary — see
    /// `HeatPumpEfficiencyTracker.periodsNeedingSnapshot`.
    var isContinuous: Bool {
        switch self {
        case .day, .week: return true
        case .month, .year: return false
        }
    }
}

/// Reads the combined (heating + dhw + cooling) electrical and thermal energy for a given
/// Viessmann rolling-window property out of a features poll. Deliberately excludes the electric
/// heating rod (`heatingRod.power.consumption.*`) from the electrical side — it's a separate
/// auxiliary heat source, not heat-pump output (see VIESSMANN_API_WERTE.md, "bewusst nicht in
/// der Effizienz-Berechnung berücksichtigt").
enum HeatPumpEfficiencyDataSource {
    static let consumptionFeatures = [
        "heating.power.consumption.summary.heating",
        "heating.power.consumption.summary.dhw",
        "heating.power.consumption.summary.cooling",
    ]
    static let productionFeatures = [
        "heating.heat.production.summary.heating",
        "heating.heat.production.summary.dhw",
        "heating.heat.production.summary.cooling",
    ]

    static func sum(features: [ViessmannFeatureDTO], featureNames: [String], property: String) -> Double {
        features
            .filter { featureNames.contains($0.feature) }
            .compactMap { $0.properties[property]?.value.numericValue }
            .reduce(0, +)
    }

    /// Computes the ratio live from a features poll, for callers that don't have (or don't want
    /// to wait for) a persisted `HeatPumpEfficiencySample` — e.g. the overview KPI tiles before
    /// the first snapshot ever ran.
    static func liveEfficiency(features: [ViessmannFeatureDTO], period: HeatPumpEfficiencyPeriod) -> Double? {
        let consumed = sum(features: features, featureNames: consumptionFeatures, property: period.sourceProperty)
        let produced = sum(features: features, featureNames: productionFeatures, property: period.sourceProperty)
        return consumed > 0 ? produced / consumed : nil
    }
}

/// Decides which non-continuous periods (`.month`/`.year`) are due for a one-time snapshot. Pure
/// and testable on purpose — the actual fetching/inserting happens in `HeatPumpModel`, which has
/// the `ModelContext`. `.day`/`.week` don't go through here: they're upserted unconditionally on
/// every poll.
enum HeatPumpEfficiencyTracker {
    /// One-time snapshots (`.month`/`.year`) never happen before this local hour, even if the
    /// new month/year has already started — a buffer against midnight rollover/delayed Viessmann
    /// updates.
    static let earliestSnapshotHour = 6

    /// - Parameters:
    ///   - now: the current poll's timestamp.
    ///   - lastSnapshotDates: the boundaryDate of the most recent stored sample per period, or
    ///     nil if none exists yet (in which case a snapshot is always due, subject to the hour
    ///     floor).
    static func periodsNeedingSnapshot(
        now: Date,
        lastSnapshotDates: [HeatPumpEfficiencyPeriod: Date],
        calendar: Calendar = .current
    ) -> [HeatPumpEfficiencyPeriod] {
        guard calendar.component(.hour, from: now) >= earliestSnapshotHour else { return [] }

        var due: [HeatPumpEfficiencyPeriod] = []
        if isNewMonth(now: now, last: lastSnapshotDates[.month], calendar: calendar) {
            due.append(.month)
        }
        if isNewYear(now: now, last: lastSnapshotDates[.year], calendar: calendar) {
            due.append(.year)
        }
        return due
    }

    private static func isNewMonth(now: Date, last: Date?, calendar: Calendar) -> Bool {
        guard let last else { return true }
        return calendar.component(.year, from: last) != calendar.component(.year, from: now)
            || calendar.component(.month, from: last) != calendar.component(.month, from: now)
    }

    private static func isNewYear(now: Date, last: Date?, calendar: Calendar) -> Bool {
        guard let last else { return true }
        return calendar.component(.year, from: last) != calendar.component(.year, from: now)
    }
}
