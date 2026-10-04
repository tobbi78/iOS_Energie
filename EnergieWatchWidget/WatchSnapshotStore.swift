//
//  WatchSnapshotStore.swift
//  EnergieWatchWidget
//
//  Created by Tobias Florian on 04.10.26.
//
//  Reads the WatchSnapshot that the Watch app's WatchConnectivityReceiver last cached in the
//  shared App Group. This extension never calls WatchConnectivity or any network API itself —
//  see BACKLOG.md, "Zielplattform Apple Watch".
//
//  No shared code between targets is possible with the available project tooling, so this file
//  is intentionally duplicated from `EnergieWatch Watch App`. Keep both copies in sync by hand.

import Foundation

enum WatchSnapshotStore {
    private static let key = "WatchSnapshotStore.latest"

    /// `.empty` when nothing has ever been received yet.
    static func load() -> WatchSnapshot {
        guard let data = SharedAppGroup.userDefaults.data(forKey: key),
              let snapshot = try? JSONDecoder().decode(WatchSnapshot.self, from: data) else {
            return .empty
        }
        return snapshot
    }
}
