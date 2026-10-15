//
//  ShellyPlugDisplay.swift
//  Energie
//
//  Created by Tobias Florian on 15.10.26.
//

import Foundation

/// Derives everything `ShellyPlugCard` (F12.1/F13.1) needs to render from a single plug's raw
/// `ShellyDeviceStatusDTO?` — online/switch state, whether it's currently safe to offer the
/// schalten button, and the W/V/A formatting. Pure logic, no SwiftUI dependency, same reasoning
/// as `ShellyPlugsSummary` (F18.1): kept testable on its own rather than computed inline in the
/// view.
nonisolated struct ShellyPlugDisplay: Equatable {
    let status: ShellyDeviceStatusDTO?

    private var switchStatus: ShellySwitchStatus? {
        status?.status?.switch0
    }

    var isOnline: Bool {
        status?.online ?? false
    }

    /// `nil` when the current switch state isn't known yet (not yet loaded, or a Gen1/
    /// unrecognized status shape) — same meaning as `ShellyPlugsSummary`'s per-device handling.
    var output: Bool? {
        switchStatus?.output
    }

    /// Whether the status badge should act as a schalten button — online with a known switch
    /// state. Offline or unknown state stays non-interactive: there's nothing sensible to
    /// switch *to* without knowing the current state, and an offline device would just fail
    /// with `DEVICE_OFFLINE` immediately anyway (same reasoning as the card's original inline
    /// check).
    var canToggle: Bool {
        isOnline && output != nil
    }

    var formattedPower: String {
        Self.formatPower(switchStatus?.apower)
    }

    var formattedVoltage: String {
        Self.formatVoltage(switchStatus?.voltage)
    }

    var formattedCurrent: String {
        Self.formatCurrent(switchStatus?.current)
    }

    /// Shared with `ShellyPlugsSummaryCard`'s total-power display so the "–"/rounding convention
    /// for a Shelly power reading only exists in one place.
    static func formatPower(_ watts: Double?) -> String {
        guard let watts else { return "–" }
        return watts.formatted(.number.precision(.fractionLength(0))) + " W"
    }

    static func formatVoltage(_ volts: Double?) -> String {
        guard let volts else { return "–" }
        return volts.formatted(.number.precision(.fractionLength(1))) + " V"
    }

    static func formatCurrent(_ amps: Double?) -> String {
        guard let amps else { return "–" }
        return amps.formatted(.number.precision(.fractionLength(2))) + " A"
    }
}
