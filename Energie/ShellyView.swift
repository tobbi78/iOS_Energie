//
//  ShellyView.swift
//  Energie
//
//  Created by Tobias Florian on 14.10.26.
//

import SwiftUI

/// "Steckdosen" tab (F12.1, taking F16.2's navigation decision): one `ShellyPlugCard` per saved
/// device, plus a `ShellyPlugsSummaryCard` on top once there's more than one (F12.2) — with just
/// one plug, an overview of "itself" would be redundant. Refreshes on open and via
/// pull-to-refresh only — see `ShellyPlugStatusLoader` for why there's no poll loop yet (F16.1 is
/// still open).
struct ShellyView: View {
    var settings: ShellySettings
    var deviceList: ShellyDeviceList
    @Binding var selectedTab: AppTab

    @State private var loader: ShellyPlugStatusLoader

    init(settings: ShellySettings, deviceList: ShellyDeviceList, selectedTab: Binding<AppTab>) {
        self.settings = settings
        self.deviceList = deviceList
        self._selectedTab = selectedTab
        self._loader = State(initialValue: ShellyPlugStatusLoader(settings: settings, deviceList: deviceList))
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Steckdosen")
        }
        .task {
            await loader.refresh()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch loader.state {
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
        case .error(let message):
            ErrorView(message: message) {
                Task { await loader.refresh() }
            }
        }
    }

    private var plugList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                if deviceList.devices.count >= 2 {
                    ShellyPlugsSummaryCard(summary: ShellyPlugsSummary(devices: deviceList.devices, statuses: loader.statuses))
                        .staggeredAppear(index: 0)
                }
                ForEach(Array(deviceList.devices.enumerated()), id: \.element.id) { index, device in
                    ShellyPlugCard(device: device, status: loader.statuses[device.id])
                        .staggeredAppear(index: index + (deviceList.devices.count >= 2 ? 1 : 0))
                }
                if let lastUpdated = loader.lastUpdated {
                    Text("Aktualisiert um \(lastUpdated.formatted(date: .omitted, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
            }
            .padding()
        }
        .refreshable {
            await loader.refresh()
        }
    }

    private func goToSettings(title: String, description: String) -> some View {
        ContentUnavailableView {
            Label(title, systemImage: "powerplug")
        } description: {
            Text(description)
        } actions: {
            Button("Zu den Einstellungen") {
                selectedTab = .settings
            }
        }
    }
}

// Previews deliberately only cover the `needsCredentials`/`noDevices` states, same as
// `SolarView`/`HeatPumpView` (which have no previews at all for their similarly network-backed
// "ready" states): `.task` eagerly calls `loader.refresh()`, which would hit the real Shelly
// Cloud API from a canvas preview — a non-mocked network round trip isn't something a preview
// should depend on. The "ready" layout itself is covered by `ShellyPlugCard`'s own previews.

#Preview("Zugangsdaten fehlen") {
    ShellyView(
        settings: ShellySettings(store: InMemoryShellySecretStore()),
        deviceList: ShellyDeviceList(userDefaults: UserDefaults(suiteName: UUID().uuidString)!),
        selectedTab: .constant(.shelly)
    )
}

#Preview("Keine Steckdosen gespeichert") {
    ShellyView(
        settings: ShellySettings(store: InMemoryShellySecretStore(seed: [
            .serverURI: "https://shelly-12-eu.shelly.cloud",
            .authKey: "preview-key",
        ])),
        deviceList: ShellyDeviceList(userDefaults: UserDefaults(suiteName: UUID().uuidString)!),
        selectedTab: .constant(.shelly)
    )
}
