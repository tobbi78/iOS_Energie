//
//  WatchSnapshotStore.swift
//  EnergieWatch Watch App
//
//  Created by Tobias Florian on 04.10.26.
//
//  Persists the most recently received WatchSnapshot in the Watch-local App Group so both the
//  Watch app and the Complication widget extension (a separate process) can read the same value
//  without the widget needing its own WatchConnectivity session — the widget only ever reads
//  what `WatchConnectivityReceiver` last wrote here.
//
//  No shared code between targets is possible with the available project tooling (same
//  constraint already documented in `WatchSnapshot.swift`), so this file is intentionally
//  duplicated into `EnergieWatchWidget`. Keep both copies in sync by hand.

import Foundation

enum WatchSnapshotStore {
    private static let key = "WatchSnapshotStore.latest"

    static func save(_ snapshot: WatchSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        SharedAppGroup.userDefaults.set(data, forKey: key)
    }

    /// `.empty` when nothing has ever been received yet (e.g. right after installing the Watch
    /// app, before the iPhone has had a chance to send a first snapshot).
    static func load() -> WatchSnapshot {
        guard let data = SharedAppGroup.userDefaults.data(forKey: key),
              let snapshot = try? JSONDecoder().decode(WatchSnapshot.self, from: data) else {
            return .empty
        }
        return snapshot
    }
}
