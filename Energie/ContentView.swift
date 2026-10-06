//
//  ContentView.swift
//  Energie
//
//  Created by Tobias Florian on 30.09.26.
//

import SwiftData
import SwiftUI

/// Identifies the three top-level sections so `HomeView` can jump straight into a tab (HP-5).
enum AppTab: Hashable {
    case home, pv, heatPump, settings
}

/// App root. A `TabView` so PV and the heat pump stay independent sections, with a combined
/// "Start" tab in front — see BACKLOG.md ("Zukünftige zweite Energiequelle: Wärmepumpe") and
/// Plans/Waermepumpe-Integration.md (Abschnitt 4).
struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var enphaseSettings = EnphaseSettings()
    @State private var displayPreferences = PVDisplayPreferences()
    @State private var budgetSettings = EnphaseBudgetSettings()
    @State private var solarModel: SolarModel?
    @State private var viessmannSettings = ViessmannSettings()
    @State private var pressureAlertSettings = HeatPumpPressureAlertSettings()
    @State private var heatPumpModel: HeatPumpModel?
    @State private var selectedTab: AppTab = .home
    @State private var watchSyncService = WatchSyncService()
    /// Drives the `LaunchView` overlay (F10.1) — see the `.task` below for the dismiss timing.
    @State private var showsLaunchScreen = true

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Start", systemImage: "house.fill", value: .home) {
                HomeView(solarModel: solarModel, heatPumpModel: heatPumpModel, selectedTab: $selectedTab)
            }
            Tab("PV-Anlage", systemImage: "sun.max.fill", value: .pv) {
                if let solarModel {
                    SolarView(model: solarModel, displayPreferences: displayPreferences)
                } else {
                    ProgressView()
                }
            }
            Tab("Wärmepumpe", systemImage: "heater.vertical.fill", value: .heatPump) {
                if let heatPumpModel {
                    HeatPumpView(model: heatPumpModel)
                } else {
                    ProgressView()
                }
            }
            Tab("Einstellungen", systemImage: "gearshape.fill", value: .settings) {
                if let solarModel, let heatPumpModel {
                    SettingsView(
                        solarModel: solarModel,
                        displayPreferences: displayPreferences,
                        budgetSettings: budgetSettings,
                        heatPumpModel: heatPumpModel
                    )
                } else {
                    ProgressView()
                }
            }
        }
        .task {
            guard solarModel == nil else { return }
            let model = SolarModel(
                settings: enphaseSettings,
                modelContext: modelContext,
                budgetSettings: budgetSettings,
                budget: EnphaseRequestBudget(userDefaults: SharedAppGroup.userDefaults),
                watchSyncService: watchSyncService
            )
            solarModel = model
            // Started here, not in SolarView's own .task, so the PV data loads even if the user
            // lands on the "Start" tab first and never visits "PV-Anlage" directly.
            await model.start()
        }
        .task {
            guard heatPumpModel == nil else { return }
            let model = HeatPumpModel(
                settings: viessmannSettings,
                modelContext: modelContext,
                pressureAlertSettings: pressureAlertSettings,
                watchSyncService: watchSyncService
            )
            heatPumpModel = model
            await model.start()
        }
        .overlay {
            if showsLaunchScreen {
                LaunchView()
                    .transition(.opacity.combined(with: .scale(scale: 1.05)))
            }
        }
        .task {
            // Mindestdauer gegen Flackern bei schnellem Start/Cache-Hit, dann warten, bis
            // mindestens eine der beiden Quellen ihren ersten State-Übergang hinter sich hat
            // (nicht mehr `.loading`) — Quellen ohne gespeicherte Zugangsdaten sind das sofort.
            // Obergrenze, damit eine hängende Netzwerkanfrage den Start nie blockiert; die Tabs
            // zeigen in dem Fall weiterhin ihre eigenen Ladezustände.
            let minimumDuration: Duration = .milliseconds(1200)
            let maximumDuration: Duration = .milliseconds(3000)
            let pollInterval: Duration = .milliseconds(100)
            let start = ContinuousClock.now

            try? await Task.sleep(for: minimumDuration)
            while ContinuousClock.now - start < maximumDuration {
                let solarDone = solarModel.map { $0.state != .loading } ?? false
                let heatPumpDone = heatPumpModel.map { $0.state != .loading } ?? false
                if solarDone || heatPumpDone { break }
                try? await Task.sleep(for: pollInterval)
            }

            withAnimation(.easeInOut(duration: 0.45)) {
                showsLaunchScreen = false
            }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [PVDailySample.self, PVYearlySample.self, HeatPumpEfficiencySample.self], inMemory: true)
}
