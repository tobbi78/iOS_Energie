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
    /// F13.1 — switches the plug to the given state and reloads its status. Thrown errors
    /// surface via `toggleError` below rather than bubbling further; a `MainActor`-isolated
    /// `ShellyModel` method, same shape as `ShellyModel.setSwitch`.
    var onToggle: (Bool) async throws -> Void

    /// Set while the confirmation dialog for a tap on the status badge is up; the dialog's
    /// buttons read this to know which direction to confirm.
    @State private var pendingTarget: Bool?
    @State private var isToggling = false
    @State private var toggleError: String?

    /// Derives online/switch-state/formatting from `status` — kept as a single computed
    /// property rather than repeating `ShellyPlugDisplay(status: status)` at every use site
    /// (F18.1).
    private var display: ShellyPlugDisplay {
        ShellyPlugDisplay(status: status)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            HStack(spacing: 0) {
                metric(title: "Leistung", value: display.formattedPower, icon: "bolt.fill")
                Divider().frame(height: 36)
                metric(title: "Spannung", value: display.formattedVoltage, icon: "waveform.path")
                Divider().frame(height: 36)
                metric(title: "Strom", value: display.formattedCurrent, icon: "gauge")
            }
        }
        .padding()
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
        .accessibilityHint(accessibilityHint)
        // `.accessibilityElement(children: .ignore)` hides the nested `Button` in `statusBadge`
        // from VoiceOver along with everything else — without this action, double-tapping the
        // card wouldn't do anything for a VoiceOver user even though sighted users can tap the
        // badge directly (F13.1/F13.2).
        .accessibilityAction {
            guard display.canToggle, let output = display.output, !isToggling else { return }
            pendingTarget = !output
        }
        .confirmationDialog(
            confirmationTitle,
            isPresented: Binding(
                get: { pendingTarget != nil },
                set: { if !$0 { pendingTarget = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let pendingTarget {
                Button(pendingTarget ? "Einschalten" : "Ausschalten") {
                    toggle(to: pendingTarget)
                }
            }
        }
        .alert(
            "Schalten fehlgeschlagen",
            isPresented: Binding(
                get: { toggleError != nil },
                set: { if !$0 { toggleError = nil } }
            )
        ) {
            Button("OK") {}
        } message: {
            Text(toggleError ?? "")
        }
    }

    /// `String(localized:)` rather than a plain interpolated literal — this property's type
    /// (`String`, required by `confirmationDialog`'s `isPresented:` overload) would otherwise
    /// resolve to the non-localizing `StringProtocol` overload and leave `device.name`'s
    /// surrounding "einschalten?"/"ausschalten?" text untranslated in the English build.
    private var confirmationTitle: String {
        guard let pendingTarget else { return "" }
        return pendingTarget
            ? String(localized: "\(device.name) einschalten?")
            : String(localized: "\(device.name) ausschalten?")
    }

    /// F13.2 — runs after the confirmation dialog's button is tapped, not before, so a dismissed
    /// dialog (tap outside, swipe down) never sends a command.
    private func toggle(to target: Bool) {
        pendingTarget = nil
        isToggling = true
        Task {
            defer { isToggling = false }
            do {
                try await onToggle(target)
            } catch {
                toggleError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
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

    /// Online with a known switch state doubles as the schalten button (F13.1) — the badge
    /// itself becomes tappable rather than adding a separate control next to it (Nutzerentscheidung
    /// 2026-10-15), opening the confirmation dialog (F13.2) for whichever direction is the
    /// opposite of the current state. Offline or unknown state stays non-interactive, same as
    /// before — there's nothing sensible to switch to without knowing the current state, and an
    /// offline device would just fail with `DEVICE_OFFLINE` immediately anyway.
    @ViewBuilder
    private var statusBadge: some View {
        if isToggling {
            ProgressView()
                .controlSize(.small)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
        } else if !display.isOnline {
            badge(text: "Offline", color: .secondary)
        } else if let output = display.output {
            Button {
                pendingTarget = !output
            } label: {
                badge(text: output ? "An" : "Aus", color: output ? .green : .secondary)
            }
            .buttonStyle(.plain)
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
        if !display.isOnline {
            parts.append("Offline")
        } else if let output = display.output {
            parts.append(output ? "Eingeschaltet" : "Ausgeschaltet")
        }
        parts.append("Leistung \(display.formattedPower)")
        parts.append("Spannung \(display.formattedVoltage)")
        parts.append("Strom \(display.formattedCurrent)")
        return parts.joined(separator: ", ")
    }

    /// Empty when there's nothing to switch to (offline/unknown state/already toggling) — an
    /// empty hint is simply not announced by VoiceOver, same as not setting one at all.
    /// `String(localized:)` for the same reason as `confirmationTitle` above.
    private var accessibilityHint: String {
        guard display.canToggle, !isToggling else { return "" }
        return String(localized: "Doppeltippen zum Schalten")
    }

}

#Preview("An") {
    ShellyPlugCard(
        device: ShellyDevice(id: "a1b2c3d4e5f6", name: "Wohnzimmer", model: "Plug S"),
        status: ShellyDeviceStatusDTO(
            id: "a1b2c3d4e5f6", type: "SNPL-00112EU", code: nil, gen: "G2", online: true,
            status: ShellyDeviceStatus(switch0: ShellySwitchStatus(output: true, apower: 123, voltage: 231.4, current: 0.53))
        ),
        onToggle: { _ in }
    )
    .padding()
}

#Preview("Aus") {
    ShellyPlugCard(
        device: ShellyDevice(id: "0011223344aa", name: "Büro", model: "Plug S"),
        status: ShellyDeviceStatusDTO(
            id: "0011223344aa", type: "SNPL-00112EU", code: nil, gen: "G2", online: true,
            status: ShellyDeviceStatus(switch0: ShellySwitchStatus(output: false, apower: 0, voltage: 230.9, current: 0))
        ),
        onToggle: { _ in }
    )
    .padding()
}

#Preview("Offline") {
    ShellyPlugCard(
        device: ShellyDevice(id: "ffeeddccbbaa", name: "Garage", model: "Plug S"),
        status: ShellyDeviceStatusDTO(id: "ffeeddccbbaa", type: nil, code: nil, gen: "G2", online: false, status: nil),
        onToggle: { _ in }
    )
    .padding()
}

#Preview("Noch kein Status") {
    ShellyPlugCard(
        device: ShellyDevice(id: "556677889900", name: "Keller", model: nil),
        status: nil,
        onToggle: { _ in }
    )
    .padding()
}
