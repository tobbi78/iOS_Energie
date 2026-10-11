//
//  HeatPumpEnergyHistory.swift
//  Energie
//
//  Created by Tobias Florian on 11.10.26.
//

import Foundation

/// Time granularities for the combined Strom-/Wärme-/Effizienz-Verlauf chart (Effizienz-Tab).
/// Deliberately separate from `HeatPumpEfficiencyPeriod` — that type names the four KPI tiles
/// ("Heute", "Letzte 7 Tage", …) for a single current value each, this one drives a history of
/// buckets per granularity.
enum HeatPumpHistoryGranularity: String, CaseIterable, Identifiable {
    case day, week, month, year

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .day: return "Tage"
        case .week: return "Wochen"
        case .month: return "Monate"
        case .year: return "Jahre"
        }
    }

    /// Property name on `heating.power.consumption.total`'s number-array properties. Verified
    /// live on-device 2026-10-11 (see VIESSMANN_API_WERTE.md): index 0 is always the in-progress
    /// current period, so this single array covers both "live" and historical consumption —
    /// unlike production, no separate live fetch is needed at any granularity.
    var consumptionArrayProperty: String { rawValue }

    /// `heating.heat.production.summary.*`'s rolling-window property for "the current,
    /// still-running period" — only needed for `.month`/`.year`, where no `HeatPumpEfficiencySample`
    /// exists yet (snapshots are only captured once the period has fully ended). `.day`/`.week`
    /// don't need this: their sample is continuously upserted, so it already holds today's
    /// live total by the time this is read.
    var currentProductionProperty: String? {
        switch self {
        case .day, .week: return nil
        case .month: return "currentMonth"
        case .year: return "currentYear"
        }
    }

    /// The `HeatPumpEfficiencySample.period` this granularity's historical (non-live) production
    /// values are stored under.
    var samplePeriod: HeatPumpEfficiencyPeriod {
        switch self {
        case .day: return .day
        case .week: return .week
        case .month: return .month
        case .year: return .year
        }
    }

    /// The anchor date for the bucket `index` periods back from `now` (0 = the current,
    /// in-progress period). `.week` steps back in plain 7-day blocks rather than calendar weeks,
    /// matching how Viessmann's own `week` array is laid out (not Mon–Sun weeks).
    func anchorDate(index: Int, now: Date, calendar: Calendar) -> Date? {
        switch self {
        case .day:
            return calendar.date(byAdding: .day, value: -index, to: calendar.startOfDay(for: now))
        case .week:
            return calendar.date(byAdding: .day, value: -index * 7, to: calendar.startOfDay(for: now))
        case .month:
            guard let startOfMonth = calendar.dateInterval(of: .month, for: now)?.start else { return nil }
            return calendar.date(byAdding: .month, value: -index, to: startOfMonth)
        case .year:
            guard let startOfYear = calendar.dateInterval(of: .year, for: now)?.start else { return nil }
            return calendar.date(byAdding: .year, value: -index, to: startOfYear)
        }
    }
}

/// One period's electrical consumption, thermal production, and the derived efficiency, for the
/// combined history chart. Consumption always comes from Viessmann's own array (deeper history,
/// tracked device-side since installation); production/efficiency are capped by how long this
/// app itself has been recording `HeatPumpEfficiencySample` snapshots (since ~2026-10-03) — `nil`
/// where no sample exists yet, rather than a misleading zero. Grows on its own as more snapshots
/// accumulate.
struct HeatPumpEnergyBucket: Identifiable {
    let date: Date
    let isCurrent: Bool
    let consumedKWh: Double?
    let producedKWh: Double?

    var id: Date { date }

    var efficiency: Double? {
        guard let consumedKWh, let producedKWh, consumedKWh > 0 else { return nil }
        return producedKWh / consumedKWh
    }
}

enum HeatPumpEnergyHistory {
    /// Builds one bucket per entry in Viessmann's consumption array (the deeper, device-side
    /// history), with matching production/efficiency filled in from `samples` wherever this app
    /// already recorded that period — see `HeatPumpEnergyBucket`'s doc comment for why the two
    /// have different depth. Returned oldest-first, ready to plot directly.
    static func buckets(
        granularity: HeatPumpHistoryGranularity,
        features: [ViessmannFeatureDTO],
        samples: [HeatPumpEfficiencySample],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [HeatPumpEnergyBucket] {
        let consumedSeries = features.numberArrayValue(
            "heating.power.consumption.total",
            granularity.consumptionArrayProperty
        ) ?? []
        let periodSamples = samples.filter { $0.period == granularity.samplePeriod.rawValue }

        let buckets = consumedSeries.enumerated().compactMap { index, consumed -> HeatPumpEnergyBucket? in
            guard let date = granularity.anchorDate(index: index, now: now, calendar: calendar) else { return nil }
            let produced = producedKWh(
                granularity: granularity,
                index: index,
                date: date,
                features: features,
                periodSamples: periodSamples,
                calendar: calendar
            )
            return HeatPumpEnergyBucket(date: date, isCurrent: index == 0, consumedKWh: consumed, producedKWh: produced)
        }
        return buckets.sorted { $0.date < $1.date }
    }

    private static func producedKWh(
        granularity: HeatPumpHistoryGranularity,
        index: Int,
        date: Date,
        features: [ViessmannFeatureDTO],
        periodSamples: [HeatPumpEfficiencySample],
        calendar: Calendar
    ) -> Double? {
        if index == 0, let liveProperty = granularity.currentProductionProperty {
            return HeatPumpEfficiencyDataSource.sum(
                features: features,
                featureNames: HeatPumpEfficiencyDataSource.productionFeatures,
                property: liveProperty
            )
        }

        switch granularity {
        case .day, .week:
            // Continuously upserted (one row per calendar day) — this also covers index 0 for
            // these two granularities, since today's row already holds the live running total.
            return periodSamples.first { calendar.isDate($0.boundaryDate, inSameDayAs: date) }?.producedKWh
        case .month:
            // A `.month` sample's `boundaryDate` is its *capture* time (right after the month
            // rolled over), representing the month before that — so the sample for the month
            // starting at `date` is the one captured one calendar month later.
            guard let capturedDuring = calendar.date(byAdding: .month, value: 1, to: date) else { return nil }
            return periodSamples.first { calendar.isDate($0.boundaryDate, equalTo: capturedDuring, toGranularity: .month) }?.producedKWh
        case .year:
            guard let capturedDuring = calendar.date(byAdding: .year, value: 1, to: date) else { return nil }
            return periodSamples.first { calendar.isDate($0.boundaryDate, equalTo: capturedDuring, toGranularity: .year) }?.producedKWh
        }
    }
}
