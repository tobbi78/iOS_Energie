//
//  PrivacyPolicyView.swift
//  Energie
//
//  Created by Tobias Florian on 06.10.26.
//

import SwiftUI

/// In-app copy of `docs/privacy.html`, reached from the central "Einstellungen" tab so the
/// privacy policy is readable without leaving the app rather than only linked from App Store
/// Connect. Keep this in sync with `docs/privacy.html` if either changes.
struct PrivacyPolicyView: View {
    var body: some View {
        Form {
            Section {
                Text("„Energie“ ist eine private App, die ausschließlich im Rahmen eines nicht-öffentlichen TestFlight-Tests mit einem begrenzten Personenkreis (Familie/Freunde) verwendet wird. Sie wird nicht im öffentlichen App Store angeboten.")
            } footer: {
                Text("Stand: Oktober 2026")
            }

            Section("Verantwortlicher") {
                LabeledContent("Kontakt") {
                    Link("hula.proxy-3c@icloud.com", destination: URL(string: "mailto:hula.proxy-3c@icloud.com")!)
                }
            }

            Section("Zweck der App") {
                Text("Die App zeigt Photovoltaik-Daten (über die Enphase-API) und Wärmepumpen-Daten (über die Viessmann-API) an, die ausschließlich aus dem eigenen Nutzerkonto der jeweiligen Person stammen, die die App installiert hat.")
            }

            Section("Welche Daten verarbeitet werden") {
                PrivacyBullet(
                    title: "Zugangsdaten (OAuth-Tokens)",
                    text: "Beim Verbinden mit Enphase bzw. Viessmann werden Zugriffs- und Erneuerungs-Tokens im verschlüsselten iOS-Schlüsselbund (Keychain) des jeweiligen Geräts gespeichert. Diese Tokens verlassen das Gerät nicht über iCloud und werden nicht an den Entwickler übertragen."
                )
                PrivacyBullet(
                    title: "Energie-Messdaten",
                    text: "PV-Erzeugungsdaten und Wärmepumpen-Effizienzdaten werden über den privaten iCloud-Account der nutzenden Person zwischen deren eigenen Geräten (iPhone, Apple Watch, Widgets) synchronisiert. Diese Daten sind ausschließlich im privaten iCloud-Bereich der jeweiligen Person gespeichert und für niemand anderen einsehbar – auch nicht für den Entwickler."
                )
                PrivacyBullet(
                    title: "Benachrichtigungen",
                    text: "Lokale Hinweise (z. B. Druckalarme der Wärmepumpe) werden ausschließlich auf dem Gerät selbst erzeugt; dafür werden keine Daten übertragen."
                )
            }

            Section {
                Text("Daten werden ausschließlich mit den Diensten ausgetauscht, mit denen sich die nutzende Person aktiv und freiwillig über deren eigenen Zugang verbindet:")
                Label("Enphase Energy (PV-Anlagendaten)", systemImage: "sun.max.fill")
                    .foregroundStyle(.pvAccent)
                Label("Viessmann Climate Solutions (Wärmepumpendaten)", systemImage: "heater.vertical.fill")
                    .foregroundStyle(.heatPumpAccent)
            } header: {
                Text("Weitergabe an Dritte")
            } footer: {
                Text("Für die Datenverarbeitung durch diese Anbieter gelten deren eigene Datenschutzbestimmungen. Der Entwickler der App hat keinen Zugriff auf diese Konten oder Daten. Es findet keine Weitergabe von Daten zu Werbezwecken statt. Die App enthält kein Tracking, keine Analyse-Software von Drittanbietern und keine Werbung.")
            }

            Section("Speicherdauer") {
                Text("Daten verbleiben, solange die App installiert ist bzw. bis die nutzende Person die Verbindung zu Enphase/Viessmann trennt oder die App deinstalliert. Beim Deinstallieren werden lokal gespeicherte Zugangsdaten (Keychain) automatisch entfernt.")
            }

            Section {
                Text("Jede nutzende Person kann jederzeit Auskunft über die eigenen gespeicherten Daten verlangen oder deren Löschung veranlassen – zum Beispiel durch Trennen der Konto-Verbindung in den App-Einstellungen (löscht dabei auch die lokal und in iCloud gespeicherte Verlaufshistorie) oder durch Deinstallation der App. Bei Fragen genügt eine Nachricht an die oben genannte Kontaktadresse.")
            } header: {
                Text("Rechte der betroffenen Person")
            } footer: {
                Text("Energie App – privater TestFlight-Test, kein öffentliches Produkt.")
            }
        }
        .navigationTitle("Datenschutzerklärung")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct PrivacyBullet: View {
    let title: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .fontWeight(.semibold)
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    NavigationStack {
        PrivacyPolicyView()
    }
}
