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
        let cloudKitDatabase: ModelConfiguration.CloudKitDatabase = FileManager.default.ubiquityIdentityToken != nil
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
