//
//  ShellyWidgetSnapshot.swift
//  EnergieWidget
//
//  Created by Tobias Florian on 16.10.26.
//

import Foundation

/// Everything `ShellyWidget`/`CombinedWidget` (F16.3) need to render, derived once from a fresh
/// `ShellyClient.fetchDevices` result and then cached as-is (`Codable`) so a failed refresh can
/// still show the last known state. Deliberately just glue over already-tested app-side logic —
/// `ShellyPlugsSummary` for the counters and `ShellyPlugDisplay` for the per-plug state/
/// formatting (F18.1) — rather than duplicating or re-testing that logic here, same reasoning as
/// `HPWidgetDataSource.Snapshot` staying a plain value type.
nonisolated struct ShellyWidgetSnapshot: Codable, Equatable {
    /// One saved plug's widget-relevant state, in the same order as `ShellyDeviceList.devices`
    /// (F17.2) — the list/widget rows read top-to-bottom in the order the user arranged them.
    struct Plug: Codable, Equatable {
        let id: String
        let name: String
        let isOnline: Bool
        /// `nil` when the current switch state isn't known yet — same meaning as
        /// `ShellyPlugDisplay.output`.
        let output: Bool?
        let formattedPower: String
    }

    let totalPower: Double?
    let onCount: Int
    let deviceCount: Int
    let offlineCount: Int
    let plugs: [Plug]
    let fetchedAt: Date

    init(devices: [ShellyDevice], statuses: [String: ShellyDeviceStatusDTO], fetchedAt: Date) {
        let summary = ShellyPlugsSummary(devices: devices, statuses: statuses)
        totalPower = summary.totalPower
        onCount = summary.onCount
        deviceCount = summary.deviceCount
        offlineCount = summary.offlineCount
        self.fetchedAt = fetchedAt
        plugs = devices.map { device in
            let display = ShellyPlugDisplay(status: statuses[device.id])
            return Plug(
                id: device.id,
                name: device.name,
                isOnline: display.isOnline,
                output: display.output,
                formattedPower: display.formattedPower
            )
        }
    }
}
