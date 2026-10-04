//
//  HeatPumpPressureAlert.swift
//  EnergieWidget
//
//  Created by Tobias Florian on 04.10.26.
//
//  Byte-identical duplicate of Energie/HeatPumpPressureAlert.swift (see ViessmannEndpoints.swift
//  for why). Keep both copies in sync by hand.

import Foundation

enum HeatPumpPressureAlertKind {
    case drop
    case repeatReminder
    case recovery
}

enum HeatPumpPressureAlertTracker {
    struct State: Equatable {
        var isBelowThreshold = false
        var lastNotifiedAt: Date?
    }

    static func evaluate(
        currentPressure: Double?,
        threshold: Double,
        now: Date,
        state: State,
        recoveryEnabled: Bool,
        repeatInterval: TimeInterval
    ) -> (alert: HeatPumpPressureAlertKind?, state: State) {
        guard let currentPressure else {
            return (nil, state)
        }

        if currentPressure < threshold {
            if !state.isBelowThreshold {
                return (.drop, State(isBelowThreshold: true, lastNotifiedAt: now))
            }
            if let lastNotifiedAt = state.lastNotifiedAt, now.timeIntervalSince(lastNotifiedAt) >= repeatInterval {
                return (.repeatReminder, State(isBelowThreshold: true, lastNotifiedAt: now))
            }
            return (nil, state)
        }

        let recovered = state.isBelowThreshold
        let newState = State(isBelowThreshold: false, lastNotifiedAt: nil)
        return (recovered && recoveryEnabled ? .recovery : nil, newState)
    }
}
