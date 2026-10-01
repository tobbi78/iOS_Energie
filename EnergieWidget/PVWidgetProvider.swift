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
            snapshot: PVWidgetDataSource.Snapshot(producedWh: 4200, selfSufficiencyRate: 0.62, batterySocPercent: 54, fetchedAt: .now),
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
            // Alerts (F5.5) only fire from this real, periodic refresh path — not from
            // getSnapshot(), which WidgetKit also calls for quick previews (e.g. the widget
            // gallery) where triggering a notification would be surprising/spurious.
            let entry = await makeEntry(triggerAlerts: true)
            // Paced by remaining monthly Enphase budget (F4.2) — a fixed short interval would
            // exhaust the 1000/month limit in days. WidgetKit's own refresh budget ultimately
            // still governs how often this actually re-runs; this is only a request for
            // "no sooner than".
            let usedThisMonth = await PVWidgetDataSource.requestsUsedThisMonth()
            let delay = PVWidgetPollPacing.nextPollDelay(
                usedThisMonth: usedThisMonth,
                monthlyLimit: EnphaseRequestBudget.monthlyLimit,
                now: entry.date
            )
            let nextUpdate = entry.date.addingTimeInterval(delay)
            completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
        }
    }

    private func makeEntry(triggerAlerts: Bool = false) async -> PVWidgetEntry {
        switch await PVWidgetDataSource.fetchLatestSnapshot() {
        case .success(let snapshot):
            if triggerAlerts {
                PVWidgetAlerts.handleSuccess(snapshot: snapshot)
            }
            return PVWidgetEntry(date: .now, snapshot: snapshot, state: .ready)
        case .failure(let error):
            if triggerAlerts {
                PVWidgetAlerts.handleFailure(error)
            }
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
