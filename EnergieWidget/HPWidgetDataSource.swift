//
//  HPWidgetDataSource.swift
//  EnergieWidget
//
//  Created by Tobias Florian on 04.10.26.
//
//  Deliberately minimal and self-contained (see PVWidgetDataSource's doc comment for the same
//  reasoning). Unlike the PV widget, this one DOES perform its own OAuth token refresh: Viessmann
//  access tokens only last ~1h (`expires_in` on the token response), while PV's widget can get
//  away with only ever reading whatever the app already has, because that token lives far
//  longer. Without self-refresh here, the entire point of this widget — the Anlagendruck-Alarm
//  firing while the app is closed — would stop working after about an hour. The refreshed tokens
//  are written back to the shared Keychain, so the app itself also picks them up next time it
//  reads its own ViessmannSettings.
//

import Foundation
import Security

/// Reads/writes the same Keychain items `ViessmannKeychainStore` does. No `kSecAttrAccessGroup`
/// set explicitly on either side, same as `PVWidgetKeychain` — both targets share the one
/// `keychain-access-groups` entitlement.
private enum HPWidgetKeychain {
    private static let service = "de.florian.tobias.Energie.viessmann"

    static func readString(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func writeString(account: String, value: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        guard let data = value.data(using: .utf8) else { return }

        let attributesToUpdate: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributesToUpdate as CFDictionary)

        if updateStatus == errSecItemNotFound {
            var newItem = query
            newItem[kSecValueData as String] = data
            newItem[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            SecItemAdd(newItem as CFDictionary, nil)
        }
    }
}

enum HPWidgetDataSource {
    /// Same App Group suite as the PV widget's data source — reused directly rather than
    /// duplicated, since both are already compiled into this one widget extension target.
    static let sharedDefaults = PVWidgetDataSource.sharedDefaults
    private static let cacheKey = "HPWidgetDataSource.lastSnapshot"

    struct Snapshot: Codable {
        let pressureBar: Double?
        let outsideTemperatureCelsius: Double?
        let fetchedAt: Date
    }

    enum FetchError: Error {
        case notSignedIn
        case deviceNotResolved
        case refreshFailed
        case rateLimited(retryAfter: TimeInterval?)
        case invalidResponse
        case http(Int)
    }

    static func cachedSnapshot() -> Snapshot? {
        guard let data = sharedDefaults.data(forKey: cacheKey) else { return nil }
        return try? JSONDecoder().decode(Snapshot.self, from: data)
    }

    static func fetchLatestSnapshot() async -> Result<Snapshot, FetchError> {
        guard let clientID = HPWidgetKeychain.readString(account: "clientID"),
              let refreshToken = HPWidgetKeychain.readString(account: "refreshToken") else {
            return .failure(.notSignedIn)
        }
        guard let installationIDString = HPWidgetKeychain.readString(account: "installationID"),
              let installationID = Int(installationIDString),
              let gatewaySerial = HPWidgetKeychain.readString(account: "gatewaySerial"),
              let deviceID = HPWidgetKeychain.readString(account: "deviceID") else {
            return .failure(.deviceNotResolved)
        }

        guard var accessToken = HPWidgetKeychain.readString(account: "accessToken") else {
            return .failure(.notSignedIn)
        }

        let expiresAtString = HPWidgetKeychain.readString(account: "tokenExpiresAt")
        let expiresAtInterval = expiresAtString.flatMap(TimeInterval.init)
        let isExpired = expiresAtInterval.map { Date() >= Date(timeIntervalSince1970: $0).addingTimeInterval(-60) } ?? true

        if isExpired {
            do {
                let refreshed = try await refreshAccessToken(refreshToken: refreshToken, clientID: clientID)
                accessToken = refreshed.accessToken
                HPWidgetKeychain.writeString(account: "accessToken", value: refreshed.accessToken)
                HPWidgetKeychain.writeString(account: "refreshToken", value: refreshed.refreshToken)
                HPWidgetKeychain.writeString(account: "tokenExpiresAt", value: String(refreshed.expiresAt.timeIntervalSince1970))
            } catch {
                return .failure(.refreshFailed)
            }
        }

        do {
            let features: [ViessmannFeatureDTO] = try await fetchFeatures(
                installationID: installationID, gatewaySerial: gatewaySerial, deviceID: deviceID, accessToken: accessToken
            )
            let snapshot = Snapshot(
                pressureBar: features.numericValue("heating.sensors.pressure.supply"),
                outsideTemperatureCelsius: features.numericValue("heating.sensors.temperature.outside"),
                fetchedAt: Date()
            )
            if let data = try? JSONEncoder().encode(snapshot) {
                sharedDefaults.set(data, forKey: cacheKey)
            }
            return .success(snapshot)
        } catch let error as FetchError {
            return .failure(error)
        } catch {
            return .failure(.invalidResponse)
        }
    }

    // MARK: - Token refresh

    private struct TokenResponse: Decodable {
        let accessToken: String
        let refreshToken: String?
        let expiresIn: TimeInterval

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
            case expiresIn = "expires_in"
        }
    }

    private static func refreshAccessToken(
        refreshToken: String, clientID: String
    ) async throws -> (accessToken: String, refreshToken: String, expiresAt: Date) {
        var request = URLRequest(url: ViessmannEndpoints.tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = ViessmannEndpoints.tokenRefreshBody(clientID: clientID, refreshToken: refreshToken)
        request.httpBody = body
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryValueAllowed) ?? $0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            throw FetchError.refreshFailed
        }
        let decoded = try JSONDecoder().decode(TokenResponse.self, from: data)
        guard let newRefreshToken = decoded.refreshToken ?? Optional(refreshToken) else {
            throw FetchError.refreshFailed
        }
        return (decoded.accessToken, newRefreshToken, Date().addingTimeInterval(decoded.expiresIn))
    }

    // MARK: - Features

    private static func fetchFeatures(
        installationID: Int, gatewaySerial: String, deviceID: String, accessToken: String
    ) async throws -> [ViessmannFeatureDTO] {
        var request = URLRequest(url: ViessmannEndpoints.featuresURL(
            installationID: installationID, gatewaySerial: gatewaySerial, deviceID: deviceID
        ))
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw FetchError.invalidResponse
        }
        switch httpResponse.statusCode {
        case 200..<300:
            break
        case 401:
            throw FetchError.refreshFailed
        case 429:
            let retryAfter = httpResponse.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init)
            throw FetchError.rateLimited(retryAfter: retryAfter)
        default:
            throw FetchError.http(httpResponse.statusCode)
        }
        let decoded: ViessmannListResponse<ViessmannFeatureDTO> = try JSONDecoder.viessmann.decode(
            ViessmannListResponse<ViessmannFeatureDTO>.self, from: data
        )
        return decoded.data
    }
}

private extension CharacterSet {
    static let urlQueryValueAllowed: CharacterSet = {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return allowed
    }()
}
