//
//  ShellyResponseClassifier.swift
//  Energie
//
//  Created by Tobias Florian on 15.10.26.
//

import Foundation

/// Pure interpretation of a Shelly Cloud Control API response body — no networking, no
/// dependency on `ShellyClient` beyond the error-code strings it classifies. Split out of
/// `ShellyClient` (F18.1) so this best-effort parsing (the exact error envelope isn't officially
/// documented, see SHELLY_API_WERTE.md) is independently testable without a `MockURLProtocol`
/// round trip, same reasoning as `ShellyPlugsSummary`/`ShellyDeviceList.normalizedDeviceID`.
nonisolated enum ShellyResponseClassifier {
    /// Extracts Shelly's documented error code from a failed `v2/devices/api/set/switch`
    /// response body (`code` at the top level, or nested under `error.code`) — used by
    /// `ShellyClient.setSwitch` to build `ShellyClientError.switchCommandFailed(code:)`.
    static func errorCode(fromResponseBody body: String) -> String? {
        guard let data = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        if let code = json["code"] as? String {
            return code
        }
        if let error = json["error"] as? [String: Any], let code = error["code"] as? String {
            return code
        }
        return nil
    }

    /// Known top-level/`error.code` values that mean "the `auth_key` itself was rejected" rather
    /// than some other failure — not officially documented (SHELLY_API_WERTE.md), best-effort
    /// like `errorCode(fromResponseBody:)` above.
    private static let authErrorCodes: Set<String> = ["UNAUTHORIZED", "WRONG_AUTH_KEY", "INVALID_AUTH_KEY", "UNAUTHENTICATED"]

    /// Whether this response signals a rejected `auth_key` (F11.4). Checked on *every* response,
    /// not just non-2xx ones: the older `/interface/device/list`-style endpoints are reported to
    /// sometimes answer auth failures with HTTP 200 and `{"isok": false, "errors": {...}}`
    /// instead of a 4xx status.
    static func isAuthFailure(statusCode: Int, body: String) -> Bool {
        if statusCode == 401 || statusCode == 403 {
            return true
        }
        guard let data = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return false
        }
        if let code = json["code"] as? String, authErrorCodes.contains(code.uppercased()) {
            return true
        }
        if let error = json["error"] as? [String: Any], let code = error["code"] as? String, authErrorCodes.contains(code.uppercased()) {
            return true
        }
        if let isok = json["isok"] as? Bool, !isok, let errors = json["errors"] as? [String: Any] {
            return errors.keys.contains { key in
                let lowercased = key.lowercased()
                return lowercased.contains("auth") || lowercased.contains("token")
            }
        }
        return false
    }
}
