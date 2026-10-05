//
//  NotificationAuthorization.swift
//  Energie
//
//  Created by Tobias Florian on 05.10.26.
//

import UserNotifications

/// Requests local-notification authorization once, the first time it's needed. A no-op once the
/// user has already answered the system prompt (`.notDetermined` is the only state that triggers
/// it) — extensions share their containing app's notification permission (no separate Settings
/// entry of their own), so this request, made here where there's a foreground app to show the
/// system prompt, covers both the PV (F5.5) and heat-pump alert paths. Shared by
/// `SolarModel.start()` and `HeatPumpModel.start()`, which previously each carried their own
/// byte-identical copy of this method.
enum NotificationAuthorization {
    static func requestIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .notDetermined else { return }
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
    }
}
