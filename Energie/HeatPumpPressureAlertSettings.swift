//
//  HeatPumpPressureAlertSettings.swift
//  Energie
//
//  Created by Tobias Florian on 04.10.26.
//

import Foundation

/// User-configurable settings for the low-pressure local notification. Backed by `UserDefaults`
/// with an injectable store, same pattern as `PVDisplayPreferences` — so tests never touch the
/// real app defaults, and explicit setter methods rather than property observers (which don't
/// reliably fire during `init`).
///
/// Simpler than the macOS sibling project's `PressureAlertSettings`: no `recipient` field, since
/// this sends a local notification to the device itself rather than an iMessage to someone.
///
/// Backed by the shared App Group `UserDefaults` (not plain `.standard`) because the heat-pump
/// widget extension's own pressure-alert check needs to read the same configured threshold/
/// enabled-state — the widget doesn't link this class (same tooling limitation as
/// `EnphaseBudgetSettings`), so it reads the keys below directly via `SharedAppGroup.userDefaults`;
/// keep them in sync by hand if they ever change.
@Observable
@MainActor
final class HeatPumpPressureAlertSettings {
    static let thresholdKey = "HeatPumpPressureAlertSettings.threshold"
    static let isEnabledKey = "HeatPumpPressureAlertSettings.isEnabled"
    static let recoveryMessageEnabledKey = "HeatPumpPressureAlertSettings.recoveryMessageEnabled"
    static let repeatIntervalKey = "HeatPumpPressureAlertSettings.repeatInterval"

    /// Suggested by the reference values in `heating.configuration.pressure.total`
    /// (`defaultPressure` 1.5 bar − `normalPressureDelta` 0.6 bar ≈ 0.9 bar, see
    /// VIESSMANN_API_WERTE.md) — same default the macOS sibling project settled on.
    static let defaultThreshold: Double = 1.0
    static let defaultRepeatInterval: TimeInterval = 4 * 3600

    private let defaults: UserDefaults

    private(set) var threshold: Double
    private(set) var isEnabled: Bool
    private(set) var recoveryMessageEnabled: Bool
    private(set) var repeatInterval: TimeInterval

    init(defaults: UserDefaults = SharedAppGroup.userDefaults) {
        self.defaults = defaults
        threshold = defaults.object(forKey: Self.thresholdKey) as? Double ?? Self.defaultThreshold
        isEnabled = defaults.object(forKey: Self.isEnabledKey) as? Bool ?? true
        recoveryMessageEnabled = defaults.object(forKey: Self.recoveryMessageEnabledKey) as? Bool ?? true
        repeatInterval = defaults.object(forKey: Self.repeatIntervalKey) as? TimeInterval ?? Self.defaultRepeatInterval
    }

    func setThreshold(_ newValue: Double) {
        threshold = newValue
        defaults.set(newValue, forKey: Self.thresholdKey)
    }

    func setEnabled(_ newValue: Bool) {
        isEnabled = newValue
        defaults.set(newValue, forKey: Self.isEnabledKey)
    }

    func setRecoveryMessageEnabled(_ newValue: Bool) {
        recoveryMessageEnabled = newValue
        defaults.set(newValue, forKey: Self.recoveryMessageEnabledKey)
    }

    func setRepeatInterval(_ newValue: TimeInterval) {
        repeatInterval = newValue
        defaults.set(newValue, forKey: Self.repeatIntervalKey)
    }
}
