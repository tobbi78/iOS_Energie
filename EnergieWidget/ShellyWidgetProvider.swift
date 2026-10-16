//
//  ShellyWidgetProvider.swift
//  EnergieWidget
//
//  Created by Tobias Florian on 16.10.26.
//

import WidgetKit

struct ShellyWidgetProvider: TimelineProvider {
    /// No known rate limit beyond the account-wide 1-request/second throttle (F15.1/F15.3,
    /// Nutzerentscheidung 2026-10-15) — 15 minutes keeps the widget reasonably current without
    /// polling so often it would outpace what a Homescreen widget's own refresh budget allows.
    /// Unlike PV/Wärmepumpe, there's no alarm tied to this widget (F16.4 — schalten stays
    /// app-only, and there's no equivalent of a pressure/Anlagenausfall alert for a plug), so
    /// this cadence is the only thing driving the refresh.
    static let pollInterval: TimeInterval = 900

    func placeholder(in context: Context) -> ShellyWidgetEntry {
        ShellyWidgetEntry(
            date: .now,
            snapshot: ShellyWidgetSnapshot(
                totalPower: 142,
                onCount: 2,
                deviceCount: 3,
                offlineCount: 0,
                plugs: [
                    ShellyWidgetSnapshot.Plug(id: "a", name: "Wohnzimmer", isOnline: true, output: true, formattedPower: "98 W"),
                    ShellyWidgetSnapshot.Plug(id: "b", name: "Büro", isOnline: true, output: true, formattedPower: "44 W"),
                    ShellyWidgetSnapshot.Plug(id: "c", name: "Garage", isOnline: true, output: false, formattedPower: "0 W"),
                ],
                fetchedAt: .now
            ),
            state: .ready
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (ShellyWidgetEntry) -> Void) {
        Task {
            completion(await makeEntry())
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ShellyWidgetEntry>) -> Void) {
        Task {
            let entry = await makeEntry()
            let nextUpdate = entry.date.addingTimeInterval(Self.pollInterval)
            completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
        }
    }

    private func makeEntry() async -> ShellyWidgetEntry {
        switch await ShellyWidgetDataSource.fetchLatestSnapshot() {
        case .success(let snapshot):
            return ShellyWidgetEntry(date: .now, snapshot: snapshot, state: .ready)
        case .failure(let error):
            let state: ShellyWidgetEntry.State
            switch error {
            case .notConfigured:
                state = .notConfigured
            case .noDevices:
                state = .noDevices
            case .unauthorized:
                state = .authFailed
            case .failed:
                state = .error
            }
            return ShellyWidgetEntry(date: .now, snapshot: ShellyWidgetDataSource.cachedSnapshot(), state: state)
        }
    }
}
