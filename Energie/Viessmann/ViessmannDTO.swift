//
//  ViessmannDTO.swift
//  Energie
//
//  Created by Tobias Florian on 01.10.26.
//

import Foundation

/// Response shapes for the Viessmann equipment-discovery endpoints (installations → gateways →
/// devices). Same caveat as `ViessmannEndpoints`: based on the publicly documented API shape,
/// not yet verified against a real account.

struct ViessmannListResponse<Element: Decodable>: Decodable {
    let data: [Element]
}

struct ViessmannInstallationDTO: Decodable, Identifiable {
    let id: Int
    let description: String?
}

struct ViessmannGatewayDTO: Decodable, Identifiable {
    let serial: String
    let gatewayType: String?

    var id: String { serial }
}

struct ViessmannDeviceDTO: Decodable, Identifiable {
    let id: String
    let deviceType: String?
    let modelId: String?
    let status: String?
}

extension Array where Element == ViessmannDeviceDTO {
    /// Best-effort pick of the actual heating device, not the gateway pseudo-device that also
    /// shows up in this list (see ERKENNTNISSE_MACOS.md, "Falsches Gerät wurde gepollt").
    /// **Heuristic, unverified**: prefers a device whose `deviceType` isn't "gateway". With
    /// exactly one device, or none matching, falls back to the first entry so callers always get
    /// a deterministic pick to show in a confirmation/selection UI (HP-4 settings screen) rather
    /// than silently guessing wrong.
    var mostLikelyHeatingDevice: ViessmannDeviceDTO? {
        first(where: { $0.deviceType?.lowercased() != "gateway" }) ?? first
    }
}
