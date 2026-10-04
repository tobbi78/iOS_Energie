//
//  WatchSyncService.swift
//  Energie
//
//  Created by Tobias Florian on 04.10.26.
//
//  Hands the latest PV/heat-pump values off to a paired Apple Watch (see BACKLOG.md,
//  "Zielplattform Apple Watch"). This is the iPhone side of the companion model decided there:
//  the Watch app and its Complication widget never call Enphase/Viessmann themselves — they only
//  ever display what this service last sent them. That sidesteps two problems a second,
//  independently polling device would create: rotating the Viessmann refresh token out from
//  under the iPhone, and burning extra Enphase monthly-budget requests for no benefit.
//
//  `SolarModel` and `HeatPumpModel` each report their own side independently (same "a failure on
//  one side must never affect the other" principle as the rest of the app) via `updatePV`/
//  `updateHeatPump` — this service merges both into one `WatchSnapshot` and only actually talks
//  to WatchConnectivity when the merged result changed, so a model that keeps refreshing with
//  identical values doesn't spam the link.
//
//  Uses `updateApplicationContext`, not a message send: that's the right primitive for "the
//  watch only needs the latest state" (WatchConnectivity coalesces repeated contexts for us) and
//  it delivers even when the watch app isn't currently in the foreground, unlike
//  `sendMessage`.

import Foundation
import WatchConnectivity

/// Just the slice of `WCSession` this service needs, so tests can inject a fake instead of the
/// real (unsubclassable) `WCSession` — same DI pattern already used throughout the app (e.g.
/// `EnphaseClient`'s injected `URLSession`).
protocol WatchConnectivitySession: AnyObject {
    var activationState: WCSessionActivationState { get }
    var isPaired: Bool { get }
    var isWatchAppInstalled: Bool { get }
    var delegate: WCSessionDelegate? { get set }
    func activate()
    func updateApplicationContext(_ applicationContext: [String: Any]) throws
}

extension WCSession: WatchConnectivitySession {}

@MainActor
final class WatchSyncService: NSObject {
    struct PVUpdate: Equatable {
        var producedTodayWh: Double
        var selfSufficiencyRate: Double?
        var batterySocPercent: Double?
        var fetchedAt: Date
    }

    struct HeatPumpUpdate: Equatable {
        var pressureBar: Double?
        var outsideTemperatureCelsius: Double?
        var pressureAlertActive: Bool
        var fetchedAt: Date
    }

    private let session: WatchConnectivitySession?
    private var latestPV: PVUpdate?
    private var latestHeatPump: HeatPumpUpdate?
    private(set) var lastSentSnapshot: WatchSnapshot?

    init(session: WatchConnectivitySession? = WCSession.isSupported() ? WCSession.default : nil) {
        self.session = session
        super.init()
        session?.delegate = self
        session?.activate()
    }

    /// Call after every successful PV refresh (`SolarModel.refresh()`).
    func updatePV(_ update: PVUpdate) {
        guard latestPV != update else { return }
        latestPV = update
        sendMergedSnapshotIfNeeded()
    }

    /// Call after every successful heat-pump refresh (`HeatPumpModel.refresh()`).
    func updateHeatPump(_ update: HeatPumpUpdate) {
        guard latestHeatPump != update else { return }
        latestHeatPump = update
        sendMergedSnapshotIfNeeded()
    }

    private func sendMergedSnapshotIfNeeded() {
        let snapshot = WatchSnapshot(
            pvProducedTodayWh: latestPV?.producedTodayWh,
            pvSelfSufficiencyRate: latestPV?.selfSufficiencyRate,
            pvBatterySocPercent: latestPV?.batterySocPercent,
            pvFetchedAt: latestPV?.fetchedAt,
            heatPumpPressureBar: latestHeatPump?.pressureBar,
            heatPumpOutsideTemperatureCelsius: latestHeatPump?.outsideTemperatureCelsius,
            heatPumpPressureAlertActive: latestHeatPump?.pressureAlertActive ?? false,
            heatPumpFetchedAt: latestHeatPump?.fetchedAt
        )
        guard snapshot != lastSentSnapshot else { return }
        guard let session, session.activationState == .activated, session.isPaired, session.isWatchAppInstalled else { return }

        do {
            let data = try JSONEncoder().encode(snapshot)
            try session.updateApplicationContext(["snapshot": data])
            lastSentSnapshot = snapshot
        } catch {
            // Best-effort hand-off — a failed transfer to the Watch must never affect the iPhone
            // app itself. `lastSentSnapshot` deliberately stays unchanged so the next successful
            // refresh retries the send.
        }
    }
}

extension WatchSyncService: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
}
