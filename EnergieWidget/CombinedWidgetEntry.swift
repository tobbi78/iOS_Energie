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
}
