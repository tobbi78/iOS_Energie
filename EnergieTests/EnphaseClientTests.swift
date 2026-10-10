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

    @Test func performThrowsBudgetExhaustedWithASmallerConfiguredMonthlyLimit() async throws {
        let budget = EnphaseRequestBudget(userDefaults: UserDefaults(suiteName: UUID().uuidString)!)
        for _ in 0..<180 { await budget.recordRequest() }

        let client = EnphaseClient(
            urlSession: MockURLProtocol.makeSession(),
            throttle: EnphaseRequestThrottle(),
            budget: budget,
            apiKey: { "key" },
            accessToken: { "token" },
            reserve: { 20 },
            monthlyLimit: { 200 }
        )

        // Threshold with a configured limit of 200 and reserve 20 is 180 — 180 already-used
        // requests exhaust it, even though the default 1000/month limit would still allow more.
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

    private func makeClient() -> EnphaseClient {
        EnphaseClient(
            urlSession: MockURLProtocol.makeSession(),
            throttle: EnphaseRequestThrottle(),
            budget: EnphaseRequestBudget(userDefaults: UserDefaults(suiteName: UUID().uuidString)!),
            apiKey: { "key" },
            accessToken: { "token" }
        )
    }

    // MARK: - Lifetime (daily) series (F3.2/F3.3) — thin wrappers around perform(), but still
    // worth a direct round-trip each since they're the only call site for their respective DTOs.

    @Test func fetchEnergyLifetimeDecodesResponse() async throws {
        MockURLProtocol.requestHandler = { request in
            MockURLProtocol.jsonResponse(url: request.url!, json: #"{"start_date":"2026-01-01","production":[1,2,3]}"#)
        }
        let response = try await makeClient().fetchEnergyLifetime(systemID: 1)
        #expect(response.production == [1, 2, 3])
    }

    @Test func fetchConsumptionLifetimeDecodesResponse() async throws {
        MockURLProtocol.requestHandler = { request in
            MockURLProtocol.jsonResponse(url: request.url!, json: #"{"start_date":"2026-01-01","consumption":[4,5]}"#)
        }
        let response = try await makeClient().fetchConsumptionLifetime(systemID: 1)
        #expect(response.consumption == [4, 5])
    }

    @Test func fetchImportLifetimeDecodesResponse() async throws {
        MockURLProtocol.requestHandler = { request in
            MockURLProtocol.jsonResponse(url: request.url!, json: #"{"start_date":"2026-01-01","import":[6]}"#)
        }
        let response = try await makeClient().fetchImportLifetime(systemID: 1)
        #expect(response.imported == [6])
    }

    @Test func fetchExportLifetimeDecodesResponse() async throws {
        MockURLProtocol.requestHandler = { request in
            MockURLProtocol.jsonResponse(url: request.url!, json: #"{"start_date":"2026-01-01","export":[7]}"#)
        }
        let response = try await makeClient().fetchExportLifetime(systemID: 1)
        #expect(response.exported == [7])
    }

    @Test func fetchBatteryLifetimeDecodesResponse() async throws {
        MockURLProtocol.requestHandler = { request in
            MockURLProtocol.jsonResponse(url: request.url!, json: #"{"start_date":"2026-01-01","charge":[8],"discharge":[9]}"#)
        }
        let response = try await makeClient().fetchBatteryLifetime(systemID: 1)
        #expect(response.charge == [8])
        #expect(response.discharge == [9])
    }

    @Test func performThrowsInvalidResponseAndHTTPErrors() async throws {
        MockURLProtocol.requestHandler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: "HTTP/1.1", headerFields: nil)!, Data("server error".utf8))
        }
        await #expect(throws: EnphaseClientError.http(status: 500, body: "server error")) {
            try await makeClient().fetchSystems()
        }
    }

    @Test func performDecodesARealWorldPlanUsageLimit429() async throws {
        // Exact body observed from a live 429 (2026-10-05 incident, see BACKLOG.md) — no
        // `period`/`period_end` at all, just `message`/`details`/`code`. Regression test for
        // the mislabeling bug this uncovered (see EnphaseBudgetTests for the pure-errorDescription
        // variants of this case).
        MockURLProtocol.requestHandler = { request in
            MockURLProtocol.jsonResponse(
                url: request.url!,
                status: 429,
                json: #"{"message":"Too Many Requests","details":"Usage limit exceeded for plan Watt","code":429}"#
            )
        }
        await #expect(throws: EnphaseClientError.rateLimited(period: nil, periodEnd: nil, detail: "Usage limit exceeded for plan Watt")) {
            try await makeClient().fetchSystems()
        }
    }
}

}
