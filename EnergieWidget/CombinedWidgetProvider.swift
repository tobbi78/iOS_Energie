//
//  CombinedWidgetProvider.swift
//  EnergieWidget
//
//  Created by Tobias Florian on 04.10.26.
//
//  Polls both data sources independently on every real refresh (async let — a slow/failed
//  fetch on one side never blocks or fails the other) and still triggers both sources' alerts
//  (PVWidgetAlerts/HPWidgetAlerts), so a user who places only this combined tile instead of the
//  two individual ones doesn't lose the Anlagenausfall/Druckalarm notifications.
//
//  Next-update timing takes the *minimum* of both sources' own pacing: PV stays budget-safe
//  (PVWidgetPollPacing reads the actual month-to-date usage and backs off on its own, and
//  EnphaseClient's budget gate still refuses a request outright if that's ever not enough — see
//  its own doc comments), while the heat pump still gets checked at least as often as its own
//  widget would (its 429/monthly-limit situation is unbounded, see HPWidgetProvider). The only
//  real trade-off: placing this tile exhausts the shared Enphase budget sooner than the PV-only
//  widget would on its own, because it polls PV at least as often as the heat pump wants to —
//  acceptable since a user who chooses the combined tile is presumably not also running the
//  separate PV tile at the same time.
//

import WidgetKit

struct CombinedWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> CombinedWidgetEntry {
        CombinedWidgetEntry(
            date: .now,
            pvSnapshot: PVWidgetDataSource.Snapshot(producedWh: 4200, selfSufficiencyRate: 0.62, batterySocPercent: 54, fetchedAt: .now),
            pvState: .ready,
            heatPumpSnapshot: HPWidgetDataSource.Snapshot(pressureBar: 1.4, outsideTemperatureCelsius: 8.0, fetchedAt: .now),
            heatPumpState: .ready
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (CombinedWidgetEntry) -> Void) {
        Task {
            let (entry, _) = await makeEntry()
            completion(entry)
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CombinedWidgetEntry>) -> Void) {
        Task {
            let (entry, delay) = await makeEntry(triggerAlerts: true)
            let nextUpdate = entry.date.addingTimeInterval(delay)
            completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
        }
    }

    private func makeEntry(triggerAlerts: Bool = false) async -> (CombinedWidgetEntry, TimeInterval) {
        async let pvResult = PVWidgetDataSource.fetchLatestSnapshot()
        async let hpResult = HPWidgetDataSource.fetchLatestSnapshot()
        async let usedThisMonth = PVWidgetDataSource.requestsUsedThisMonth()

        let (pvSnapshot, pvState) = resolvePV(await pvResult, triggerAlerts: triggerAlerts)
        let (hpSnapshot, hpState, hpDelay) = resolveHeatPump(await hpResult, triggerAlerts: triggerAlerts)

        let pvDelay = PVWidgetPollPacing.nextPollDelay(
            usedThisMonth: await usedThisMonth,
            monthlyLimit: EnphaseRequestBudget.monthlyLimit,
            reserve: PVWidgetDataSource.configuredReserve,
            now: .now
        )

        let entry = CombinedWidgetEntry(
            date: .now,
            pvSnapshot: pvSnapshot,
            pvState: pvState,
            heatPumpSnapshot: hpSnapshot,
            heatPumpState: hpState
        )
        return (entry, min(pvDelay, hpDelay))
    }

    private func resolvePV(
        _ result: Result<PVWidgetDataSource.Snapshot, PVWidgetDataSource.FetchError>, triggerAlerts: Bool
    ) -> (PVWidgetDataSource.Snapshot?, PVWidgetEntry.State) {
        switch result {
        case .success(let snapshot):
            if triggerAlerts {
                PVWidgetAlerts.handleSuccess(snapshot: snapshot)
            }
            return (snapshot, .ready)
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
            return (PVWidgetDataSource.cachedSnapshot(), state)
        }
    }

    private func resolveHeatPump(
        _ result: Result<HPWidgetDataSource.Snapshot, HPWidgetDataSource.FetchError>, triggerAlerts: Bool
    ) -> (HPWidgetDataSource.Snapshot?, HPWidgetEntry.State, TimeInterval) {
        switch result {
        case .success(let snapshot):
            if triggerAlerts {
                HPWidgetAlerts.check(pressureBar: snapshot.pressureBar)
            }
            return (snapshot, .ready, HPWidgetProvider.pollInterval)
        case .failure(let error):
            let state: HPWidgetEntry.State
            var delay = HPWidgetProvider.pollInterval
            switch error {
            case .notSignedIn, .refreshFailed:
                state = .notSignedIn
            case .deviceNotResolved:
                state = .deviceNotResolved
            case .rateLimited(let retryAfter):
                state = .error
                delay = retryAfter ?? HPWidgetProvider.rateLimitFallbackDelay
            case .invalidResponse, .http:
                state = .error
            }
            return (HPWidgetDataSource.cachedSnapshot(), state, delay)
        }
    }
}
