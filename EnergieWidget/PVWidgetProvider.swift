//
//  PVWidgetProvider.swift
//  EnergieWidget
//
//  Created by Tobias Florian on 01.10.26.
//

import WidgetKit

struct PVWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> PVWidgetEntry {
        PVWidgetEntry(
            date: .now,
            snapshot: PVWidgetDataSource.Snapshot(producedWh: 4200, selfSufficiencyRate: 0.62, fetchedAt: .now),
            state: .ready
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (PVWidgetEntry) -> Void) {
        Task {
            completion(await makeEntry())
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PVWidgetEntry>) -> Void) {
        Task {
            let entry = await makeEntry()
            // WidgetKit's own daily/hourly refresh budget ultimately governs how often this
            // actually re-runs — this is only a request for "no sooner than".
            let nextUpdate = Calendar.current.date(byAdding: .minute, value: 30, to: entry.date)
                ?? entry.date.addingTimeInterval(1800)
            completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
        }
    }

    private func makeEntry() async -> PVWidgetEntry {
        switch await PVWidgetDataSource.fetchLatestSnapshot() {
        case .success(let snapshot):
            return PVWidgetEntry(date: .now, snapshot: snapshot, state: .ready)
        case .failure(let error):
            let state: PVWidgetEntry.State
            switch error {
            case .notSignedIn: state = .notSignedIn
            case .tokenExpired: state = .tokenExpired
            case .monthlyBudgetExhausted: state = .budgetExhausted
            case .invalidResponse, .http: state = .error
            }
            return PVWidgetEntry(date: .now, snapshot: PVWidgetDataSource.cachedSnapshot(), state: state)
        }
    }
}
