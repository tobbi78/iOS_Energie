//
//  SwiftDataMigrationTests.swift
//  EnergieTests
//
//  Created by Tobias Florian on 06.10.26.
//

import Foundation
import SwiftData
import Testing
@testable import Energie

/// Guards the versioned schema / migration plan introduced by BACKLOG.md F8.1.
@MainActor
struct SwiftDataMigrationTests {

    /// Entity names drive both the SQLite store layout and the CloudKit record types
    /// (`CD_<name>`) — nesting the models in `EnergieSchemaV1` must not have changed them.
    @Test func currentSchemaKeepsUnqualifiedEntityNames() {
        let names = EnergieMigrationPlan.currentSchema.entities.map(\.name).sorted()
        #expect(names == ["HeatPumpEfficiencySample", "PVDailySample", "PVYearlySample"])
    }

    /// The app opens its store with `currentSchema`; it must describe the latest plan entry,
    /// otherwise a newly added schema version would never actually be used.
    @Test func currentSchemaMatchesLatestPlanEntry() throws {
        let latest = try #require(EnergieMigrationPlan.schemas.last)
        #expect(latest.versionIdentifier == EnergieSchemaV1.versionIdentifier)
        #expect(Schema(versionedSchema: latest).entities.map(\.name).sorted()
            == EnergieMigrationPlan.currentSchema.entities.map(\.name).sorted())
    }

    /// Installations from before F8.1 created their store from a flat, unversioned `Schema`.
    /// Reopening that same file through the migration plan must keep every row.
    @Test func storeCreatedWithFlatSchemaOpensThroughMigrationPlan() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SwiftDataMigrationTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("default.store")

        // `cloudKitDatabase: .none` explicitly — see SolarModelTests.makeContext for why.
        do {
            let legacySchema = Schema([PVDailySample.self, PVYearlySample.self, HeatPumpEfficiencySample.self])
            let legacyContainer = try ModelContainer(
                for: legacySchema,
                configurations: ModelConfiguration(schema: legacySchema, url: storeURL, cloudKitDatabase: .none)
            )
            let context = ModelContext(legacyContainer)
            context.insert(PVDailySample(date: Date(timeIntervalSince1970: 1_000_000), producedWh: 1234))
            context.insert(PVYearlySample(yearStart: Date(timeIntervalSince1970: 0), producedWh: 5678))
            context.insert(HeatPumpEfficiencySample(period: .month, boundaryDate: Date(timeIntervalSince1970: 0), consumedKWh: 10, producedKWh: 40))
            try context.save()
        }

        let schema = EnergieMigrationPlan.currentSchema
        let container = try ModelContainer(
            for: schema,
            migrationPlan: EnergieMigrationPlan.self,
            configurations: ModelConfiguration(schema: schema, url: storeURL, cloudKitDatabase: .none)
        )
        let context = ModelContext(container)

        let daily = try context.fetch(FetchDescriptor<PVDailySample>())
        let yearly = try context.fetch(FetchDescriptor<PVYearlySample>())
        let efficiency = try context.fetch(FetchDescriptor<HeatPumpEfficiencySample>())
        #expect(daily.map(\.producedWh) == [1234])
        #expect(yearly.map(\.producedWh) == [5678])
        #expect(efficiency.map(\.efficiency) == [4])
    }
}
