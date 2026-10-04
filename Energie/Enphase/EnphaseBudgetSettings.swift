//
//  EnphaseBudgetSettings.swift
//  Energie
//
//  Created by Tobias Florian on 04.10.26.
//

import Foundation

/// User-configurable reserve held back from the monthly Enphase request budget (F6.3) — was a
/// fixed `reserve: Int = 20` constant in `EnphaseRequestBudget.isExhausted(reserve:)`/
/// `PVWidgetPollPacing.monthlyReserve`. The reserve exists so the daily finalize pass
/// (`SolarModel.runDailyFinalizeIfNeeded`) always has a few requests left near the end of the
/// month, even if live polling would otherwise use up the entire budget.
///
/// Backed by the shared App Group `UserDefaults` (not plain `.standard`, unlike
/// `PVDisplayPreferences`) because the widget extension's `PVWidgetPollPacing` needs to read the
/// same configured value — the widget doesn't link this class (same tooling limitation as
/// `EnphaseRequestBudget`/`EnphaseRequestThrottle`), so it reads `reserveKey` directly via
/// `SharedAppGroup.userDefaults`; keep the key string in sync by hand if it ever changes.
@Observable
@MainActor
final class EnphaseBudgetSettings {
    static let reserveKey = "EnphaseBudgetSettings.monthlyReserve"
    static let defaultReserve = 20
    static let minimumReserve = 0
    static let maximumReserve = 100

    private let userDefaults: UserDefaults
    private(set) var monthlyReserve: Int

    init(userDefaults: UserDefaults = SharedAppGroup.userDefaults) {
        self.userDefaults = userDefaults
        let stored = userDefaults.object(forKey: Self.reserveKey) as? Int
        monthlyReserve = stored ?? Self.defaultReserve
    }

    func setMonthlyReserve(_ value: Int) {
        let clamped = min(max(value, Self.minimumReserve), Self.maximumReserve)
        monthlyReserve = clamped
        userDefaults.set(clamped, forKey: Self.reserveKey)
    }
}
