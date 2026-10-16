//
//  ContentView.swift
//  Energie
//
//  Created by Tobias Florian on 30.09.26.
//

import SwiftData
import SwiftUI

/// Identifies the top-level sections so `HomeView`/`ShellyView` can jump straight into a tab
/// (HP-5, F12.1).
enum AppTab: Hashable {
    case home, pv, heatPump, shelly, settings
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
    @State private var shellySettings = ShellySettings()
    @State private var shellyDeviceList = ShellyDeviceList()
    @State private var shellyModel: ShellyModel?
    @State private var heatPumpModel: HeatPumpModel?
    @State private var selectedTab: AppTab = .home
    @State private var watchSyncService = WatchSyncService()
    /// Drives the `LaunchView` overlay (F10.1) — see the `.task` below for the dismiss timing.
    @State private var showsLaunchScreen = true
    /// Echoes already-delivered local notifications (F5.5) back as a tab-icon bounce (F10.8) —
    /// see the `.task`/`.onChange(of: scenePhase)` below for when it's refreshed.
    @State private var notificationEcho = NotificationEcho()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Start", systemImage: "house.fill", value: .home) {
                HomeView(solarModel: solarModel, heatPumpModel: heatPumpModel, shellyModel: shellyModel, shellyDeviceList: shellyDeviceList, selectedTab: $selectedTab)
            }
            Tab(value: .pv) {
                if let solarModel {
                    SolarView(model: solarModel, displayPreferences: displayPreferences, budgetSettings: budgetSettings)
                } else {
                    ProgressView()
                }
            } label: {
                // F10.8: bounces once per newly-observed PV notification (Anlagenausfall/Budget/
                // Speicherstand, F5.5), echoing it back inside the app.
                Label("PV-Anlage", systemImage: "sun.max.fill")
                    .symbolEffect(.bounce, value: notificationEcho.pvTrigger)
            }
            Tab(value: .heatPump) {
                if let heatPumpModel {
                    HeatPumpView(model: heatPumpModel)
                } else {
                    ProgressView()
                }
            } label: {
                // F10.8: same as the PV tab, for the heat pump's pressure alert (F5.5).
                Label("Wärmepumpe", systemImage: "heater.vertical.fill")
                    .symbolEffect(.bounce, value: notificationEcho.heatPumpTrigger)
            }
            Tab(value: .shelly) {
                if let shellyModel {
                    ShellyView(model: shellyModel, deviceList: shellyDeviceList, selectedTab: $selectedTab)
                } else {
                    ProgressView()
                }
            } label: {
                Label("Steckdosen", systemImage: "powerplug.fill")
            }
            Tab("Einstellungen", systemImage: "gearshape.fill", value: .settings) {
                if let solarModel, let heatPumpModel {
                    SettingsView(
                        solarModel: solarModel,
                        displayPreferences: displayPreferences,
                        budgetSettings: budgetSettings,
                        heatPumpModel: heatPumpModel,
                        shellySettings: shellySettings,
                        shellyDeviceList: shellyDeviceList
                    )
                } else {
                    ProgressView()
                }
            }
        }
        // Lets the staggered KPI cards (F10.3) hold back until the launch overlay is gone.
        .environment(\.isLaunchScreenVisible, showsLaunchScreen)
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
        .task {
            guard shellyModel == nil else { return }
            let model = ShellyModel(settings: shellySettings, deviceList: shellyDeviceList, modelContext: modelContext)
            shellyModel = model
            model.start()
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
            // Cold launch: scenePhase is already `.active` by the time the overlay goes away, so
            // the `onChange` below never fires for this transition — refresh explicitly instead.
            await notificationEcho.refresh()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background {
                // Leaving the foreground: nudge the Shelly widgets (F16.3) to pick up whatever
                // ShellyModel's poll loop (foreground-only) last saw, rather than waiting for
                // their own next 15-minute tick to notice a change made earlier in this session.
                WidgetReload.shellyWidgetsChanged()
                return
            }
            // Reopening the app from the background: skip while the launch overlay is still up
            // (F10.3's reasoning) and let the `.task` above handle the cold-launch case.
            guard newPhase == .active, !showsLaunchScreen else { return }
            Task { await notificationEcho.refresh() }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [PVDailySample.self, PVYearlySample.self, HeatPumpEfficiencySample.self], inMemory: true)
}
