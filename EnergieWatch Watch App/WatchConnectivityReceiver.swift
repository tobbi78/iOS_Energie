//
//  WatchConnectivityReceiver.swift
//  EnergieWatch Watch App
//
//  Created by Tobias Florian on 04.10.26.
//
//  The Watch-side counterpart to the iPhone's WatchSyncService. Never calls Enphase/Viessmann
//  itself (see BACKLOG.md, "Zielplattform Apple Watch" — companion model) — it only receives
//  whatever the iPhone last sent via `updateApplicationContext`, caches it in the Watch-local App
//  Group (`WatchSnapshotStore`) so the Complication widget extension can read it too, and asks
//  WidgetKit to refresh the complications.

import Foundation
import WatchConnectivity
import WidgetKit

@Observable
@MainActor
final class WatchConnectivityReceiver: NSObject {
    private(set) var snapshot: WatchSnapshot
    private var session: WCSession?

    override init() {
        snapshot = WatchSnapshotStore.load()
        super.init()
        guard WCSession.isSupported() else { return }
        session = WCSession.default
        session?.delegate = self
        session?.activate()
    }

    private func handle(_ snapshot: WatchSnapshot) {
        self.snapshot = snapshot
        WatchSnapshotStore.save(snapshot)
        WidgetCenter.shared.reloadAllTimelines()
    }
}

extension WatchConnectivityReceiver: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let data = applicationContext["snapshot"] as? Data,
              let decoded = try? JSONDecoder().decode(WatchSnapshot.self, from: data) else { return }
        Task { @MainActor [weak self] in
            self?.handle(decoded)
        }
    }
}
