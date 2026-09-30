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

    private(set) var seriesSelection: PVSeriesSelection

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        if let raw = userDefaults.string(forKey: Self.seriesSelectionKey),
           let selection = PVSeriesSelection(rawValue: raw) {
            seriesSelection = selection
        } else {
            seriesSelection = .all
        }
    }

    func setSeriesSelection(_ selection: PVSeriesSelection) {
        seriesSelection = selection
        userDefaults.set(selection.rawValue, forKey: Self.seriesSelectionKey)
    }
}
