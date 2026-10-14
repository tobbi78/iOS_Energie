//
//  ShellyDTO.swift
//  Energie
//
//  Created by Tobias Florian on 14.10.26.
//

import Foundation

// MARK: - `/interface/device/list` (F11.3, "automatisch suchen")

/// A single device as found by the (community-documented, unverified) discovery endpoint.
/// `name`/`type` are best-effort — not every observed response shape is known to include them,
/// see `ShellyDeviceListResponse`.
nonisolated struct ShellyDiscoveredDevice: Decodable, Equatable, Identifiable {
    let id: String
    let name: String?
    let type: String?
}

/// Tolerant top-level decode for `/interface/device/list`. The actual response shape is
/// **unverified** (SHELLY_API_WERTE.md, "Noch offen") — this supports the two shapes considered
/// plausible for a Shelly-cloud-style `{"isok": ..., "data": {...}}` envelope: `data.devices` as
/// a JSON array of device objects (each carrying its own `id`), or as an object keyed by device
/// ID (common for older Shelly cloud endpoints, where the key *is* the ID). Update this once a
/// real account confirms the actual shape, and record the finding in SHELLY_API_WERTE.md.
nonisolated struct ShellyDeviceListResponse: Decodable {
    let devices: [ShellyDiscoveredDevice]

    private enum CodingKeys: String, CodingKey {
        case data
    }

    private struct DataWrapper: Decodable {
        let devices: DevicesField?
    }

    private struct KeyedDeviceFields: Decodable {
        let name: String?
        let type: String?
    }

    /// Either a JSON array of devices, or an object keyed by device ID.
    private enum DevicesField: Decodable {
        case array([ShellyDiscoveredDevice])
        case keyed([String: KeyedDeviceFields])

        init(from decoder: Decoder) throws {
            if let array = try? [ShellyDiscoveredDevice](from: decoder) {
                self = .array(array)
                return
            }
            self = .keyed(try [String: KeyedDeviceFields](from: decoder))
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let wrapper = try container.decode(DataWrapper.self, forKey: .data)
        switch wrapper.devices {
        case .array(let devices):
            self.devices = devices
        case .keyed(let keyed):
            self.devices = keyed.map { ShellyDiscoveredDevice(id: $0.key, name: $0.value.name, type: $0.value.type) }
        case .none:
            self.devices = []
        }
    }
}

// MARK: - `/v2/devices/api/get` (F11.3 ID-Prüfung, F12.1 Statusabruf)

/// A single device's identity/reachability from `v2/devices/api/get`. `status` is only
/// populated for Gen2+ devices whose `Switch.GetStatus` shape (SHELLY_API_WERTE.md) this app
/// understands (F12.1) — Gen1 devices (`relays[]`/`meters[]`) or an unrecognized shape simply
/// decode to `nil`, which `ShellyPlugCard` renders as "–" rather than failing the whole lookup.
/// F11.3's device-ID verification only ever needed `id`/`type`, so `status` being absent there
/// doesn't change that flow.
nonisolated struct ShellyDeviceStatusDTO: Decodable, Equatable {
    let id: String
    let type: String?
    let code: String?
    let gen: Int?
    let online: Bool?
    let status: ShellyDeviceStatus?
}

/// Gen2+ JSON-RPC component status (SHELLY_API_WERTE.md, "Gen2+") — only the `Switch` component
/// at index 0 is decoded, since the confirmed hardware (Backlog F12.1) is a Plug S-family
/// single-channel plug. A device with more than one switch channel, or a non-`Switch` component
/// (`PM1`/`EM`/`EM1`), simply yields `switch0 == nil`.
nonisolated struct ShellyDeviceStatus: Decodable, Equatable {
    let switch0: ShellySwitchStatus?

    private enum CodingKeys: String, CodingKey {
        case switch0 = "switch:0"
    }
}

/// `Switch.GetStatus` fields relevant to F12.1's metric card. All optional — a field missing
/// from a real response (firmware differences, a component still booting, …) degrades to "–" in
/// the UI rather than discarding the whole status.
nonisolated struct ShellySwitchStatus: Decodable, Equatable {
    let output: Bool?
    let apower: Double?
    let voltage: Double?
    let current: Double?
    /// Cumulative energy since the last device reboot (F12.3) — `ShellyDailyEnergyTracker` turns
    /// this into a "today" figure, since it is not one itself (SHELLY_API_WERTE.md).
    let aenergy: ShellyEnergyCounter?
}

/// `Switch.GetStatus`'s `aenergy` object. Only `total` (Wh, cumulative since the last reboot)
/// matters for F12.3 — `by_minute`/`minute_ts` (last 3 minutes only) aren't a substitute for a
/// real daily total and are left undecoded.
nonisolated struct ShellyEnergyCounter: Decodable, Equatable {
    let total: Double?
}

/// Tolerant top-level decode for `/v2/devices/api/get` — same caveat as
/// `ShellyDeviceListResponse`: the exact envelope isn't settled by the official docs quoted in
/// SHELLY_API_WERTE.md, only the per-device fields are. Tries, in order: a bare top-level array,
/// `data.result`, `data` itself as the array.
nonisolated struct ShellyDeviceStatusResponse: Decodable {
    let devices: [ShellyDeviceStatusDTO]

    private struct ResultEnvelope: Decodable {
        let data: DataWrapper
    }

    private struct DataWrapper: Decodable {
        let result: [ShellyDeviceStatusDTO]?
    }

    private struct DataArrayEnvelope: Decodable {
        let data: [ShellyDeviceStatusDTO]
    }

    init(from decoder: Decoder) throws {
        if let bareArray = try? [ShellyDeviceStatusDTO](from: decoder) {
            devices = bareArray
            return
        }
        if let resultEnvelope = try? ResultEnvelope(from: decoder), let result = resultEnvelope.data.result {
            devices = result
            return
        }
        if let dataArrayEnvelope = try? DataArrayEnvelope(from: decoder) {
            devices = dataArrayEnvelope.data
            return
        }
        throw DecodingError.dataCorrupted(DecodingError.Context(
            codingPath: decoder.codingPath,
            debugDescription: "Unrecognized Shelly device-status response shape"
        ))
    }
}
