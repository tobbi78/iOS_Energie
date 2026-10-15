//
//  ShellyResponseClassifierTests.swift
//  EnergieTests
//
//  Created by Tobias Florian on 15.10.26.
//

import Foundation
import Testing
@testable import Energie

/// Direct tests for `ShellyResponseClassifier` (F18.1) — the same scenarios `ShellyClientTests`
/// already covers end-to-end via `MockURLProtocol`, but exercised here without any networking,
/// since the parsing itself is pure.
@Suite
struct ShellyResponseClassifierTests {

    // MARK: - errorCode(fromResponseBody:)

    @Test func errorCodeExtractsATopLevelCode() {
        #expect(ShellyResponseClassifier.errorCode(fromResponseBody: #"{"code":"DEVICE_OFFLINE"}"#) == "DEVICE_OFFLINE")
    }

    @Test func errorCodeExtractsANestedCode() {
        #expect(ShellyResponseClassifier.errorCode(fromResponseBody: #"{"error":{"code":"DEVICE_FAILED_COMMAND"}}"#) == "DEVICE_FAILED_COMMAND")
    }

    @Test func errorCodeReturnsNilForAnUnrecognizedBody() {
        #expect(ShellyResponseClassifier.errorCode(fromResponseBody: #"{"message":"oops"}"#) == nil)
    }

    @Test func errorCodeReturnsNilForBodyThatIsNotJSON() {
        #expect(ShellyResponseClassifier.errorCode(fromResponseBody: "not json") == nil)
    }

    @Test func errorCodeReturnsNilForAnEmptyBody() {
        #expect(ShellyResponseClassifier.errorCode(fromResponseBody: "") == nil)
    }

    // MARK: - isAuthFailure(statusCode:body:) — HTTP status

    @Test func isAuthFailureIsTrueFor401() {
        #expect(ShellyResponseClassifier.isAuthFailure(statusCode: 401, body: "{}"))
    }

    @Test func isAuthFailureIsTrueFor403() {
        #expect(ShellyResponseClassifier.isAuthFailure(statusCode: 403, body: "{}"))
    }

    @Test func isAuthFailureIsFalseForAnUnrelatedHTTPError() {
        #expect(!ShellyResponseClassifier.isAuthFailure(statusCode: 500, body: "{}"))
    }

    // MARK: - isAuthFailure(statusCode:body:) — body-based detection on an otherwise-2xx response

    @Test func isAuthFailureDetectsATopLevelAuthErrorCode() {
        #expect(ShellyResponseClassifier.isAuthFailure(statusCode: 200, body: #"{"code":"WRONG_AUTH_KEY"}"#))
    }

    @Test func isAuthFailureDetectsANestedAuthErrorCode() {
        #expect(ShellyResponseClassifier.isAuthFailure(statusCode: 200, body: #"{"error":{"code":"INVALID_AUTH_KEY"}}"#))
    }

    @Test func isAuthFailureIsCaseInsensitiveForTheErrorCode() {
        #expect(ShellyResponseClassifier.isAuthFailure(statusCode: 200, body: #"{"code":"wrong_auth_key"}"#))
    }

    @Test func isAuthFailureDetectsAnIsokFalseBodyWithAnAuthRelatedErrorKey() {
        #expect(ShellyResponseClassifier.isAuthFailure(statusCode: 200, body: #"{"isok":false,"errors":{"auth_key":"invalid"}}"#))
    }

    @Test func isAuthFailureDetectsAnIsokFalseBodyWithATokenRelatedErrorKey() {
        #expect(ShellyResponseClassifier.isAuthFailure(statusCode: 200, body: #"{"isok":false,"errors":{"token":"expired"}}"#))
    }

    @Test func isAuthFailureIgnoresAnIsokFalseBodyWithoutAnAuthOrTokenErrorKey() {
        #expect(!ShellyResponseClassifier.isAuthFailure(statusCode: 200, body: #"{"isok":false,"errors":{"device_id":"missing"}}"#))
    }

    @Test func isAuthFailureIgnoresAnIsokTrueBody() {
        #expect(!ShellyResponseClassifier.isAuthFailure(statusCode: 200, body: #"{"isok":true}"#))
    }

    @Test func isAuthFailureIsFalseForAnUnrelatedErrorCodeOn2xx() {
        #expect(!ShellyResponseClassifier.isAuthFailure(statusCode: 200, body: #"{"code":"DEVICE_OFFLINE"}"#))
    }

    @Test func isAuthFailureIsFalseForBodyThatIsNotJSON() {
        #expect(!ShellyResponseClassifier.isAuthFailure(statusCode: 200, body: "not json"))
    }

    @Test func isAuthFailureIsFalseForAnEmptySuccessBody() {
        #expect(!ShellyResponseClassifier.isAuthFailure(statusCode: 200, body: "{}"))
    }
}
