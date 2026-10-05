//
//  OAuthState.swift
//  Energie
//
//  Created by Tobias Florian on 05.10.26.
//

import Foundation
import Security

/// Generates the random `state` value sent with an OAuth2 authorization request and verified
/// against the callback (RFC 6749 §10.12) — CSRF protection shared by the Enphase and Viessmann
/// sign-in flows, neither of which previously sent one.
enum OAuthState {
    /// 32 random bytes, base64url-encoded (~43 characters) — same shape as
    /// `ViessmannPKCE.makeCodeVerifier`, but kept separate since PKCE and `state` serve different
    /// purposes (proof of client identity vs. CSRF protection) and Enphase has no PKCE at all.
    static func generate(byteCount: Int = 32) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        _ = SecRandomCopyBytes(kSecRandomDefault, byteCount, &bytes)
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
