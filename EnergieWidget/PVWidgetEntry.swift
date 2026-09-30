//
//  PVWidgetEntry.swift
//  EnergieWidget
//
//  Created by Tobias Florian on 01.10.26.
//

import WidgetKit

struct PVWidgetEntry: TimelineEntry {
    let date: Date
    /// The most recent known snapshot — either freshly fetched or the last cached one — so the
    /// widget can keep showing a value even when a fetch fails (see `PVWidgetDataSource`).
    let snapshot: PVWidgetDataSource.Snapshot?
    let state: State

    enum State {
        case ready
        case notSignedIn
        case tokenExpired
        case budgetExhausted
        case error
    }
}
