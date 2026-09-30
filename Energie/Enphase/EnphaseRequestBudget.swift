//
//  EnphaseRequestBudget.swift
//  Energie
//
//  Created by Tobias Florian on 30.09.26.
//

import Foundation

/// Persistent per-calendar-month request counter (F4.2).
///
/// Enphase's actual monthly quota isn't officially documented — 1000/month is a user-supplied
/// assumption (see ENPHASE_API_WERTE.md/BACKLOG.md), enforced here so the app has a defined,
/// predictable behavior instead of silently exceeding it and finding out via 429s alone.
///
/// An actor, like `EnphaseRequestThrottle`, since `EnphaseClient` can issue several requests
/// concurrently (`async let` in `SolarModel`) and a plain read-increment-write on `UserDefaults`
/// would otherwise be racy.
actor EnphaseRequestBudget {
    static let monthlyLimit = 1000

    private let userDefaults: UserDefaults
    private let now: @Sendable () -> Date
    private static let monthKey = "EnphaseRequestBudget.month"
    private static let countKey = "EnphaseRequestBudget.count"

    init(userDefaults: UserDefaults = .standard, now: @escaping @Sendable () -> Date = { Date() }) {
        self.userDefaults = userDefaults
        self.now = now
    }

    /// Requests already recorded in the current calendar month.
    func usedThisMonth() -> Int {
        let currentMonth = monthIdentifier(for: now())
        guard userDefaults.string(forKey: Self.monthKey) == currentMonth else { return 0 }
        return userDefaults.integer(forKey: Self.countKey)
    }

    /// Call once for every request that actually goes out over the network.
    func recordRequest() {
        let currentMonth = monthIdentifier(for: now())
        if userDefaults.string(forKey: Self.monthKey) != currentMonth {
            userDefaults.set(currentMonth, forKey: Self.monthKey)
            userDefaults.set(0, forKey: Self.countKey)
        }
        userDefaults.set(userDefaults.integer(forKey: Self.countKey) + 1, forKey: Self.countKey)
    }

    /// True once the remaining budget for this month (minus `reserve`, kept for the daily
    /// finalize pass) is used up.
    func isExhausted(reserve: Int = 20) -> Bool {
        usedThisMonth() >= Self.monthlyLimit - reserve
    }

    private func monthIdentifier(for date: Date) -> String {
        let components = Calendar.current.dateComponents([.year, .month], from: date)
        return "\(components.year ?? 0)-\(components.month ?? 0)"
    }
}
