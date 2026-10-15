//
//  ShellyEndpointsTests.swift
//  EnergieTests
//
//  Created by Tobias Florian on 15.10.26.
//

import Foundation
import Testing
@testable import Energie

/// Request-construction tests for `ShellyEndpoints` (F18.1), analogous to `EnphaseEndpointsTests`/
/// `ViessmannEndpointsTests` — covers only what's shaped here, not what happens with the
/// response (that's `ShellyClientTests`).
struct ShellyEndpointsTests {
    private let server = "https://shelly-12-eu.shelly.cloud"

    // MARK: - deviceListRequest

    @Test func deviceListRequestPostsFormEncodedToTheDeviceListPath() throws {
        let request = ShellyEndpoints.deviceListRequest(server: server, authKey: "the-auth-key")
        #expect(request.httpMethod == "POST")
        #expect(request.url?.absoluteString == "https://shelly-12-eu.shelly.cloud/interface/device/list")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/x-www-form-urlencoded")
        let body = try #require(request.httpBody)
        #expect(String(data: body, encoding: .utf8) == "auth_key=the-auth-key")
    }

    @Test func deviceListRequestPercentEncodesAPlusInTheAuthKeyBody() throws {
        let request = ShellyEndpoints.deviceListRequest(server: server, authKey: "abc+def=")
        let body = try #require(request.httpBody)
        #expect(String(data: body, encoding: .utf8) == "auth_key=abc%2Bdef%3D")
    }

    // MARK: - deviceStatusRequest

    @Test func deviceStatusRequestPostsToTheV2GetPathWithTheAuthKeyAsAQueryItem() throws {
        let request = ShellyEndpoints.deviceStatusRequest(server: server, authKey: "the-auth-key", ids: ["a1b2c3"])
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        let url = try #require(request.url)
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(components.path == "/v2/devices/api/get")
        #expect(components.queryItems?.first(where: { $0.name == "auth_key" })?.value == "the-auth-key")
    }

    @Test func deviceStatusRequestBodyContainsIDsAndRequestsTheStatusSelect() throws {
        let request = ShellyEndpoints.deviceStatusRequest(server: server, authKey: "k", ids: ["a1b2c3", "d4e5f6"])
        let body = try #require(request.httpBody)
        let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["ids"] as? [String] == ["a1b2c3", "d4e5f6"])
        #expect(json["select"] as? [String] == ["status"])
    }

    @Test func deviceStatusRequestPercentEncodesAPlusInTheAuthKeyQueryValue() throws {
        let request = ShellyEndpoints.deviceStatusRequest(server: server, authKey: "abc+def/ghi=", ids: ["a1b2c3"])
        let url = try #require(request.url)
        #expect(!url.absoluteString.contains("+"))
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(components.queryItems?.first(where: { $0.name == "auth_key" })?.value == "abc+def/ghi=")
    }

    // MARK: - setSwitchRequest

    @Test func setSwitchRequestPostsToTheSetSwitchPathWithTheAuthKeyAsAQueryItem() throws {
        let request = ShellyEndpoints.setSwitchRequest(server: server, authKey: "the-auth-key", id: "a1b2c3", channel: 0, on: true)
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        let url = try #require(request.url)
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(components.path == "/v2/devices/api/set/switch")
        #expect(components.queryItems?.first(where: { $0.name == "auth_key" })?.value == "the-auth-key")
    }

    @Test func setSwitchRequestBodyContainsIDChannelAndOn() throws {
        let request = ShellyEndpoints.setSwitchRequest(server: server, authKey: "k", id: "a1b2c3", channel: 0, on: false)
        let body = try #require(request.httpBody)
        let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["id"] as? String == "a1b2c3")
        #expect(json["channel"] as? Int == 0)
        #expect(json["on"] as? Bool == false)
    }

    @Test func setSwitchRequestPercentEncodesAPlusInTheAuthKeyQueryValue() throws {
        let request = ShellyEndpoints.setSwitchRequest(server: server, authKey: "abc+def/ghi=", id: "a1b2c3", channel: 0, on: true)
        let url = try #require(request.url)
        #expect(!url.absoluteString.contains("+"))
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(components.queryItems?.first(where: { $0.name == "auth_key" })?.value == "abc+def/ghi=")
    }
}
