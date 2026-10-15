//
//  ShellyModel.swift
//  Energie
//
//  Created by Tobias Florian on 14.10.26.
//

import Foundation
import SwiftUI

nonisolated enum ShellyPlugsState: Equatable {
    case needsCredentials
    case noDevices
    case loading
    case ready
    case error(String)
}

/// Coordinates Shelly Cloud polling for the "Steckdosen" section, independent of `SolarModel`/
/// `HeatPumpModel` (same "one model per source" principle — see HeatPumpModel's doc comment).
///
/// Runs a recurring foreground poll loop (`pollInterval`, same shape as `HeatPumpModel.startPolling`/
/// `stopPolling`) once credentials and at least one saved device exist. **Foreground only**, like
/// the heat pump's loop — iOS suspends it when the app backgrounds and it resumes (with an
/// immediate catch-up refresh) once foregrounded again. No rate-limit backoff is needed here: the
/// account-wide 1-request/second throttle (F15.1) already paces every `ShellyClient` call
/// regardless of caller, and there's no known monthly/daily quota to exhaust (F15.3).
@Observable
@MainActor
final class ShellyModel {
    private(set) var state: ShellyPlugsState = .loading
    /// Keyed by device ID so `ShellyView` can look up each `ShellyDevice`'s status directly,
    /// regardless of the order `ShellyClient.fetchDevices` happens to return them in.
    private(set) var statuses: [String: ShellyDeviceStatusDTO] = [:]
    private(set) var lastUpdated: Date?

    private let settings: ShellySettings
    private let deviceList: ShellyDeviceList
    private let client: ShellyClient
    private let now: @Sendable () -> Date
    /// Guards against a second `refresh()` starting while one is already in flight (e.g. a
    /// double pull-to-refresh racing the poll loop) — redundant with the throttle (F15.1) for
    /// correctness, but avoids needlessly queueing up a second request that would just sit
    /// waiting behind the first.
    private var isRefreshing = false

    /// How often to poll while the app is in the foreground. No known fixed limit like
    /// Enphase's monthly budget forces (see ERKENNTNISSE_MACOS.md-style reasoning in
    /// HeatPumpModel) — just the 1-request/second throttle, which a 60s cadence stays far under
    /// even with several batched devices.
    var pollInterval: TimeInterval = 60
    @ObservationIgnored private var pollTask: Task<Void, Never>?

    init(
        settings: ShellySettings,
        deviceList: ShellyDeviceList,
        client: ShellyClient? = nil,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.settings = settings
        self.deviceList = deviceList
        self.client = client ?? ShellyClient(credentials: { await settings.credentials })
        self.now = now
    }

    /// Runs once when the app starts, then keeps polling (see the class doc comment on the
    /// foreground-only caveat). Safe to call even without credentials/devices yet — `refresh()`
    /// resolves to `.needsCredentials`/`.noDevices` without a network call, and the loop picks up
    /// credentials/devices added later at its next tick.
    func start() {
        startPolling()
    }

    /// Starts (or restarts) the recurring poll loop. Safe to call repeatedly — cancels any
    /// previous loop first, so a second call never results in two loops running at once.
    func startPolling() {
        stopPolling()
        pollTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                await self.refresh()
                guard !Task.isCancelled else { return }
                try? await Task.sleep(for: .seconds(self.pollInterval))
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    func refresh() async {
        guard !isRefreshing else { return }

        guard settings.credentials.isComplete else {
            state = .needsCredentials
            return
        }
        let ids = deviceList.devices.map(\.id)
        guard !ids.isEmpty else {
            state = .noDevices
            return
        }

        isRefreshing = true
        defer { isRefreshing = false }
        // Only the very first load shows the full-screen spinner. A pull-to-refresh or poll tick
        // on already-loaded data leaves `state` at `.ready` and the card list mounted — SwiftUI's
        // native `.refreshable` spinner already communicates "in progress" on its own, and
        // swapping the whole screen out from under an in-progress pull gesture (or a background
        // poll tick) would cut that gesture off mid-interaction.
        if state != .ready {
            state = .loading
        }
        do {
            // Already batched into groups of ≤10 by `ShellyClient.fetchDevices` (F12.2/F15.2) —
            // one request regardless of how many plugs are saved, up to that per-call maximum.
            let devices = try await client.fetchDevices(ids: ids)
            let fetchTime = now()
            withAnimation {
                // `reduce(into:)` rather than `Dictionary(uniqueKeysWithValues:)` — the response
                // shape isn't verified against a real account yet (SHELLY_API_WERTE.md, "Noch
                // offen"), so a duplicate ID must not crash this screen; the later entry wins.
                statuses = devices.reduce(into: [:]) { $0[$1.id] = $1 }
                lastUpdated = fetchTime
                state = .ready
            }
        } catch {
            state = .error((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }
}
