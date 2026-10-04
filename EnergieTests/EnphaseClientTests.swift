//
//  EnphaseClientTests.swift
//  EnergieTests
//
//  Created by Tobias Florian on 04.10.26.
//

import Foundation
import Testing
@testable import Energie

extension NetworkMockedTests {

@Suite
struct EnphaseClientTests {
    @Test func performAllowsRequestWithinASmallerConfiguredReserve() async throws {
        let budget = EnphaseRequestBudget(userDefaults: UserDefaults(suiteName: UUID().uuidString)!)
        for _ in 0..<990 { await budget.recordRequest() }

        MockURLProtocol.requestHandler = { request in
            MockURLProtocol.jsonResponse(url: request.url!, json: #"{"systems":[{"system_id":1}]}"#)
        }
        let client = EnphaseClient(
            urlSession: MockURLProtocol.makeSession(),
            throttle: EnphaseRequestThrottle(),
            budget: budget,
            apiKey: { "key" },
            accessToken: { "token" },
            reserve: { 5 }
        )

        // Threshold with reserve 5 is 995 — 990 already-used requests must still be allowed.
        let systems = try await client.fetchSystems()
        #expect(systems.first?.systemID == 1)
    }

    @Test func performThrowsBudgetExhaustedWithALargerConfiguredReserve() async throws {
        let budget = EnphaseRequestBudget(userDefaults: UserDefaults(suiteName: UUID().uuidString)!)
        for _ in 0..<990 { await budget.recordRequest() }

        let client = EnphaseClient(
            urlSession: MockURLProtocol.makeSession(),
            throttle: EnphaseRequestThrottle(),
            budget: budget,
            apiKey: { "key" },
            accessToken: { "token" },
            reserve: { 20 }
        )

        // Threshold with reserve 20 is 980 — 990 already-used requests exceed it.
        await #expect(throws: EnphaseClientError.monthlyBudgetExhausted) {
            try await client.fetchSystems()
        }
    }

    @Test func performUsesDefaultReserveWhenNoneProvided() async throws {
        let budget = EnphaseRequestBudget(userDefaults: UserDefaults(suiteName: UUID().uuidString)!)
        for _ in 0..<985 { await budget.recordRequest() }

        let client = EnphaseClient(
            urlSession: MockURLProtocol.makeSession(),
            throttle: EnphaseRequestThrottle(),
            budget: budget,
            apiKey: { "key" },
            accessToken: { "token" }
        )

        // Default reserve is 20 -> threshold 980 — 985 already exceeds it, with no reserve passed.
        await #expect(throws: EnphaseClientError.monthlyBudgetExhausted) {
            try await client.fetchSystems()
        }
    }
}

}
