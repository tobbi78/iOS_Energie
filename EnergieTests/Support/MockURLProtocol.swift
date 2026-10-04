//
//  MockURLProtocol.swift
//  EnergieTests
//
//  Created by Tobias Florian on 04.10.26.
//

import Foundation

/// Stubs `URLSession` for tests that exercise real network-calling code (OAuth clients,
/// `ViessmannClient`) without touching the network. `requestHandler` is set once per test right
/// before the call under test and read exactly once per request — tests that use this must be
/// declared in a `@Suite(.serialized)` suite so concurrent tests never race on the shared handler.
final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    static var requestHandler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = MockURLProtocol.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    static func jsonResponse(url: URL, status: Int = 200, headers: [String: String] = [:], json: String) -> (HTTPURLResponse, Data) {
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
        return (response, Data(json.utf8))
    }

    /// `URLSession` sometimes moves a `POST` body into `httpBodyStream` instead of leaving it on
    /// `httpBody` by the time a request reaches a custom `URLProtocol` — read whichever is set.
    static func bodyData(from request: URLRequest) -> Data? {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 4096
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: bufferSize)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }
}
