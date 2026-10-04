//
//  ViessmannDTO.swift
//  EnergieWidget
//
//  Created by Tobias Florian on 04.10.26.
//
//  Byte-identical duplicate of Energie/Viessmann/ViessmannDTO.swift (see ViessmannEndpoints.swift
//  for why). Keep both copies in sync by hand.

import Foundation

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
    /// and only ever see `tcu.*` network features, never `heating.*` sensor data.
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
/// generically and interpreted where displayed.
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
    /// the plain `.iso8601` strategy does not parse.
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
