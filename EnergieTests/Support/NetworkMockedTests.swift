//
//  NetworkMockedTests.swift
//  EnergieTests
//
//  Created by Tobias Florian on 04.10.26.
//

import Testing

/// Shared namespace/parent suite for every test that stubs `URLSession` via `MockURLProtocol`.
/// `MockURLProtocol.requestHandler` is a single shared static var, so tests that set it must
/// never run concurrently with each other — `.serialized` on a suite only serializes that
/// suite's own tests, not unrelated suites, so all such tests are nested here as child suites
/// (via `extension NetworkMockedTests`) rather than declared as independent top-level suites.
@Suite(.serialized)
enum NetworkMockedTests {}
