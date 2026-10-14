//
//  ShellyPlugCard.swift
//  Energie
//
//  Created by Tobias Florian on 14.10.26.
//

import SwiftUI

/// Per-plug metric card for F12.1: current power (W), voltage (V), current (A), and the on/off
/// switch state, from `Switch.GetStatus` (SHELLY_API_WERTE.md, "Gen2+"). A `nil` `status` (plug
/// not yet loaded, offline, or an unrecognized response shape) renders every value as "–" rather
/// than hiding the card — the saved device itself (name/ID) is always known even before the
/// first successful refresh.
///
/// Its own view rather than four `MetricCard`s in a grid — a state badge plus three related
/// readings for one physical device reads better as a single card — but it borrows `MetricCard`'s
/// visual language (same background/corner radius) so the "Steckdosen" tab doesn't look out of
/// place next to PV/Wärmepumpe.
struct ShellyPlugCard: View {
    let device: ShellyDevice
    let status: ShellyDeviceStatusDTO?

    private var switchStatus: ShellySwitchStatus? {
        status?.status?.switch0
    }

    private var isOnline: Bool {
        status?.online ?? false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            HStack(spacing: 0) {
                metric(title: "Leistung", value: formattedPower(switchStatus?.apower), icon: "bolt.fill")
                Divider().frame(height: 36)
                metric(title: "Spannung", value: formattedVoltage(switchStatus?.voltage), icon: "waveform.path")
                Divider().frame(height: 36)
                metric(title: "Strom", value: formattedCurrent(switchStatus?.current), icon: "gauge")
            }
        }
        .padding()
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private var header: some View {
        HStack {
            Image(systemName: "powerplug.fill")
                .font(.title3)
                .foregroundStyle(.shellyAccent)
            Text(device.name)
                .font(.headline)
            Spacer()
            statusBadge
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        if !isOnline {
            badge(text: "Offline", color: .secondary)
        } else if let output = switchStatus?.output {
            badge(text: output ? "An" : "Aus", color: output ? .green : .secondary)
        } else {
            badge(text: "–", color: .secondary)
        }
    }

    private func badge(text: String, color: Color) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }

    private func metric(title: String, value: String, icon: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.bold())
                .contentTransition(.numericText())
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    /// One spoken-out sentence instead of the default per-subview concatenation
    /// (`.accessibilityElement(children: .combine)`), which would read the status badge and each
    /// metric's icon/value/title as disconnected fragments.
    private var accessibilitySummary: String {
        var parts = [device.name]
        if !isOnline {
            parts.append("Offline")
        } else if let output = switchStatus?.output {
            parts.append(output ? "Eingeschaltet" : "Ausgeschaltet")
        }
        parts.append("Leistung \(formattedPower(switchStatus?.apower))")
        parts.append("Spannung \(formattedVoltage(switchStatus?.voltage))")
        parts.append("Strom \(formattedCurrent(switchStatus?.current))")
        return parts.joined(separator: ", ")
    }

    private func formattedPower(_ watts: Double?) -> String {
        guard let watts else { return "–" }
        return watts.formatted(.number.precision(.fractionLength(0))) + " W"
    }

    private func formattedVoltage(_ volts: Double?) -> String {
        guard let volts else { return "–" }
        return volts.formatted(.number.precision(.fractionLength(1))) + " V"
    }

    private func formattedCurrent(_ amps: Double?) -> String {
        guard let amps else { return "–" }
        return amps.formatted(.number.precision(.fractionLength(2))) + " A"
    }

}

#Preview("An") {
    ShellyPlugCard(
        device: ShellyDevice(id: "a1b2c3d4e5f6", name: "Wohnzimmer", model: "Plug S"),
        status: ShellyDeviceStatusDTO(
            id: "a1b2c3d4e5f6", type: "SNPL-00112EU", code: nil, gen: "G2", online: true,
            status: ShellyDeviceStatus(switch0: ShellySwitchStatus(output: true, apower: 123, voltage: 231.4, current: 0.53))
        )
    )
    .padding()
}

#Preview("Aus") {
    ShellyPlugCard(
        device: ShellyDevice(id: "0011223344aa", name: "Büro", model: "Plug S"),
        status: ShellyDeviceStatusDTO(
            id: "0011223344aa", type: "SNPL-00112EU", code: nil, gen: "G2", online: true,
            status: ShellyDeviceStatus(switch0: ShellySwitchStatus(output: false, apower: 0, voltage: 230.9, current: 0))
        )
    )
    .padding()
}

#Preview("Offline") {
    ShellyPlugCard(
        device: ShellyDevice(id: "ffeeddccbbaa", name: "Garage", model: "Plug S"),
        status: ShellyDeviceStatusDTO(id: "ffeeddccbbaa", type: nil, code: nil, gen: "G2", online: false, status: nil)
    )
    .padding()
}

#Preview("Noch kein Status") {
    ShellyPlugCard(
        device: ShellyDevice(id: "556677889900", name: "Keller", model: nil),
        status: nil
    )
    .padding()
}
