//
//  ShellyEndpoints.swift
//  Energie
//
//  Created by Tobias Florian on 14.10.26.
//

import Foundation

/// URL/request construction for the Shelly Cloud Control API. Unlike Enphase/Viessmann, the
/// server itself is tenant-based and comes from the user's own credentials (`ShellyCredentials`)
/// rather than a fixed `baseURL` — see SHELLY_API_WERTE.md.
enum ShellyEndpoints {
    /// `/interface/device/list` (F11.3) — only community-documented, not part of the official
    /// API reference; verify its actual response shape against a real account before relying on
    /// it (see `ShellyDTO.swift`'s tolerant decoding and SHELLY_API_WERTE.md, "Noch offen").
    static func deviceListRequest(server: String, authKey: String) -> URLRequest {
        formEncodedRequest(server: server, path: "/interface/device/list", parameters: ["auth_key": authKey])
    }

    /// `/v2/devices/api/get` (F11.3 ID-Prüfung, später F12 Statusabruf) — up to 10 device IDs
    /// per call (SHELLY_API_WERTE.md); callers are responsible for chunking larger lists
    /// (`ShellyClient` does this).
    static func deviceStatusRequest(server: String, authKey: String, ids: [String]) -> URLRequest {
        precondition(!ids.isEmpty && ids.count <= 10, "deviceStatusRequest takes 1–10 device IDs per call")

        // `URLComponents`/`URLQueryItem` leave `+` unescaped in query values (it's a legal
        // RFC 3986 query character), but Shelly's server decodes query parameters using
        // form-urlencoded conventions where `+` means space — an `auth_key` containing `+`
        // would silently get corrupted into a space and fail auth with HTTP 401. Encode it by
        // hand with the same stricter charset `formEncodedRequest` already uses below.
        let encodedAuthKey = authKey.addingPercentEncoding(withAllowedCharacters: .urlQueryValueAllowed) ?? authKey
        let url = URL(string: server + "/v2/devices/api/get?auth_key=" + encodedAuthKey)!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["ids": ids, "select": ["status"]])
        return request
    }

    private static func formEncodedRequest(server: String, path: String, parameters: [String: String]) -> URLRequest {
        var request = URLRequest(url: URL(string: server + path)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = parameters
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryValueAllowed) ?? $0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)
        return request
    }
}

private extension CharacterSet {
    /// Same stricter allowed-set as `ViessmannOAuthClient`'s private copy — also escapes `+`,
    /// `&` and `=`, which must not appear literally inside a form-urlencoded value. Duplicated
    /// rather than shared since both are file-private to their own file.
    static let urlQueryValueAllowed: CharacterSet = {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return allowed
    }()
}
