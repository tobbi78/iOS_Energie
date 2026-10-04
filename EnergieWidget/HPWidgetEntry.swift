//
//  HPWidgetEntry.swift
//  EnergieWidget
//
//  Created by Tobias Florian on 04.10.26.
//

import WidgetKit

struct HPWidgetEntry: TimelineEntry {
    let date: Date
    /// The most recent known snapshot — either freshly fetched or the last cached one — so the
    /// widget can keep showing a value even when a fetch fails (see `HPWidgetDataSource`).
    let snapshot: HPWidgetDataSource.Snapshot?
    let state: State

    enum State {
        case ready
        case notSignedIn
        /// Device selection hasn't been resolved yet — happens once, right after the user's
        /// first sign-in in the app, before `HeatPumpModel` has had a chance to run.
        case deviceNotResolved
        case error
    }
}
