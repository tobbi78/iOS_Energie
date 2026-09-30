//
//  PVDisplayPreferences.swift
//  Energie
//
//  Created by Tobias Florian on 30.09.26.
//

import Foundation

/// Which series the history charts show (F3.5) — one shared selection for all of them.
enum PVSeriesSelection: String, CaseIterable, Identifiable {
    case all
    case production
    case consumption
    case feedIn

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: return "Alle"
        case .production: return "Produktion"
        case .consumption: return "Verbrauch"
        case .feedIn: return "Einspeisung"
        }
    }
}

/// Display-only preferences — not secrets, so plain (injectable) `UserDefaults` rather than the
/// Keychain-backed `EnphaseSettings`.
@Observable
@MainActor
final class PVDisplayPreferences {
    private let userDefaults: UserDefaults
    private static let seriesSelectionKey = "PVDisplayPreferences.seriesSelection"
    private static let feedInTariffKey = "PVDisplayPreferences.feedInTariffPerKWh"

    /// Default matches the rough estimate for small German residential systems from
    /// ENPHASE_INTEGRATION_SPEC.md — a placeholder until the user enters their real rate (F6.2).
    static let defaultFeedInTariffPerKWh = 0.08

    private(set) var seriesSelection: PVSeriesSelection
    private(set) var feedInTariffPerKWh: Double

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        if let raw = userDefaults.string(forKey: Self.seriesSelectionKey),
           let selection = PVSeriesSelection(rawValue: raw) {
            seriesSelection = selection
        } else {
            seriesSelection = .all
        }

        let storedTariff = userDefaults.double(forKey: Self.feedInTariffKey)
        feedInTariffPerKWh = storedTariff > 0 ? storedTariff : Self.defaultFeedInTariffPerKWh
    }

    func setSeriesSelection(_ selection: PVSeriesSelection) {
        seriesSelection = selection
        userDefaults.set(selection.rawValue, forKey: Self.seriesSelectionKey)
    }

    func setFeedInTariffPerKWh(_ tariff: Double) {
        guard tariff > 0 else { return }
        feedInTariffPerKWh = tariff
        userDefaults.set(tariff, forKey: Self.feedInTariffKey)
    }
}
