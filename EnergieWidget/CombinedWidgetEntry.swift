//
//  CombinedWidgetEntry.swift
//  EnergieWidget
//
//  Created by Tobias Florian on 04.10.26.
//
//  A combined tile showing both energy sources at once, for users who'd rather place one
//  widget than two. Each side keeps its own snapshot/state independently (same "a failure on
//  one side must never affect the other" principle as the rest of the app, see BACKLOG.md's
//  "Übertragbares Architekturmuster") — reuses the existing per-source state enums and
//  snapshot types directly since this is the same compilation target.
//

import WidgetKit

struct CombinedWidgetEntry: TimelineEntry {
    let date: Date
    let pvSnapshot: PVWidgetDataSource.Snapshot?
    let pvState: PVWidgetEntry.State
    let heatPumpSnapshot: HPWidgetDataSource.Snapshot?
    let heatPumpState: HPWidgetEntry.State
    /// `nil`/`.notConfigured`/`.noDevices` hide the Shelly section entirely (F16.3,
    /// Nutzerentscheidung 2026-10-15) — a user without Shelly set up sees this tile exactly as
    /// before, rather than an empty/placeholder third section.
    let shellySnapshot: ShellyWidgetSnapshot?
    let shellyState: ShellyWidgetEntry.State
}
