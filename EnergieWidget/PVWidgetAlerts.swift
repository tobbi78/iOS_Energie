//
//  PVWidgetAlerts.swift
//  EnergieWidget
//
//  Created by Tobias Florian on 01.10.26.
//
//  Local notifications (F5.5): Anlagenausfall, erschöpftes Monatsbudget, niedriger
//  Speicherstand. Lives in the widget because it's the process that actually polls
//  regularly in the background — a notification is only useful for exactly the moments the
//  app isn't open. Each condition notifies at most once per "episode" (persisted in the
//  shared App-Group UserDefaults) so a sustained outage/low battery doesn't spam a
//  notification on every single timeline refresh.
//
//  Extensions share their containing app's notification permission (there's no separate
//  Settings entry for the widget) — the app requests authorization once in
//  `SolarModel.start()`; scheduling here just uses whatever was already granted.
//

import Foundation
import UserNotifications

enum PVWidgetAlerts {
    static let consecutiveFailureThreshold = 3
    static let lowBatteryThresholdPercent = 10.0

    private static let defaults = PVWidgetDataSource.sharedDefaults
    private static let consecutiveFailuresKey = "PVWidgetAlerts.consecutiveFailures"
    private static let budgetExhaustedNotifiedKey = "PVWidgetAlerts.budgetExhaustedNotified"
    private static let lowBatteryNotifiedKey = "PVWidgetAlerts.lowBatteryNotified"

    /// Call after a successful fetch — clears the outage/budget flags (a successful poll means
    /// neither condition currently holds) and checks the battery level.
    static func handleSuccess(snapshot: PVWidgetDataSource.Snapshot) {
        defaults.set(0, forKey: consecutiveFailuresKey)
        defaults.set(false, forKey: budgetExhaustedNotifiedKey)

        guard let percent = snapshot.batterySocPercent else { return }
        let isLowNow = percent < lowBatteryThresholdPercent
        let wasLowBefore = defaults.bool(forKey: lowBatteryNotifiedKey)
        if isLowNow, !wasLowBefore {
            notify(
                identifier: "pv.lowBattery",
                title: "Speicher fast leer",
                body: "Ladezustand der PV-Anlage nur noch \(Int(percent))%."
            )
        }
        defaults.set(isLowNow, forKey: lowBatteryNotifiedKey)
    }

    /// Call after a failed fetch. `.notSignedIn`/`.tokenExpired` are expected states that need
    /// the user to open the app anyway (already visible there) — not an "Anlagenausfall", so no
    /// alert for those here.
    static func handleFailure(_ error: PVWidgetDataSource.FetchError) {
        switch error {
        case .monthlyBudgetExhausted:
            guard !defaults.bool(forKey: budgetExhaustedNotifiedKey) else { return }
            notify(
                identifier: "pv.budgetExhausted",
                title: "Enphase-Monatslimit erreicht",
                body: "Das monatliche Abfrage-Kontingent ist aufgebraucht. Neue Werte gibt es erst wieder im nächsten Monat."
            )
            defaults.set(true, forKey: budgetExhaustedNotifiedKey)

        case .invalidResponse, .http:
            let count = defaults.integer(forKey: consecutiveFailuresKey) + 1
            defaults.set(count, forKey: consecutiveFailuresKey)
            if count == consecutiveFailureThreshold {
                notify(
                    identifier: "pv.pollFailures",
                    title: "PV-Anlage nicht erreichbar",
                    body: "Mehrere Abrufe der Enphase-Daten sind in Folge fehlgeschlagen."
                )
            }

        case .notSignedIn, .tokenExpired:
            break
        }
    }

    private static func notify(identifier: String, title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
