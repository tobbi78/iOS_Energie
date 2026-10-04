//
//  FakeWatchConnectivitySession.swift
//  EnergieTests
//
//  Created by Tobias Florian on 04.10.26.
//
//  Stubs `WatchConnectivitySession` for `WatchSyncServiceTests` — `WCSession` itself can't be
//  instantiated/subclassed in a test host, same reasoning as `MockURLProtocol` for `URLSession`.

import Foundation
import WatchConnectivity
@testable import Energie

final class FakeWatchConnectivitySession: NSObject, WatchConnectivitySession, @unchecked Sendable {
    var activationState: WCSessionActivationState
    var isPaired: Bool
    var isWatchAppInstalled: Bool
    var delegate: WCSessionDelegate?
    var updateApplicationContextError: Error?

    private(set) var activateCallCount = 0
    private(set) var sentContexts: [[String: Any]] = []

    init(activationState: WCSessionActivationState = .activated, isPaired: Bool = true, isWatchAppInstalled: Bool = true) {
        self.activationState = activationState
        self.isPaired = isPaired
        self.isWatchAppInstalled = isWatchAppInstalled
    }

    func activate() {
        activateCallCount += 1
    }

    func updateApplicationContext(_ applicationContext: [String: Any]) throws {
        if let updateApplicationContextError {
            throw updateApplicationContextError
        }
        sentContexts.append(applicationContext)
    }
}
