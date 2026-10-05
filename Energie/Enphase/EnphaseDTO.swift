//
//  EnphaseDTO.swift
//  Energie
//
//  Created by Tobias Florian on 30.09.26.
//

import Foundation

/// Decoding types for the Enphase Monitoring API v4 responses used by `EnphaseClient`.
/// Field meanings/units: see ENPHASE_API_WERTE.md.

extension JSONDecoder {
    /// Reused across requests instead of allocating a fresh `JSONDecoder()` for every one —
    /// mirrors `JSONDecoder.viessmann` (ViessmannDTO.swift). No custom strategy needed: none of
    /// the Enphase response types decode `Date` directly (Unix-second fields are plain `Int`,
    /// converted to `Date` by hand where needed, e.g. `EnphaseSystemDTO.operationalAt`).
    static let enphase = JSONDecoder()
}

struct EnphaseSystemsResponse: Decodable {
    let systems: [EnphaseSystemDTO]
}

struct EnphaseSystemDTO: Decodable {
    let systemID: Int
    /// Unix seconds; commissioning/grid-connection date. Used as the backfill start point
    /// (F3.2) instead of an arbitrary fixed window.
    let operationalAt: Int?

    enum CodingKeys: String, CodingKey {
        case systemID = "system_id"
        case operationalAt = "operational_at"
    }
}

struct EnphaseSystemSummaryDTO: Decodable {
    let energyTodayWh: Double
    let currentPowerW: Double?

    enum CodingKeys: String, CodingKey {
        case energyTodayWh = "energy_today"
        case currentPowerW = "current_power"
    }
}

/// Response shape shared by `telemetry/consumption_meter` and `telemetry/production_meter`.
struct EnphaseMeterTelemetryResponse: Decodable {
    let intervals: [Interval]

    struct Interval: Decodable {
        let endAt: Int
        let enwh: Double

        enum CodingKeys: String, CodingKey {
            case endAt = "end_at"
            case enwh
        }
    }

    var totalWh: Double {
        intervals.reduce(0) { $0 + $1.enwh }
    }
}

/// Response shape for `energy_import_telemetry` / `energy_export_telemetry`. Both endpoints
/// nest their intervals as a list of lists (`intervals[][]`, see ENPHASE_API_WERTE.md) and only
/// populate one of `whImported`/`whExported` depending on which endpoint was called.
struct EnphaseEnergyFlowTelemetryResponse: Decodable {
    let intervals: [[Entry]]

    struct Entry: Decodable {
        let endAt: Int
        let whImported: Double?
        let whExported: Double?

        enum CodingKeys: String, CodingKey {
            case endAt = "end_at"
            case whImported = "wh_imported"
            case whExported = "wh_exported"
        }
    }

    var totalWh: Double {
        intervals.flatMap { $0 }.reduce(0) { $0 + ($1.whImported ?? $1.whExported ?? 0) }
    }
}

struct EnphaseBatteryTelemetryResponse: Decodable {
    let intervals: [Interval]

    struct Interval: Decodable {
        let endAt: Int
        let charge: EnergyValue
        let discharge: EnergyValue
        let soc: StateOfCharge

        enum CodingKeys: String, CodingKey {
            case endAt = "end_at"
            case charge, discharge, soc
        }
    }

    struct EnergyValue: Decodable {
        let enwh: Double
    }

    struct StateOfCharge: Decodable {
        let percent: Double
    }

    var totalChargedWh: Double {
        intervals.reduce(0) { $0 + $1.charge.enwh }
    }

    var totalDischargedWh: Double {
        intervals.reduce(0) { $0 + $1.discharge.enwh }
    }

    /// Percent of charge as of the most recent interval, `nil` if no interval was reported yet.
    var latestSocPercent: Double? {
        intervals.last?.soc.percent
    }
}

// MARK: - Lifetime (daily) series, used for backfill (F3.2) and daily finalize (F3.3)

/// A day-indexed value from a `_lifetime` series, resolved to a concrete calendar day.
///
/// Trailing zeros mean "not yet reported", not "0 Wh" (see ENPHASE_API_WERTE.md) — callers
/// decide how to treat them; this type only pairs values with their day.
struct EnphaseLifetimeDailyValue {
    let date: Date
    let value: Double
}

private func dailyValues(startDateString: String, values: [Double]) -> [EnphaseLifetimeDailyValue] {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.dateFormat = "yyyy-MM-dd"
    formatter.timeZone = TimeZone.current
    guard let startDate = formatter.date(from: startDateString) else { return [] }

    let calendar = Calendar.current
    return values.enumerated().compactMap { offset, value in
        calendar.date(byAdding: .day, value: offset, to: startDate).map {
            EnphaseLifetimeDailyValue(date: calendar.startOfDay(for: $0), value: value)
        }
    }
}

struct EnphaseEnergyLifetimeResponse: Decodable {
    let startDate: String
    let production: [Double]

    enum CodingKeys: String, CodingKey {
        case startDate = "start_date"
        case production
    }

    var dailyValues: [EnphaseLifetimeDailyValue] {
        Energie.dailyValues(startDateString: startDate, values: production)
    }
}

struct EnphaseConsumptionLifetimeResponse: Decodable {
    let startDate: String
    let consumption: [Double]

    enum CodingKeys: String, CodingKey {
        case startDate = "start_date"
        case consumption
    }

    var dailyValues: [EnphaseLifetimeDailyValue] {
        Energie.dailyValues(startDateString: startDate, values: consumption)
    }
}

struct EnphaseImportLifetimeResponse: Decodable {
    let startDate: String
    let imported: [Double]

    enum CodingKeys: String, CodingKey {
        case startDate = "start_date"
        case imported = "import"
    }

    var dailyValues: [EnphaseLifetimeDailyValue] {
        Energie.dailyValues(startDateString: startDate, values: imported)
    }
}

struct EnphaseExportLifetimeResponse: Decodable {
    let startDate: String
    let exported: [Double]

    enum CodingKeys: String, CodingKey {
        case startDate = "start_date"
        case exported = "export"
    }

    var dailyValues: [EnphaseLifetimeDailyValue] {
        Energie.dailyValues(startDateString: startDate, values: exported)
    }
}

struct EnphaseBatteryLifetimeResponse: Decodable {
    let startDate: String
    let charge: [Double]
    let discharge: [Double]

    enum CodingKeys: String, CodingKey {
        case startDate = "start_date"
        case charge, discharge
    }

    var dailyChargedValues: [EnphaseLifetimeDailyValue] {
        Energie.dailyValues(startDateString: startDate, values: charge)
    }

    var dailyDischargedValues: [EnphaseLifetimeDailyValue] {
        Energie.dailyValues(startDateString: startDate, values: discharge)
    }
}
