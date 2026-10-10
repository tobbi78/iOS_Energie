//
//  NotificationEcho.swift
//  Energie
//
//  Created by Tobias Florian on 11.10.26.
//
//  Makes the existing local notifications (F5.5 — Anlagenausfall/Budget/Speicherstand bei PV,
//  Druckalarm bei der Wärmepumpe) visible *inside* the app (F10.8). The notifications
//  themselves are scheduled by `PVWidgetAlerts`/`HPWidgetAlerts` (EnergieWidget, since that's
//  the process that actually polls in the background) or by `HeatPumpModel` itself — this type
//  doesn't schedule anything, it just looks at what the system has already delivered. Their
//  identifiers are stable prefixes (`pv.*`/`heatPump.*`), which is all that's needed here; the
//  widget's duplicated constants (see `SharedAppGroup`) don't need to be touched.
//

import Foundation
import UserNotifications

@MainActor
@Observable
final class NotificationEcho {
    /// Bumped once per newly-observed PV notification — `ContentView` uses this as the
    /// `symbolEffect(.bounce, value:)` trigger on the PV tab icon.
    private(set) var pvTrigger = 0
    /// Same as `pvTrigger`, for the heat pump's pressure alert.
    private(set) var heatPumpTrigger = 0

    private let center: UNUserNotificationCenter
    private let defaults: UserDefaults

    private static let pvLastSeenKey = "NotificationEcho.pvLastSeen"
    private static let heatPumpLastSeenKey = "NotificationEcho.heatPumpLastSeen"

    init(center: UNUserNotificationCenter = .current(), defaults: UserDefaults = .standard) {
        self.center = center
        self.defaults = defaults
    }

    /// Call when the app becomes active — after the `LaunchView` overlay (F10.1) is gone, so the
    /// bounce isn't wasted behind it (same reasoning as the staggered KPI cards, F10.3).
    func refresh() async {
        let delivered = await center.deliveredNotifications()
        let pvDates = delivered.filter { $0.request.identifier.hasPrefix("pv.") }.map(\.date)
        let heatPumpDates = delivered.filter { $0.request.identifier.hasPrefix("heatPump.") }.map(\.date)

        apply(Self.evaluate(deliveredDates: pvDates, lastSeenDate: defaults.object(forKey: Self.pvLastSeenKey) as? Date),
              trigger: &pvTrigger, lastSeenKey: Self.pvLastSeenKey)
        apply(Self.evaluate(deliveredDates: heatPumpDates, lastSeenDate: defaults.object(forKey: Self.heatPumpLastSeenKey) as? Date),
              trigger: &heatPumpTrigger, lastSeenKey: Self.heatPumpLastSeenKey)
    }

    private func apply(_ result: (isNew: Bool, newestDate: Date?), trigger: inout Int, lastSeenKey: String) {
        if result.isNew { trigger += 1 }
        if let newest = result.newestDate { defaults.set(newest, forKey: lastSeenKey) }
    }

    /// Pure comparison extracted for testability (`NotificationEchoTests`): given the delivery
    /// dates of a category's currently-delivered notifications and the timestamp last checked,
    /// decides whether a *new* one (newer than last seen) has arrived since. Returns the newest
    /// date found so the caller can persist it, even when nothing new triggered this time.
    static func evaluate(deliveredDates: [Date], lastSeenDate: Date?) -> (isNew: Bool, newestDate: Date?) {
        guard let newest = deliveredDates.max() else { return (false, lastSeenDate) }
        let isNew = lastSeenDate.map { newest > $0 } ?? true
        return (isNew, newest)
    }
}
