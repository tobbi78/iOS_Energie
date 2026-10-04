//
//  HeatPumpPressureAlert.swift
//  Energie
//
//  Created by Tobias Florian on 04.10.26.
//

import Foundation

/// The three kinds of pressure alert. `.drop` and `.repeatReminder` share the same wording (both
/// mean "still too low"); `.recovery` is the all-clear. Ported from the macOS sibling project's
/// `PressureAlertTracker`/`PressureAlertKind`.
enum HeatPumpPressureAlertKind {
    case drop
    case repeatReminder
    case recovery
}

/// Decides whether the current poll should trigger a pressure alert, given the previous state.
/// Pure and stateless per call — `HeatPumpModel` holds the actual state between polls and passes
/// it in, same pattern as `HeatPumpEfficiencyTracker.periodsNeedingSnapshot`.
enum HeatPumpPressureAlertTracker {
    struct State: Equatable {
        var isBelowThreshold = false
        var lastNotifiedAt: Date?
    }

    /// - Parameters:
    ///   - currentPressure: `nil` when the sensor value wasn't in the poll — no alert, no state
    ///     change, since we can't tell whether the pressure actually recovered.
    ///   - now: the current poll's timestamp.
    ///   - state: the state after the previous call (or `State()` if this is the first poll).
    ///   - recoveryEnabled: whether an all-clear notification is wanted once the pressure recovers.
    ///   - repeatInterval: how long to wait between repeat reminders while still below.
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
                // Crossing down: always notify, regardless of repeatInterval.
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
