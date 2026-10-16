//
//  EnergieApp.swift
//  Energie
//
//  Created by Tobias Florian on 30.09.26.
//

import SwiftUI
import SwiftData
import CoreData
import CloudKit

@main
struct EnergieApp: App {
    var sharedModelContainer: ModelContainer = {
        // F8.1: versioned schema + migration plan instead of a flat `Schema([...])`, so future
        // model changes migrate the store instead of breaking it (see `EnergieMigrationPlan` for
        // the checklist, incl. CloudKit's additive-only constraint).
        let schema = EnergieMigrationPlan.currentSchema
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
        let isCloudKitEnabled = !isRunningTests && FileManager.default.ubiquityIdentityToken != nil
        let cloudKitDatabase: ModelConfiguration.CloudKitDatabase = isCloudKitEnabled
            ? .private(SharedAppGroup.cloudKitContainerIdentifier)
            : .none
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: cloudKitDatabase
        )

#if DEBUG
        // One-off push of the CloudKit *Development* schema. CloudKit normally infers its schema
        // from records that actually get mirrored, so a freshly added entity (e.g.
        // `ShellyDailySample`, F14.1) only shows up in the CloudKit Console once something syncs
        // it — slow and easy to miss entirely if no device happens to write one. This uploads
        // throwaway representative records for every entity instead, so the Development schema
        // is complete right after a single debug run. Gated behind an env var (set once in the
        // scheme's Run arguments, then removed again) so it doesn't add CloudKit overhead to
        // every normal debug launch — see EnergieSchema.swift's migration checklist. Must never
        // run against Production; `#if DEBUG` plus the opt-in env var both guard against that.
        print("[CloudKitSchemaInit] isCloudKitEnabled=\(isCloudKitEnabled) envFlag=\(ProcessInfo.processInfo.environment["INITIALIZE_CLOUDKIT_SCHEMA"] ?? "<unset>")")
        // `ubiquityIdentityToken` above only answers yes/no; `CKContainer.accountStatus` gives the
        // actual reason (noAccount/restricted/couldNotDetermine + underlying error) when it's no.
        CKContainer(identifier: SharedAppGroup.cloudKitContainerIdentifier).accountStatus { status, error in
            print("[CloudKitSchemaInit] CKContainer.accountStatus=\(status) error=\(String(describing: error))")
        }
        if isCloudKitEnabled,
            ProcessInfo.processInfo.environment["INITIALIZE_CLOUDKIT_SCHEMA"] == "1" {
            do {
                try autoreleasepool {
                    let storeDescription = NSPersistentStoreDescription(url: modelConfiguration.url)
                    storeDescription.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(
                        containerIdentifier: SharedAppGroup.cloudKitContainerIdentifier
                    )
                    storeDescription.shouldAddStoreAsynchronously = false
                    guard let managedObjectModel = NSManagedObjectModel.makeManagedObjectModel(for: EnergieSchemaV3.models) else {
                        fatalError("Could not derive a managed object model for the CloudKit schema push")
                    }
                    let schemaInitContainer = NSPersistentCloudKitContainer(name: "Energie", managedObjectModel: managedObjectModel)
                    schemaInitContainer.persistentStoreDescriptions = [storeDescription]
                    schemaInitContainer.loadPersistentStores { _, error in
                        if let error {
                            fatalError("Could not load store for CloudKit schema push: \(error)")
                        }
                    }
                    print("[CloudKitSchemaInit] store loaded, calling initializeCloudKitSchema()…")
                    try schemaInitContainer.initializeCloudKitSchema()
                    print("[CloudKitSchemaInit] initializeCloudKitSchema() finished without throwing")
                    if let store = schemaInitContainer.persistentStoreCoordinator.persistentStores.first {
                        try schemaInitContainer.persistentStoreCoordinator.remove(store)
                    }
                }
            } catch {
                fatalError("CloudKit schema initialization failed: \(error)")
            }
        }
#endif

        do {
            return try ModelContainer(
                for: schema,
                migrationPlan: EnergieMigrationPlan.self,
                configurations: [modelConfiguration]
            )
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
