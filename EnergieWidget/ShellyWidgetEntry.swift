//
//  ShellyWidgetEntry.swift
//  EnergieWidget
//
//  Created by Tobias Florian on 16.10.26.
//

import WidgetKit

struct ShellyWidgetEntry: TimelineEntry {
    let date: Date
    /// The most recent known snapshot — either freshly fetched or the last cached one — so the
    /// widget can keep showing a value even when a fetch fails, same reasoning as
    /// `HPWidgetEntry.snapshot`.
    let snapshot: ShellyWidgetSnapshot?
    let state: State

    enum State {
        case ready
        /// No (complete) Shelly credentials saved yet (F11.1).
        case notConfigured
        /// Credentials exist, but no plugs have been added yet (F11.3).
        case noDevices
        /// The stored `auth_key` was rejected (F11.4).
        case authFailed
        case error
    }
}
