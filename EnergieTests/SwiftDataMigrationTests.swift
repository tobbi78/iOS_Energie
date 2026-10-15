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
        #expect(names == ["HeatPumpEfficiencySample", "PVDailySample", "PVYearlySample", "ShellyDailySample"])
    }

    /// The app opens its store with `currentSchema`; it must describe the latest plan entry,
    /// otherwise a newly added schema version would never actually be used.
    @Test func currentSchemaMatchesLatestPlanEntry() throws {
        let latest = try #require(EnergieMigrationPlan.schemas.last)
        #expect(latest.versionIdentifier == EnergieSchemaV3.versionIdentifier)
        #expect(Schema(versionedSchema: latest).entities.map(\.name).sorted()
            == EnergieMigrationPlan.currentSchema.entities.map(\.name).sorted())
    }

    /// `EnergieMigrationPlan` must actually contain one lightweight stage per version step, not
    /// just list the versions in `schemas` — a missing stage would silently skip the migration and
    /// SwiftData would fail to open an existing older store against the current schema.
    @Test func migrationPlanDeclaresOneStagePerVersionStep() {
        let identifiers = EnergieMigrationPlan.schemas.map { $0.versionIdentifier }
        // V2 is deliberately absent: its models are identical to V1's, and the duplicate checksum
        // broke staged migration (see `EnergieSchemaV2`'s doc comment).
        #expect(identifiers == [EnergieSchemaV1.versionIdentifier, EnergieSchemaV3.versionIdentifier])
        #expect(EnergieMigrationPlan.stages.count == 1)
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

    /// Exercises the actual `.lightweight(fromVersion: V1, toVersion: V3)` stage, as opposed to
    /// `storeCreatedWithFlatSchemaOpensThroughMigrationPlan` above, which only proves a
    /// pre-F8.1, unversioned store still opens. This test pins the store to `EnergieSchemaV1`
    /// explicitly (the shipped F8.1 state, before V2 existed), then reopens it through
    /// `EnergieMigrationPlan` so SwiftData has to run the V1 -> V3 stage to reach `currentSchema`.
    @Test func storeCreatedWithSchemaV1MigratesThroughPlan() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SwiftDataMigrationTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("default.store")

        do {
            let v1Schema = Schema(versionedSchema: EnergieSchemaV1.self)
            let v1Container = try ModelContainer(
                for: v1Schema,
                configurations: ModelConfiguration(schema: v1Schema, url: storeURL, cloudKitDatabase: .none)
            )
            let context = ModelContext(v1Container)
            context.insert(PVDailySample(date: Date(timeIntervalSince1970: 2_000_000), producedWh: 4321))
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
        #expect(daily.map(\.producedWh) == [4321])
    }

    /// F14.1: a store shipped with `EnergieSchemaV2` (before `ShellyDailySample` existed) must
    /// open through the plan's V2 -> V3 stage, keep its existing rows and accept the new entity.
    @Test func storeCreatedWithSchemaV2MigratesToV3ThroughPlan() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SwiftDataMigrationTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("default.store")

        do {
            let v2Schema = Schema(versionedSchema: EnergieSchemaV2.self)
            let v2Container = try ModelContainer(
                for: v2Schema,
                configurations: ModelConfiguration(schema: v2Schema, url: storeURL, cloudKitDatabase: .none)
            )
            let context = ModelContext(v2Container)
            context.insert(PVDailySample(date: Date(timeIntervalSince1970: 3_000_000), producedWh: 999))
            try context.save()
        }

        let schema = EnergieMigrationPlan.currentSchema
        let container = try ModelContainer(
            for: schema,
            migrationPlan: EnergieMigrationPlan.self,
            configurations: ModelConfiguration(schema: schema, url: storeURL, cloudKitDatabase: .none)
        )
        let context = ModelContext(container)

        #expect(try context.fetch(FetchDescriptor<PVDailySample>()).map(\.producedWh) == [999])
        context.insert(ShellyDailySample(deviceID: "abc", date: Date(timeIntervalSince1970: 3_000_000), energyWh: 42))
        try context.save()
        #expect(try context.fetch(FetchDescriptor<ShellyDailySample>()).map(\.energyWh) == [42])
    }
}
