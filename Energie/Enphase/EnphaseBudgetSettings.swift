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
/// F6.4 adds the monthly limit itself as a second configurable value, since different Enphase
/// plans grant different quotas instead of the one originally confirmed 1000/month — the plan a
/// given install is actually booked on isn't knowable from the API, so it's a setting instead of
/// a constant.
///
/// Backed by the shared App Group `UserDefaults` (not plain `.standard`, unlike
/// `PVDisplayPreferences`) because the widget extension's `PVWidgetPollPacing` needs to read the
/// same configured values — the widget doesn't link this class (same tooling limitation as
/// `EnphaseRequestBudget`/`EnphaseRequestThrottle`), so it reads `reserveKey`/`monthlyLimitKey`
/// directly via `SharedAppGroup.userDefaults`; keep the key strings in sync by hand if they ever
/// change.
@Observable
@MainActor
final class EnphaseBudgetSettings {
    static let reserveKey = "EnphaseBudgetSettings.monthlyReserve"
    static let defaultReserve = 20
    static let minimumReserve = 0
    static let maximumReserve = 100

    static let monthlyLimitKey = "EnphaseBudgetSettings.monthlyLimit"
    static let defaultMonthlyLimit = 1000
    static let minimumMonthlyLimit = 100
    static let maximumMonthlyLimit = 1000

    private let userDefaults: UserDefaults
    private(set) var monthlyReserve: Int
    private(set) var monthlyLimit: Int

    /// Reserve can never exceed half of the currently configured monthly limit — otherwise a low
    /// limit combined with a high reserve (both independently valid ranges) could leave nothing
    /// for live polling at all.
    var maximumReserve: Int {
        min(Self.maximumReserve, monthlyLimit / 2)
    }

    init(userDefaults: UserDefaults = SharedAppGroup.userDefaults) {
        self.userDefaults = userDefaults
        let storedLimit = userDefaults.object(forKey: Self.monthlyLimitKey) as? Int
        let limit = min(max(storedLimit ?? Self.defaultMonthlyLimit, Self.minimumMonthlyLimit), Self.maximumMonthlyLimit)
        let storedReserve = userDefaults.object(forKey: Self.reserveKey) as? Int
        let reserve = min(max(storedReserve ?? Self.defaultReserve, Self.minimumReserve), limit / 2)
        monthlyLimit = limit
        monthlyReserve = reserve
    }

    func setMonthlyReserve(_ value: Int) {
        let clamped = min(max(value, Self.minimumReserve), maximumReserve)
        monthlyReserve = clamped
        userDefaults.set(clamped, forKey: Self.reserveKey)
    }

    /// Lowering the limit can push the already-configured reserve above the new `maximumReserve`
    /// — in that case the reserve is silently reduced to fit, rather than left in an inconsistent
    /// state where it reads back larger than half the limit.
    func setMonthlyLimit(_ value: Int) {
        let clamped = min(max(value, Self.minimumMonthlyLimit), Self.maximumMonthlyLimit)
        monthlyLimit = clamped
        userDefaults.set(clamped, forKey: Self.monthlyLimitKey)
        if monthlyReserve > maximumReserve {
            setMonthlyReserve(monthlyReserve)
        }
    }
}
