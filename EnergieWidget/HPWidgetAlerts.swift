//
//  HPWidgetAlerts.swift
//  EnergieWidget
//
//  Created by Tobias Florian on 04.10.26.
//
//  Background equivalent of HeatPumpModel's checkPressureAlert/notifyPressureAlert — this is the
//  actual point of the whole widget (see HPWidgetDataSource's doc comment): the foreground-only
//  poll loop in the app can't catch a pressure drop while the app is closed. Reads the user's
//  configured threshold/settings directly from the shared App Group UserDefaults (same tooling
//  limitation as EnphaseBudgetSettings/PVWidgetDataSource.configuredReserve — can't link
//  HeatPumpPressureAlertSettings, so the raw key strings are duplicated here; keep in sync by
//  hand). The tracker state (crossed-below-threshold + last-notified) is persisted across widget
//  runs the same way, since each timeline refresh is a fresh process.
//

import Foundation
import UserNotifications

enum HPWidgetAlerts {
    private static let defaults = HPWidgetDataSource.sharedDefaults
    private static let trackerStateKey = "HPWidgetAlerts.trackerState"

    private static var isEnabled: Bool {
        defaults.object(forKey: "HeatPumpPressureAlertSettings.isEnabled") as? Bool ?? true
    }
    private static var threshold: Double {
        defaults.object(forKey: "HeatPumpPressureAlertSettings.threshold") as? Double ?? 1.0
    }
    private static var recoveryMessageEnabled: Bool {
        defaults.object(forKey: "HeatPumpPressureAlertSettings.recoveryMessageEnabled") as? Bool ?? true
    }
    private static var repeatInterval: TimeInterval {
        defaults.object(forKey: "HeatPumpPressureAlertSettings.repeatInterval") as? TimeInterval ?? (4 * 3600)
    }

    static func check(pressureBar: Double?) {
        guard isEnabled else { return }

        let (alert, newState) = HeatPumpPressureAlertTracker.evaluate(
            currentPressure: pressureBar,
            threshold: threshold,
            now: Date(),
            state: loadTrackerState(),
            recoveryEnabled: recoveryMessageEnabled,
            repeatInterval: repeatInterval
        )
        saveTrackerState(newState)

        guard let alert, let pressureBar else { return }
        notify(alert, pressure: pressureBar)
    }

    private struct CodableState: Codable {
        let isBelowThreshold: Bool
        let lastNotifiedAt: Date?
    }

    private static func loadTrackerState() -> HeatPumpPressureAlertTracker.State {
        guard let data = defaults.data(forKey: trackerStateKey),
              let decoded = try? JSONDecoder().decode(CodableState.self, from: data) else {
            return HeatPumpPressureAlertTracker.State()
        }
        return HeatPumpPressureAlertTracker.State(isBelowThreshold: decoded.isBelowThreshold, lastNotifiedAt: decoded.lastNotifiedAt)
    }

    private static func saveTrackerState(_ state: HeatPumpPressureAlertTracker.State) {
        let encoded = CodableState(isBelowThreshold: state.isBelowThreshold, lastNotifiedAt: state.lastNotifiedAt)
        if let data = try? JSONEncoder().encode(encoded) {
            defaults.set(data, forKey: trackerStateKey)
        }
    }

    private static func notify(_ alert: HeatPumpPressureAlertKind, pressure: Double) {
        let pressureText = pressure.formatted(.number.precision(.fractionLength(1...2)))
        let content = UNMutableNotificationContent()
        content.sound = .default
        switch alert {
        case .drop, .repeatReminder:
            let thresholdText = threshold.formatted(.number.precision(.fractionLength(1...2)))
            content.title = "Wärmepumpe: Anlagendruck zu niedrig"
            content.body = "\(pressureText) bar, Schwellwert \(thresholdText) bar."
        case .recovery:
            content.title = "Wärmepumpe: Anlagendruck wieder normal"
            content.body = "\(pressureText) bar."
        }
        let request = UNNotificationRequest(identifier: "heatPump.pressureAlert", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
