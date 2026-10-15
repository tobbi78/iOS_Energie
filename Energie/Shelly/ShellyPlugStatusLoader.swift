//
//  ShellyPlugStatusLoader.swift
//  Energie
//
//  Created by Tobias Florian on 14.10.26.
//

import Foundation
import SwiftUI

/// Drives `ShellyView` (F12.1). Deliberately has no poll loop of its own yet — the user decided
/// F12.1 should refresh on open and via pull-to-refresh only, with a recurring loop left to
/// F16.1 once more of Epic 12 exists. `ShellyClient` already paces every request through the
/// shared account-wide throttle (F15.1) regardless of who calls it.
nonisolated enum ShellyPlugsState: Equatable {
    case needsCredentials
    case noDevices
    case loading
    case ready
    case error(String)
}

/// Loads the latest status for every saved Shelly plug in one batched call. `@Observable`/
/// `@MainActor` like `SolarModel`/`HeatPumpModel`, but much smaller — there's no persistence, no
/// auth flow, and (for now) no background polling to coordinate.
@Observable
@MainActor
final class ShellyPlugStatusLoader {
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
    /// double pull-to-refresh) — redundant with the throttle (F15.1) for correctness, but avoids
    /// needlessly queueing up a second request that would just sit waiting behind the first.
    private var isRefreshing = false

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
        // Only the very first load shows the full-screen spinner. A pull-to-refresh on already-
        // loaded data leaves `state` at `.ready` and the card list mounted — SwiftUI's native
        // `.refreshable` spinner already communicates "in progress" on its own, and swapping the
        // whole screen out from under an in-progress pull gesture would cut that gesture off
        // mid-interaction.
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
