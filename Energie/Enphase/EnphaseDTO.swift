//
//  EnphaseDTO.swift
//  Energie
//
//  Created by Tobias Florian on 30.09.26.
//

import Foundation

/// Decoding types for the Enphase Monitoring API v4 responses used by `EnphaseClient`.
/// Field meanings/units: see ENPHASE_API_WERTE.md.

struct EnphaseSystemsResponse: Decodable {
    let systems: [EnphaseSystemDTO]
}

struct EnphaseSystemDTO: Decodable {
    let systemID: Int

    enum CodingKeys: String, CodingKey {
        case systemID = "system_id"
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
