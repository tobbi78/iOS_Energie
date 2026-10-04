//
//  EnergieApp.swift
//  Energie
//
//  Created by Tobias Florian on 30.09.26.
//

import SwiftUI
import SwiftData

@main
struct EnergieApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            PVDailySample.self,
            PVYearlySample.self,
            HeatPumpEfficiencySample.self,
        ])
        // Epic 0 (F0.1): syncs across the user's devices via the private CloudKit container —
        // now possible since a paid Apple Developer account is available (see BACKLOG.md,
        // "Nicht umsetzbar ohne kostenpflichtigen Apple Developer Account"). All three model
        // types satisfy CloudKit's constraints (F0.2): every non-optional property has a
        // declaration-site default, no `@Attribute(.unique)`, no relationships.
        //
        // Falls back to local-only storage when no iCloud account is signed in
        // (`ubiquityIdentityToken` is a lightweight, synchronous check — no network/CloudKit
        // round-trip). Without this, SwiftData's CoreData+CloudKit mirroring setup fails hard
        // with `CKAccountStatusNoAccount` and brings down the whole process, not just the sync —
        // observed directly in this environment, which has no iCloud account signed in.
        //
        // Also forced local-only under XCTest, regardless of account status, as defense in
        // depth for this container specifically — the actual crash traced down to a different
        // cause (see SolarModelTests.makeContext's comment): `ModelConfiguration`'s
        // `cloudKitDatabase` defaults to `.automatic`, which auto-discovers and tries to mirror
        // through whatever container is in the app's entitlements *regardless of
        // `isStoredInMemoryOnly`* — so the tests' own, supposedly-local containers were affected
        // too, independently of whether this one ever even gets constructed during a test run.
        let isRunningTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        let cloudKitDatabase: ModelConfiguration.CloudKitDatabase = (!isRunningTests && FileManager.default.ubiquityIdentityToken != nil)
            ? .private(SharedAppGroup.cloudKitContainerIdentifier)
            : .none
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: cloudKitDatabase
        )

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
