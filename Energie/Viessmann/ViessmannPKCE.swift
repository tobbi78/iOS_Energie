//
//  ViessmannPKCE.swift
//  Energie
//
//  Created by Tobias Florian on 01.10.26.
//

import CryptoKit
import Foundation

/// RFC 7636 PKCE values for the Viessmann OAuth2 authorization-code flow. PKCE replaces the
/// client secret Enphase needs (see Plans/Waermepumpe-Integration.md, Abschnitt 3): the
/// verifier stays on-device, only its SHA-256 challenge is sent with the authorization request,
/// and the verifier itself is sent once at token-exchange time to prove the two requests came
/// from the same client.
struct ViessmannPKCE {
    let codeVerifier: String
    let codeChallenge: String

    init(codeVerifier: String = ViessmannPKCE.makeCodeVerifier()) {
        self.codeVerifier = codeVerifier
        self.codeChallenge = ViessmannPKCE.makeCodeChallenge(for: codeVerifier)
    }

    /// 32 random bytes, base64url-encoded (~43 characters) — within RFC 7636's required
    /// 43–128 character range.
    static func makeCodeVerifier(byteCount: Int = 32) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        _ = SecRandomCopyBytes(kSecRandomDefault, byteCount, &bytes)
        return base64URLEncode(Data(bytes))
    }

    static func makeCodeChallenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return base64URLEncode(Data(digest))
    }

    private static func base64URLEncode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
