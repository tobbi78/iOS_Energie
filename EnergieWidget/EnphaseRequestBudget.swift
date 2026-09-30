//
//  EnphaseRequestBudget.swift
//  EnergieWidget
//
//  Created by Tobias Florian on 01.10.26.
//
//  Intentional duplicate of Energie/Enphase/EnphaseRequestBudget.swift. The widget extension is
//  a separate compilation target/module; sharing one source file's compilation across both
//  targets would need a shared framework target, which isn't achievable with the available
//  project-editing tools without a larger, riskier restructuring. Keep this file's logic byte-
//  identical to the app's copy when changing either — both read/write the same shared
//  UserDefaults suite (`SharedAppGroup`/`PVWidgetDataSource.sharedDefaults`) and must agree on
//  the UserDefaults keys to correctly share one Enphase monthly budget (BACKLOG.md F5.6).
//

import Foundation

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

    func usedThisMonth() -> Int {
        let currentMonth = monthIdentifier(for: now())
        guard userDefaults.string(forKey: Self.monthKey) == currentMonth else { return 0 }
        return userDefaults.integer(forKey: Self.countKey)
    }

    func recordRequest() {
        let currentMonth = monthIdentifier(for: now())
        if userDefaults.string(forKey: Self.monthKey) != currentMonth {
            userDefaults.set(currentMonth, forKey: Self.monthKey)
            userDefaults.set(0, forKey: Self.countKey)
        }
        userDefaults.set(userDefaults.integer(forKey: Self.countKey) + 1, forKey: Self.countKey)
    }

    func isExhausted(reserve: Int = 20) -> Bool {
        usedThisMonth() >= Self.monthlyLimit - reserve
    }

    private func monthIdentifier(for date: Date) -> String {
        let components = Calendar.current.dateComponents([.year, .month], from: date)
        return "\(components.year ?? 0)-\(components.month ?? 0)"
    }
}
