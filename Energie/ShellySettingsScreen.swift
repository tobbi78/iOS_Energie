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
    @State private var isAuthKeyRevealed = false
    @State private var showsInvalidURIError = false
    @State private var showsSavedConfirmation = false
    @State private var showsSignOutConfirmation = false
    @State private var isTestingConnection = false
    @State private var connectionTestOutcome: ConnectionTestOutcome?

    private var client: ShellyClient {
        ShellyClient(credentials: { await settings.credentials })
    }

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
                    if isTestingConnection {
                        HStack {
                            ProgressView()
                            Text("Verbindung wird getestet …")
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Button("Verbindung testen") {
                            Task { await testConnection() }
                        }
                        .disabled(deviceList.devices.isEmpty)
                    }
                    if deviceList.devices.isEmpty {
                        Text("Zum Testen zuerst eine Steckdose hinzufügen.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else if let connectionTestOutcome {
                        connectionTestResultLabel(connectionTestOutcome)
                    }
                    Button("Abmelden", role: .destructive) {
                        showsSignOutConfirmation = true
                    }
                }
            }

            Section {
                TextField("Server-URI", text: $serverURI)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                HStack {
                    Group {
                        if isAuthKeyRevealed {
                            TextField("Authorization Key", text: $authKey)
                        } else {
                            SecureField("Authorization Key", text: $authKey)
                        }
                    }
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    Button {
                        isAuthKeyRevealed.toggle()
                    } label: {
                        Image(systemName: isAuthKeyRevealed ? "eye.slash" : "eye")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(isAuthKeyRevealed ? "Schlüssel verbergen" : "Schlüssel anzeigen")
                }
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
            "Abmelden?",
            isPresented: $showsSignOutConfirmation,
            titleVisibility: .visible
        ) {
            Button("Abmelden", role: .destructive) {
                settings.signOut()
                authKey = ""
                isAuthKeyRevealed = false
                connectionTestOutcome = nil
            }
        } message: {
            Text("Der Schlüssel wird von diesem Gerät gelöscht. Server-URI und Steckdosenliste bleiben erhalten.")
        }
    }

    private func save() {
        let saved = settings.setCredentials(serverURI: serverURI, authKey: authKey)
        showsInvalidURIError = !saved
        if saved {
            serverURI = settings.credentials.serverURI
            showsSavedConfirmation = true
            connectionTestOutcome = nil
        }
    }

    private func testConnection() async {
        isTestingConnection = true
        defer { isTestingConnection = false }
        do {
            let result = try await client.testConnection(deviceIDs: deviceList.devices.map(\.id))
            connectionTestOutcome = .success(online: result.online, total: result.total)
        } catch ShellyClientError.unauthorized {
            connectionTestOutcome = .unauthorized
        } catch {
            connectionTestOutcome = .failure((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }

    @ViewBuilder
    private func connectionTestResultLabel(_ outcome: ConnectionTestOutcome) -> some View {
        switch outcome {
        case .success(let online, let total):
            Label("Verbindung OK – \(online) von \(total) Steckdosen online", systemImage: "checkmark.circle.fill")
                .font(.footnote)
                .foregroundStyle(.green)
        case .unauthorized:
            Label("Schlüssel abgelehnt – bitte neu eingeben.", systemImage: "exclamationmark.triangle.fill")
                .font(.footnote)
                .foregroundStyle(.red)
        case .failure(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.footnote)
                .foregroundStyle(.red)
        }
    }

    /// Result of a "Verbindung testen" tap (F17.1) — `.unauthorized` is split out from the
    /// generic `.failure` case so the result label can point directly at a dead key rather than
    /// showing `ShellyClientError.unauthorized`'s generic wording twice (it already explains
    /// itself fully, but the dedicated case keeps this screen in control of its own phrasing).
    private enum ConnectionTestOutcome: Equatable {
        case success(online: Int, total: Int)
        case unauthorized
        case failure(String)
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
