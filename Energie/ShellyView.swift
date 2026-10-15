//
//  ShellyView.swift
//  Energie
//
//  Created by Tobias Florian on 14.10.26.
//

import SwiftData
import SwiftUI

/// "Steckdosen" tab (F12.1, taking F16.2's navigation decision): one `ShellyPlugCard` per saved
/// device, plus a `ShellyPlugsSummaryCard` on top once there's more than one (F12.2) — with just
/// one plug, an overview of "itself" would be redundant. `ShellyModel` (F16.1) now owns a
/// recurring poll loop independent of this tab being open; the `.task` below additionally
/// refreshes immediately whenever the tab is opened, same as pull-to-refresh.
struct ShellyView: View {
    var model: ShellyModel
    var deviceList: ShellyDeviceList
    @Binding var selectedTab: AppTab

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Steckdosen")
                .toolbar {
                    if model.state == .ready {
                        ToolbarItem(placement: .primaryAction) {
                            NavigationLink {
                                ShellyHistoryScreen(devices: deviceList.devices)
                            } label: {
                                Label("Verlauf", systemImage: "chart.bar.xaxis")
                            }
                        }
                    }
                }
        }
        .task {
            await model.refresh()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .needsCredentials:
            goToSettings(
                title: "Keine Shelly-Zugangsdaten",
                description: "Hinterlege zuerst Server-URI und Schlüssel in den Einstellungen."
            )
        case .noDevices:
            goToSettings(
                title: "Noch keine Steckdosen",
                description: "Füge Steckdosen in den Einstellungen hinzu."
            )
        case .loading:
            ProgressView("Lade Steckdosen…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .ready:
            plugList
        case .authFailed:
            goToSettings(
                title: "Shelly-Schlüssel ungültig",
                description: "Der hinterlegte Schlüssel wurde abgelehnt — vermutlich wurde das Passwort des Shelly-Kontos geändert. Bitte den neuen Schlüssel in den Einstellungen hinterlegen.",
                systemImage: "exclamationmark.triangle.fill",
                retry: { Task { await model.refresh(force: true) } }
            )
        case .error(let message):
            ErrorView(message: message) {
                Task { await model.refresh() }
            }
        }
    }

    private var plugList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                if deviceList.devices.count >= 2 {
                    ShellyPlugsSummaryCard(summary: ShellyPlugsSummary(
                        devices: deviceList.devices,
                        statuses: model.statuses
                    ))
                        .staggeredAppear(index: 0)
                }
                ForEach(Array(deviceList.devices.enumerated()), id: \.element.id) { index, device in
                    ShellyPlugCard(device: device, status: model.statuses[device.id]) { on in
                        try await model.setSwitch(deviceID: device.id, on: on)
                    }
                    .staggeredAppear(index: index + (deviceList.devices.count >= 2 ? 1 : 0))
                }
                if let lastUpdated = model.lastUpdated {
                    Text("Aktualisiert um \(lastUpdated.formatted(date: .omitted, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
            }
            .padding()
        }
        .refreshable {
            await model.refresh()
        }
    }

    private func goToSettings(
        title: String,
        description: String,
        systemImage: String = "powerplug",
        retry: (() -> Void)? = nil
    ) -> some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            Text(description)
        } actions: {
            if let retry {
                Button("Zu den Einstellungen") {
                    selectedTab = .settings
                }
                .buttonStyle(.borderedProminent)
                Button("Erneut versuchen", action: retry)
                    .buttonStyle(.bordered)
            } else {
                Button("Zu den Einstellungen") {
                    selectedTab = .settings
                }
            }
        }
    }
}

// MARK: - History submenu

/// Dedicated screen for the plug history charts (F14.3), reached via the toolbar like
/// `SolarView`'s `PVHistoryScreen` — the main tab stays focused on live values and switching.
private struct ShellyHistoryScreen: View {
    let devices: [ShellyDevice]

    @Query(sort: \ShellyDailySample.date) private var samples: [ShellyDailySample]

    var body: some View {
        ScrollView {
            ShellyHistoryChartsView(samples: samples, devices: devices)
        }
        .navigationTitle("Verlauf")
    }
}

// Previews deliberately only cover the `needsCredentials`/`noDevices` states, same as
// `SolarView`/`HeatPumpView` (which have no previews at all for their similarly network-backed
// "ready" states): `.task` eagerly calls `model.refresh()`, which would hit the real Shelly
// Cloud API from a canvas preview — a non-mocked network round trip isn't something a preview
// should depend on. The "ready" layout itself is covered by `ShellyPlugCard`'s own previews.

#Preview("Zugangsdaten fehlen") {
    let deviceList = ShellyDeviceList(userDefaults: UserDefaults(suiteName: UUID().uuidString)!)
    ShellyView(
        model: ShellyModel(
            settings: ShellySettings(store: InMemoryShellySecretStore()),
            deviceList: deviceList
        ),
        deviceList: deviceList,
        selectedTab: .constant(.shelly)
    )
}

#Preview("Keine Steckdosen gespeichert") {
    let deviceList = ShellyDeviceList(userDefaults: UserDefaults(suiteName: UUID().uuidString)!)
    ShellyView(
        model: ShellyModel(
            settings: ShellySettings(store: InMemoryShellySecretStore(seed: [
                .serverURI: "https://shelly-12-eu.shelly.cloud",
                .authKey: "preview-key",
            ])),
            deviceList: deviceList
        ),
        deviceList: deviceList,
        selectedTab: .constant(.shelly)
    )
}
