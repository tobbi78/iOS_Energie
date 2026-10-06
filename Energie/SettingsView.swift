//
//  SettingsView.swift
//  Energie
//
//  Created by Tobias Florian on 04.10.26.
//

import SwiftUI

/// Central "Einstellungen" tab: a single, consolidated entry point to both sources' settings
/// screens (`PVSettingsScreen`/`HeatPumpSettingsScreen`), replacing the previous per-source
/// "Mehr" menu entries so there's exactly one place to find any setting, reachable from the
/// bottom tab bar next to "Wärmepumpe".
struct SettingsView: View {
    var solarModel: SolarModel
    var displayPreferences: PVDisplayPreferences
    var budgetSettings: EnphaseBudgetSettings
    var heatPumpModel: HeatPumpModel

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        PVSettingsScreen(model: solarModel, displayPreferences: displayPreferences, budgetSettings: budgetSettings)
                    } label: {
                        SettingsRow(title: "PV-Anlage", icon: "sun.max.fill", tint: .pvAccent)
                    }
                    NavigationLink {
                        HeatPumpSettingsScreen(model: heatPumpModel)
                    } label: {
                        SettingsRow(title: "Wärmepumpe", icon: "heater.vertical.fill", tint: .heatPumpAccent)
                    }
                }

                Section {
                    NavigationLink {
                        PrivacyPolicyView()
                    } label: {
                        SettingsRow(title: "Datenschutzerklärung", icon: "hand.raised.fill", tint: .gray)
                    }
                }
            }
            .navigationTitle("Einstellungen")
        }
    }
}

/// Icon-badge row styled after the system Settings app, so each destination reads as its own
/// clearly colored entry even though both now live in one shared list.
private struct SettingsRow: View {
    let title: String
    let icon: String
    let tint: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.subheadline.bold())
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(tint, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .accessibilityHidden(true)
            Text(title)
        }
    }
}
