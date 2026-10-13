//
//  WatchSnapshot.swift
//  Energie
//
//  Created by Tobias Florian on 04.10.26.
//
//  The payload sent from the iPhone app to a paired Apple Watch via WatchConnectivity (see
//  WatchSyncService). The Watch app and its Complication widget extension never make their own
//  network calls (see BACKLOG.md, "Zielplattform Apple Watch" — companion model, not an
//  independent on-watch poller, to avoid Viessmann refresh-token rotation conflicts and extra
//  Enphase budget consumption): they only ever display the most recently received snapshot.
//
//  Shared with `EnergieWatch Watch App` and `EnergieWatchWidget` via multi-target membership
//  (File Inspector), not a separate copy per target.
//
//  Each side (PV/heat pump) stays independently optional — same "a failure on one side must
//  never affect the other" principle as the rest of the app (see BACKLOG.md's
//  "Übertragbares Architekturmuster"). Field names/units mirror the existing widget snapshots
//  (`PVWidgetDataSource.Snapshot`, `HPWidgetDataSource.Snapshot`) so values can be passed through
//  without conversion.

import Foundation

nonisolated struct WatchSnapshot: Codable, Equatable {
    // MARK: PV (Enphase)
    var pvProducedTodayWh: Double?
    var pvSelfSufficiencyRate: Double?
    var pvBatterySocPercent: Double?
    var pvFetchedAt: Date?

    // MARK: Wärmepumpe (Viessmann)
    var heatPumpPressureBar: Double?
    var heatPumpOutsideTemperatureCelsius: Double?
    var heatPumpPressureAlertActive: Bool
    var heatPumpFetchedAt: Date?

    /// Placeholder shown on the Watch before the first snapshot has ever arrived.
    static let empty = WatchSnapshot(
        pvProducedTodayWh: nil,
        pvSelfSufficiencyRate: nil,
        pvBatterySocPercent: nil,
        pvFetchedAt: nil,
        heatPumpPressureBar: nil,
        heatPumpOutsideTemperatureCelsius: nil,
        heatPumpPressureAlertActive: false,
        heatPumpFetchedAt: nil
    )
}
