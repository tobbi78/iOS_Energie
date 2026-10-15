//
//  ShellyDevicesScreen.swift
//  Energie
//
//  Created by Tobias Florian on 14.10.26.
//

import SwiftUI

/// Manages the Shelly plugs the app knows about (F11.3) — either found via "Geräte automatisch
/// suchen" (`/interface/device/list`, only community-documented, may not work reliably — see
/// `ShellyClient.discoverDevices`) or entered by hand and verified against the Shelly Cloud API
/// (`v2/devices/api/get`). Reached from `ShellySettingsScreen` once credentials are saved.
struct ShellyDevicesScreen: View {
    var settings: ShellySettings
    var deviceList: ShellyDeviceList

    @State private var isDiscovering = false
    @State private var discoveryError: String?
    @State private var discoveredDevices: [ShellyDiscoveredDevice] = []

    @State private var manualDeviceID = ""
    @State private var manualName = ""
    @State private var isVerifying = false
    @State private var manualError: String?
    @State private var showsAddedConfirmation = false

    /// The device currently being renamed (F17.2), if any — drives the rename `.alert` below.
    /// `nil` both before renaming starts and once it's dismissed, so a single optional doubles as
    /// the alert's `isPresented` state via the computed `Binding` in `body`.
    @State private var renamingDevice: ShellyDevice?
    @State private var renameText = ""

    private var client: ShellyClient {
        ShellyClient(credentials: { await settings.credentials })
    }

    var body: some View {
        Form {
            if deviceList.devices.isEmpty {
                Section {
                    ContentUnavailableView(
                        "Noch keine Steckdosen",
                        systemImage: "powerplug",
                        description: Text("Automatisch suchen oder die Geräte-ID unten manuell eingeben.")
                    )
                    .listRowBackground(Color.clear)
                }
            } else {
                Section {
                    ForEach(deviceList.devices) { device in
                        deviceRow(device)
                    }
                    .onDelete { deviceList.remove(atOffsets: $0) }
                    .onMove { deviceList.move(fromOffsets: $0, toOffset: $1) }
                } header: {
                    Text("Gespeicherte Steckdosen")
                } footer: {
                    Text("Tippen zum Umbenennen, „Bearbeiten“ zum Sortieren oder Löschen. Die Reihenfolge gilt auch im Steckdosen-Tab.")
                }
            }

            Section {
                if isDiscovering {
                    HStack {
                        ProgressView()
                        Text("Suche läuft …")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Button("Geräte automatisch suchen") {
                        Task { await discover() }
                    }
                }
                if let discoveryError {
                    Label(discoveryError, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
                ForEach(discoveredDevices) { discovered in
                    discoveredDeviceRow(discovered)
                }
            } header: {
                Text("Automatische Suche")
            } footer: {
                Text("Nutzt einen nur inoffiziell dokumentierten Shelly-Endpunkt — funktioniert möglicherweise nicht zuverlässig. Schlägt die Suche fehl, hilft die manuelle Eingabe unten weiter.")
            }

            Section {
                TextField("Geräte-ID", text: $manualDeviceID)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("Name (optional)", text: $manualName)
                if let manualError {
                    Label(manualError, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
                Button {
                    Task { await verifyAndAddManualDevice() }
                } label: {
                    if isVerifying {
                        ProgressView()
                    } else {
                        Text("Prüfen und hinzufügen")
                    }
                }
                .disabled(manualDeviceID.isEmpty || isVerifying)
            } header: {
                Text("Manuell hinzufügen")
            } footer: {
                Text("Die Geräte-ID findest du in der Shelly-App unter \"Gerät → Einstellungen → Geräteinformationen\".")
            }
        }
        .navigationTitle("Steckdosen")
        .toolbar {
            if !deviceList.devices.isEmpty {
                EditButton()
            }
        }
        .sensoryFeedback(.success, trigger: showsAddedConfirmation)
        .alert(
            "Steckdose umbenennen",
            isPresented: Binding(
                get: { renamingDevice != nil },
                set: { if !$0 { renamingDevice = nil } }
            )
        ) {
            TextField("Name", text: $renameText)
            Button("Abbrechen", role: .cancel) {}
            Button("Sichern") {
                if let renamingDevice {
                    deviceList.rename(id: renamingDevice.id, to: renameText)
                }
            }
        } message: {
            if let renamingDevice {
                Text(renamingDevice.id)
            }
        }
    }

    @ViewBuilder
    private func deviceRow(_ device: ShellyDevice) -> some View {
        Button {
            beginRenaming(device)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(device.name)
                        .foregroundStyle(.primary)
                    Text(device.id)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "pencil")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .leading) {
            Button {
                beginRenaming(device)
            } label: {
                Label("Umbenennen", systemImage: "pencil")
            }
            .tint(.shellyAccent)
        }
    }

    private func beginRenaming(_ device: ShellyDevice) {
        renamingDevice = device
        renameText = device.name
    }

    @ViewBuilder
    private func discoveredDeviceRow(_ discovered: ShellyDiscoveredDevice) -> some View {
        let alreadyAdded = deviceList.devices.contains { $0.id == discovered.id }
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(discovered.name ?? discovered.id)
                Text(discovered.id)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if alreadyAdded {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Bereits hinzugefügt")
            } else {
                Button("Hinzufügen") {
                    add(id: discovered.id, name: discovered.name ?? discovered.id, model: discovered.type)
                }
            }
        }
    }

    private func discover() async {
        isDiscovering = true
        discoveryError = nil
        defer { isDiscovering = false }
        do {
            discoveredDevices = try await client.discoverDevices()
            if discoveredDevices.isEmpty {
                discoveryError = "Keine Geräte gefunden."
            }
        } catch {
            discoveredDevices = []
            discoveryError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func verifyAndAddManualDevice() async {
        guard let normalizedID = ShellyDeviceList.normalizedDeviceID(manualDeviceID) else {
            manualError = "Geräte-ID ungültig — bitte unverändert aus der Shelly-App übernehmen."
            return
        }
        isVerifying = true
        manualError = nil
        defer { isVerifying = false }
        do {
            let status = try await client.verifyDevice(id: normalizedID)
            let trimmedName = manualName.trimmingCharacters(in: .whitespacesAndNewlines)
            add(id: status.id, name: trimmedName.isEmpty ? (status.type ?? status.id) : trimmedName, model: status.type)
            manualDeviceID = ""
            manualName = ""
        } catch {
            manualError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func add(id: String, name: String, model: String?) {
        guard deviceList.add(ShellyDevice(id: id, name: name, model: model)) else { return }
        discoveredDevices.removeAll { $0.id == id }
        showsAddedConfirmation.toggle()
    }
}

#Preview("Leer") {
    NavigationStack {
        ShellyDevicesScreen(
            settings: ShellySettings(store: InMemoryShellySecretStore(seed: [
                .serverURI: "https://shelly-12-eu.shelly.cloud",
                .authKey: "preview-key",
            ])),
            deviceList: ShellyDeviceList(userDefaults: UserDefaults(suiteName: UUID().uuidString)!)
        )
    }
}

#Preview("Mit Steckdosen") {
    let deviceList = ShellyDeviceList(userDefaults: UserDefaults(suiteName: UUID().uuidString)!)
    deviceList.add(ShellyDevice(id: "a1b2c3d4e5f6", name: "Wohnzimmer", model: "Plug S"))
    deviceList.add(ShellyDevice(id: "0011223344aa", name: "Büro", model: "Plug S"))
    return NavigationStack {
        ShellyDevicesScreen(
            settings: ShellySettings(store: InMemoryShellySecretStore(seed: [
                .serverURI: "https://shelly-12-eu.shelly.cloud",
                .authKey: "preview-key",
            ])),
            deviceList: deviceList
        )
    }
}
