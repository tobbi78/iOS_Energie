//
//  ShellyDailySample.swift
//  Energie
//
//  Created by Tobias Florian on 15.10.26.
//

import Foundation
import SwiftData

extension EnergieSchemaV3 {

/// One row per Shelly plug per calendar day (BACKLOG.md F14.1). The Shelly Cloud has no
/// server-side energy history — only the cumulative `aenergy.total` counter in each status — so
/// the app records its own history, folding counter differences into these rows on every poll
/// (`ShellyHistoryRecorder`, F14.2).
///
/// The counter baseline (`lastCounterWh`/`lastCounterAt`) lives on the synced row itself rather
/// than in device-local `UserDefaults`: with CloudKit mirroring (Epic 0), a second device picks
/// up the same baseline and only adds what happened since, instead of each device diffing
/// against its own stale baseline and double-counting the shared interval. Only the newest row
/// per device carries a meaningful baseline; older rows keep whatever they last had.
///
/// Every property has a declaration-site default and there's no `@Attribute(.unique)` (CloudKit
/// constraints, F0.2/F8.2) — which is also why duplicates per device/day are possible after a
/// sync race and get cleaned up by `ShellyHistoryRecorder`.
@Model
final class ShellyDailySample {
    var deviceID: String = ""
    /// Start of the calendar day this row covers.
    var date: Date = Date.distantPast
    var energyWh: Double = 0
    /// The raw `aenergy.total` (Wh) the next poll diffs against.
    var lastCounterWh: Double?
    /// When `lastCounterWh` was observed — the start of the interval the next delta is spread
    /// across (see `ShellyEnergyAccumulator`).
    var lastCounterAt: Date?

    init(
        deviceID: String,
        date: Date,
        energyWh: Double = 0,
        lastCounterWh: Double? = nil,
        lastCounterAt: Date? = nil
    ) {
        self.deviceID = deviceID
        self.date = date
        self.energyWh = energyWh
        self.lastCounterWh = lastCounterWh
        self.lastCounterAt = lastCounterAt
    }
}

}
