//
//  SharedAppGroup.swift
//  EnergieWatch Watch App
//
//  Created by Tobias Florian on 04.10.26.
//
//  App Group shared between the Watch app and its Complication widget extension, so both can
//  see the same locally-stored WatchSnapshot (see WatchSnapshotStore.swift) without the widget
//  needing its own WatchConnectivity session. Uses the same group identifier as the iPhone side
//  (`Energie/SharedAppGroup.swift`) purely for naming consistency — the Watch and the iPhone are
//  separate devices with separate storage, so this is never actually shared across them; only
//  WatchConnectivity (see WatchSyncService on the iPhone, WatchConnectivityReceiver here) bridges
//  the two devices.
//
//  No shared code between targets is possible with the available project tooling (same
//  constraint already documented in the iPhone-side `SharedAppGroup.swift`), so this file is
//  intentionally duplicated into `EnergieWatchWidget`. Keep both copies in sync by hand.

import Foundation

enum SharedAppGroup {
    static let identifier = "group.de.florian.tobias.Energie"

    static var userDefaults: UserDefaults {
        UserDefaults(suiteName: identifier) ?? .standard
    }
}
