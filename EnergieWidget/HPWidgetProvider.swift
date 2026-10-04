//
//  HPWidgetProvider.swift
//  EnergieWidget
//
//  Created by Tobias Florian on 04.10.26.
//

import WidgetKit

struct HPWidgetProvider: TimelineProvider {
    /// Viessmann has no known fixed monthly limit (unlike Enphase) — just a safe-cadence
    /// recommendation of 5–15 minutes (see HeatPumpModel's doc comment) — so a fixed interval is
    /// used instead of PVWidgetPollPacing's budget-adaptive spreading. Matches
    /// HeatPumpModel.pollInterval's own default.
    static let pollInterval: TimeInterval = 600
    /// Same fallback reasoning as HeatPumpModel.rateLimitFallbackDelay: a wasted retry costs one
    /// API call, while waiting too long delays recovery unnecessarily when no Retry-After header
    /// is given.
    static let rateLimitFallbackDelay: TimeInterval = 3600

    func placeholder(in context: Context) -> HPWidgetEntry {
        HPWidgetEntry(
            date: .now,
            snapshot: HPWidgetDataSource.Snapshot(pressureBar: 1.4, outsideTemperatureCelsius: 8.0, fetchedAt: .now),
            state: .ready
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (HPWidgetEntry) -> Void) {
        Task {
            let (entry, _) = await makeEntry()
            completion(entry)
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<HPWidgetEntry>) -> Void) {
        Task {
            // Alerts only fire from this real, periodic refresh path — not from getSnapshot(),
            // which WidgetKit also calls for quick previews (e.g. the widget gallery), same
            // reasoning as PVWidgetProvider.
            let (entry, delay) = await makeEntry(triggerAlerts: true)
            let nextUpdate = entry.date.addingTimeInterval(delay)
            completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
        }
    }

    private func makeEntry(triggerAlerts: Bool = false) async -> (HPWidgetEntry, TimeInterval) {
        switch await HPWidgetDataSource.fetchLatestSnapshot() {
        case .success(let snapshot):
            if triggerAlerts {
                HPWidgetAlerts.check(pressureBar: snapshot.pressureBar)
            }
            return (HPWidgetEntry(date: .now, snapshot: snapshot, state: .ready), Self.pollInterval)
        case .failure(let error):
            let state: HPWidgetEntry.State
            var delay = Self.pollInterval
            switch error {
            case .notSignedIn, .refreshFailed:
                state = .notSignedIn
            case .deviceNotResolved:
                state = .deviceNotResolved
            case .rateLimited(let retryAfter):
                state = .error
                delay = retryAfter ?? Self.rateLimitFallbackDelay
            case .invalidResponse, .http:
                state = .error
            }
            return (HPWidgetEntry(date: .now, snapshot: HPWidgetDataSource.cachedSnapshot(), state: state), delay)
        }
    }
}
