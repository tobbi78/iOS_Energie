//
//  ShellyPlugsSummary.swift
//  Energie
//
//  Created by Tobias Florian on 14.10.26.
//

import Foundation

/// Aggregates the per-device status fetched by `ShellyPlugStatusLoader` into a single overview
/// for `ShellyPlugsSummaryCard` (F12.2) — "how many plugs are on, how many are offline, how much
/// power are they drawing in total" at a glance, without having to scan every `ShellyPlugCard`
/// individually once there's more than a couple of them.
///
/// Pure logic, no SwiftUI/networking dependency, same reasoning as `ShellyDeviceList`'s
/// `normalizedDeviceID` — kept testable on its own rather than computed inline in the view.
nonisolated struct ShellyPlugsSummary: Equatable {
    let deviceCount: Int
    let onCount: Int
    let offlineCount: Int
    /// Sum of `apower` across online devices with a known reading. `nil` if not a single online
    /// device has a known `apower` yet (e.g. right after launch, before the first successful
    /// refresh) — `ShellyPlugsSummaryCard` renders that as "–", same convention as
    /// `ShellyPlugCard`'s individual metrics.
    let totalPower: Double?
    /// Sum of `energyToday` (Wh, F12.3) across *all* saved devices with a known reading today —
    /// unlike `totalPower`, this includes devices that are currently offline, since "today's"
    /// consumption up to the point they went offline is still valid and shouldn't drop out of
    /// the total just because the device can't be reached right now. `nil` under the same
    /// "nothing known yet" condition as `totalPower`.
    let totalEnergyToday: Double?

    /// - Parameters:
    ///   - devices: the saved plugs (`ShellyDeviceList.devices`), defining both the count and
    ///     the order-independent set to summarize.
    ///   - statuses: latest known status per device ID (`ShellyPlugStatusLoader.statuses`).
    ///     Entries for IDs not present in `devices` are ignored — only saved devices count.
    ///     A device with no entry here (not yet loaded) is treated the same as "offline": its
    ///     state simply isn't known yet.
    ///   - energyToday: today's consumption (Wh) per device ID (`ShellyPlugStatusLoader.
    ///     energyToday`, F12.3). Defaults to empty for callers that predate F12.3.
    init(devices: [ShellyDevice], statuses: [String: ShellyDeviceStatusDTO], energyToday: [String: Double] = [:]) {
        deviceCount = devices.count

        var onCount = 0
        var offlineCount = 0
        var totalPower: Double?
        var totalEnergyToday: Double?

        for device in devices {
            if let energyForToday = energyToday[device.id] {
                totalEnergyToday = (totalEnergyToday ?? 0) + energyForToday
            }

            guard let status = statuses[device.id], status.online == true else {
                offlineCount += 1
                continue
            }
            let switch0 = status.status?.switch0
            if switch0?.output == true {
                onCount += 1
            }
            if let apower = switch0?.apower {
                totalPower = (totalPower ?? 0) + apower
            }
        }

        self.onCount = onCount
        self.offlineCount = offlineCount
        self.totalPower = totalPower
        self.totalEnergyToday = totalEnergyToday
    }
}
