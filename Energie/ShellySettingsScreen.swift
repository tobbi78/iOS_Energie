//
//  ShellySettingsScreen.swift
//  Energie
//
//  Created by Tobias Florian on 14.10.26.
//

import SwiftUI

/// Credential entry for the Shelly Cloud Control API (F11.1/F11.2) — no OAuth consent flow like
/// Enphase/Viessmann, just two values the user copies from the Shelly app ("User settings →
/// Authorization cloud key"), see SHELLY_API_WERTE.md. Reached via the central "Einstellungen"
/// tab (`SettingsView`), analogous to `PVSettingsScreen`/`HeatPumpSettingsScreen`.
struct ShellySettingsScreen: View {
    var settings: ShellySettings
    var deviceList: ShellyDeviceList

    @State private var serverURI = ""
    @State private var authKey = ""
    @State private var showsInvalidURIError = false
    @State private var showsSavedConfirmation = false
    @State private var showsRemoveConfirmation = false

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Shelly-Zugangsdaten", systemImage: "key.horizontal.fill")
                        .font(.headline)
                        .foregroundStyle(.shellyAccent)
                    Text("In der Shelly-App unter \"Nutzereinstellungen → Autorisierungsschlüssel für die Cloud\".")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            if settings.credentials.isComplete {
                Section("Verbindung") {
                    if let host = URL(string: settings.credentials.serverURI)?.host {
                        LabeledContent("Verbunden mit", value: host)
                    }
                    NavigationLink {
                        ShellyDevicesScreen(settings: settings, deviceList: deviceList)
                    } label: {
                        LabeledContent("Steckdosen", value: "\(deviceList.devices.count)")
                    }
                    Button("Zugangsdaten entfernen", role: .destructive) {
                        showsRemoveConfirmation = true
                    }
                }
            }

            Section {
                TextField("Server-URI", text: $serverURI)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                SecureField("Authorization Key", text: $authKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                if showsInvalidURIError {
                    Label("Server-URI ungültig — bitte unverändert aus der Shelly-App übernehmen.", systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
                Button("Zugangsdaten speichern") {
                    save()
                }
                .disabled(serverURI.isEmpty || authKey.isEmpty)
            } header: {
                Text("Zugangsdaten")
            } footer: {
                Text("Der Schlüssel ändert sich automatisch bei einer Passwortänderung des Shelly-Kontos und muss dann hier neu eingegeben werden. Er bleibt — anders als die Server-URI — nur auf diesem Gerät gespeichert.")
            }
        }
        .navigationTitle("Shelly-Steckdosen")
        .onAppear {
            serverURI = settings.credentials.serverURI
            authKey = settings.credentials.authKey
        }
        .sensoryFeedback(.success, trigger: showsSavedConfirmation)
        .alert("Gespeichert", isPresented: $showsSavedConfirmation) {
            Button("OK") {}
        }
        .confirmationDialog(
            "Zugangsdaten entfernen?",
            isPresented: $showsRemoveConfirmation,
            titleVisibility: .visible
        ) {
            Button("Entfernen", role: .destructive) {
                settings.clearCredentials()
                serverURI = ""
                authKey = ""
            }
        } message: {
            Text("Der gespeicherte Schlüssel wird aus der Keychain gelöscht. Die bereits erfassten Steckdosendaten bleiben erhalten.")
        }
    }

    private func save() {
        let saved = settings.setCredentials(serverURI: serverURI, authKey: authKey)
        showsInvalidURIError = !saved
        if saved {
            serverURI = settings.credentials.serverURI
            showsSavedConfirmation = true
        }
    }
}

#Preview("Leer") {
    NavigationStack {
        ShellySettingsScreen(
            settings: ShellySettings(store: InMemoryShellySecretStore()),
            deviceList: ShellyDeviceList(userDefaults: UserDefaults(suiteName: UUID().uuidString)!)
        )
    }
}

#Preview("Verbunden") {
    NavigationStack {
        ShellySettingsScreen(
            settings: ShellySettings(store: InMemoryShellySecretStore(seed: [
                .serverURI: "https://shelly-12-eu.shelly.cloud",
                .authKey: "preview-key",
            ])),
            deviceList: ShellyDeviceList(userDefaults: UserDefaults(suiteName: UUID().uuidString)!)
        )
    }
}
