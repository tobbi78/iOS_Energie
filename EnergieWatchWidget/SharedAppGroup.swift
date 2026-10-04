//
//  SharedAppGroup.swift
//  EnergieWatchWidget
//
//  Created by Tobias Florian on 04.10.26.
//
//  App Group shared with the Watch app (see the Watch app's own `SharedAppGroup.swift` for why
//  this uses the same identifier as the iPhone side). This complication extension never talks
//  to WatchConnectivity itself — it only reads whatever the Watch app last cached here via
//  `WatchSnapshotStore`.
//
//  No shared code between targets is possible with the available project tooling, so this file
//  is intentionally duplicated from `EnergieWatch Watch App`. Keep both copies in sync by hand.

import Foundation

enum SharedAppGroup {
    static let identifier = "group.de.florian.tobias.Energie"

    static var userDefaults: UserDefaults {
        UserDefaults(suiteName: identifier) ?? .standard
    }
}
