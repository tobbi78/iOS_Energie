//
//  ShellyDeviceList.swift
//  Energie
//
//  Created by Tobias Florian on 14.10.26.
//

import Foundation

/// A single Shelly plug the user has added to the app (F11.3). `id` is the Shelly device ID
/// itself (not a local UUID) — the same value sent to `v2/devices/api/get`/later
/// `set/switch` (F13), so it has to stay stable across app launches rather than being
/// regenerated.
nonisolated struct ShellyDevice: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var model: String?
}

/// Locally stored list of the user's Shelly plugs (F11.3). Unlike Enphase/Viessmann, there's no
/// server-side "my systems" list the app can trust unconditionally — the one endpoint that comes
/// close, `/interface/device/list`, is only community-documented and may not work at all (see
/// `ShellyClient.discoverDevices`) — so the authoritative list lives on-device, populated either
/// from that endpoint or typed in by hand.
///
/// Backed by the shared App Group `UserDefaults` (not plain `.standard`), like
/// `EnphaseBudgetSettings`, so a future widget (F16.3) can read the same device list without
/// duplicating it.
@Observable
@MainActor
final class ShellyDeviceList {
    nonisolated static let devicesKey = "ShellyDeviceList.devices"

    private static let allowedDeviceIDCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789")

    private let userDefaults: UserDefaults
    private(set) var devices: [ShellyDevice]

    init(userDefaults: UserDefaults = SharedAppGroup.userDefaults) {
        self.userDefaults = userDefaults
        devices = Self.loadDevices(from: userDefaults)
    }

    /// Reads the saved device list without needing a `ShellyDeviceList` instance — used by
    /// `ShellyWidgetDataSource` (F16.3), which runs in the widget extension process and has no
    /// reason to pull in the `@MainActor`/`@Observable` wrapper just to read a snapshot.
    nonisolated static func loadDevices(from userDefaults: UserDefaults) -> [ShellyDevice] {
        guard let data = userDefaults.data(forKey: devicesKey),
              let decoded = try? JSONDecoder().decode([ShellyDevice].self, from: data) else {
            return []
        }
        return decoded
    }

    /// Returns `false` without changing anything if a device with this ID is already present —
    /// the ID is the Shelly device ID itself, so a duplicate add is always a mistake (the same
    /// physical plug added twice), never a legitimate second entry.
    @discardableResult
    func add(_ device: ShellyDevice) -> Bool {
        guard !devices.contains(where: { $0.id == device.id }) else { return false }
        devices.append(device)
        persist()
        return true
    }

    /// Equivalent to `RangeReplaceableCollection.remove(atOffsets:)`, reimplemented by hand so
    /// this model file doesn't need to import SwiftUI (that extension lives there, not in
    /// Foundation) just for this one convenience method.
    func remove(atOffsets offsets: IndexSet) {
        for index in offsets.sorted(by: >) {
            devices.remove(at: index)
        }
        persist()
    }

    /// Equivalent to `RangeReplaceableCollection.move(fromOffsets:toOffset:)`, reimplemented by
    /// hand for the same reason as `remove(atOffsets:)` above (that extension lives in SwiftUI,
    /// not Foundation). Used by the "Bearbeiten"/drag-to-reorder list in `ShellyDevicesScreen`
    /// (F17.2) — the saved order is also the order `ShellyView`'s card list renders in.
    func move(fromOffsets offsets: IndexSet, toOffset destination: Int) {
        let moved = offsets.map { devices[$0] }
        var adjustedDestination = destination
        for index in offsets.sorted(by: >) {
            devices.remove(at: index)
            if index < adjustedDestination {
                adjustedDestination -= 1
            }
        }
        devices.insert(contentsOf: moved, at: adjustedDestination)
        persist()
    }

    /// Renames a saved device (F17.2). Returns `false` without changing anything if `id` isn't
    /// known, or if the trimmed name is empty — an unnamed plug would just fall back to showing
    /// its raw ID everywhere, which is strictly worse than rejecting the rename outright.
    @discardableResult
    func rename(id: String, to name: String) -> Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, let index = devices.firstIndex(where: { $0.id == id }) else { return false }
        devices[index].name = trimmedName
        persist()
        return true
    }

    /// Normalizes a user-typed Shelly device ID: trims whitespace, lowercases it, and rejects
    /// anything containing characters outside `[a-z0-9]` — a device ID with a stray space or
    /// punctuation can only be a typo, never a real Shelly ID (in the Shelly app under
    /// "Device → Settings → Device Information", see F11.3).
    static func normalizedDeviceID(_ input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty, trimmed.unicodeScalars.allSatisfy({ allowedDeviceIDCharacters.contains($0) }) else {
            return nil
        }
        return trimmed
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(devices) else { return }
        userDefaults.set(data, forKey: Self.devicesKey)
    }
}
