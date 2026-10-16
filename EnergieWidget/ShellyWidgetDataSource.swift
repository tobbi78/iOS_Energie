//
//  ShellyWidgetDataSource.swift
//  EnergieWidget
//
//  Created by Tobias Florian on 16.10.26.
//
//  Deliberately minimal and self-contained, same reasoning as PVWidgetDataSource/
//  HPWidgetDataSource: reads whichever credentials/device list the app already saved and does
//  its own status fetch (F16.3), rather than depending on `ShellyModel`'s poll loop, which only
//  runs while the app itself is in the foreground. Unlike the Viessmann widget, there's no OAuth
//  token to refresh here — Shelly's `auth_key` either still works or it doesn't (F11.4) — so this
//  stays a single fetch-and-cache round trip.
//

import Foundation

enum ShellyWidgetDataSource {
    /// Same App Group suite as the other widgets' data sources — reused directly rather than
    /// duplicated, since all three are already compiled into this one widget extension target.
    static let sharedDefaults = PVWidgetDataSource.sharedDefaults
    private static let cacheKey = "ShellyWidgetDataSource.lastSnapshot"

    enum FetchError: Error {
        /// No (complete) `ShellyCredentials` saved yet (F11.1).
        case notConfigured
        /// Credentials exist, but the user hasn't added any plugs yet (F11.3).
        case noDevices
        /// The stored `auth_key` was rejected (F11.4) — surfaced distinctly so the widget can
        /// point at "open the app" rather than a generic retry.
        case unauthorized
        case failed
    }

    static func cachedSnapshot() -> ShellyWidgetSnapshot? {
        guard let data = sharedDefaults.data(forKey: cacheKey) else { return nil }
        return try? JSONDecoder().decode(ShellyWidgetSnapshot.self, from: data)
    }

    static func fetchLatestSnapshot() async -> Result<ShellyWidgetSnapshot, FetchError> {
        let store = ShellyKeychainStore()
        let credentials = ShellyCredentials(
            serverURI: store.read(.serverURI) ?? "",
            authKey: store.read(.authKey) ?? ""
        )
        guard credentials.isComplete else {
            return .failure(.notConfigured)
        }

        let devices = ShellyDeviceList.loadDevices(from: SharedAppGroup.userDefaults)
        guard !devices.isEmpty else {
            return .failure(.noDevices)
        }

        let client = ShellyClient(credentials: { credentials })
        do {
            let statuses = try await client.fetchDevices(ids: devices.map(\.id))
            // Later entries win on a duplicate ID, same tolerance as `ShellyModel.refresh` —
            // the response shape isn't verified against a real account yet
            // (SHELLY_API_WERTE.md, "Noch offen").
            let statusByID = statuses.reduce(into: [String: ShellyDeviceStatusDTO]()) { $0[$1.id] = $1 }
            let fetchTime = Date()
            let snapshot = ShellyWidgetSnapshot(devices: devices, statuses: statusByID, fetchedAt: fetchTime)
            if let data = try? JSONEncoder().encode(snapshot) {
                sharedDefaults.set(data, forKey: cacheKey)
            }
            return .success(snapshot)
        } catch ShellyClientError.unauthorized {
            return .failure(.unauthorized)
        } catch {
            return .failure(.failed)
        }
    }
}
