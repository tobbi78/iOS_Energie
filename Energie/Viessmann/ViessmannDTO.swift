//
//  ViessmannDTO.swift
//  Energie
//
//  Created by Tobias Florian on 01.10.26.
//

import Foundation

/// Response shapes for the Viessmann equipment-discovery and features endpoints. Verified
/// against the real, working implementation in the macOS sibling project
/// (https://github.com/tobbi78/Dashboard_Waermepumpe, `Viessmann/ViessmannDTO.swift`) — an
/// earlier version of this file guessed at separate `/gateways`/`/devices` endpoints, which
/// don't exist; `includeGateways=true` on the installations call nests everything in one response.

// MARK: - Equipment discovery

struct ViessmannListResponse<Element: Decodable>: Decodable {
    let data: [Element]
}

struct ViessmannInstallationDTO: Decodable, Identifiable {
    let id: Int
    let description: String?
    let gateways: [ViessmannGatewayDTO]
}

struct ViessmannGatewayDTO: Decodable, Identifiable {
    let serial: String
    let devices: [ViessmannDeviceDTO]

    var id: String { serial }
}

struct ViessmannDeviceDTO: Decodable, Identifiable {
    let id: String
    let deviceType: String?
    let modelId: String?
}

extension Array where Element == ViessmannDeviceDTO {
    /// The gateway itself (e.g. Vitoconnect) shows up as a pseudo-device with id `"gateway"`
    /// alongside the actual heating appliance — picking blindly by array order can land on it
    /// and only ever see `tcu.*` network features, never `heating.*` sensor data. Confirmed via
    /// the real bug/fix in the macOS sibling project (`DashboardModel.resolveInstallation`,
    /// `gatewayPseudoDeviceID`). Falls back to the first device if, unexpectedly, every entry is
    /// the gateway — callers should treat that as "nothing useful found", not a hidden success.
    var mostLikelyHeatingDevice: ViessmannDeviceDTO? {
        first(where: { $0.id != "gateway" }) ?? first
    }
}

// MARK: - Features

struct ViessmannFeatureDTO: Decodable {
    let feature: String
    let isEnabled: Bool
    let isReady: Bool
    let timestamp: Date?
    let properties: [String: ViessmannFeaturePropertyDTO]
}

struct ViessmannFeaturePropertyDTO: Decodable {
    let type: String?
    let value: ViessmannFeatureValue
    let unit: String?
}

/// The Viessmann features API returns wildly heterogeneous property shapes (numbers, strings,
/// booleans, arrays of consumption stats, ...) — see VIESSMANN_API_WERTE.md. Modeling each
/// feature as its own struct would break on every firmware/API update, so values are captured
/// generically and interpreted where displayed (HP-4). Ported as-is from the macOS sibling
/// project's `FeatureValue`.
enum ViessmannFeatureValue: Decodable {
    case number(Double)
    case bool(Bool)
    case string(String)
    case stringArray([String])
    case numberArray([Double])
    case other

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String].self) {
            self = .stringArray(value)
        } else if let value = try? container.decode([Double].self) {
            self = .numberArray(value)
        } else {
            self = .other
        }
    }

    var numericValue: Double? {
        switch self {
        case .number(let value): return value
        case .bool(let value): return value ? 1 : 0
        default: return nil
        }
    }

    /// Viessmann's consumption-history properties (`heating.power.consumption.*`'s `day`/`week`/
    /// `month`/`year`) decode straight into this case — confirmed live on-device 2026-10-11, see
    /// VIESSMANN_API_WERTE.md.
    var numberArrayValue: [Double]? {
        switch self {
        case .numberArray(let value): return value
        default: return nil
        }
    }

    var stringRepresentation: String? {
        switch self {
        case .string(let value): return value
        case .bool(let value): return String(value)
        case .stringArray(let value): return value.joined(separator: ",")
        case .numberArray(let value): return value.map { String($0) }.joined(separator: ",")
        case .number, .other: return nil
        }
    }
}

extension JSONDecoder {
    /// Viessmann timestamps include fractional seconds (e.g. "2026-09-21T10:00:00.000Z"), which
    /// the plain `.iso8601` strategy does not parse. Ported from the macOS sibling project.
    static let viessmann: JSONDecoder = {
        let decoder = JSONDecoder()
        let withFractional = ISO8601DateFormatter()
        withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let withoutFractional = ISO8601DateFormatter()
        withoutFractional.formatOptions = [.withInternetDateTime]

        decoder.dateDecodingStrategy = .custom { dateDecoder in
            let container = try dateDecoder.singleValueContainer()
            let string = try container.decode(String.self)
            if let date = withFractional.date(from: string) ?? withoutFractional.date(from: string) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date: \(string)")
        }
        return decoder
    }()
}
