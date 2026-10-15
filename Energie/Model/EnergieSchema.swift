//
//  EnergieSchema.swift
//  Energie
//
//  Created by Tobias Florian on 06.10.26.
//

import Foundation
import SwiftData

/// The current model types, resolved to the latest schema version — every call site uses these
/// names, so bumping the schema only means repointing the aliases (see `EnergieMigrationPlan`).
typealias PVDailySample = EnergieSchemaV1.PVDailySample
typealias PVYearlySample = EnergieSchemaV1.PVYearlySample
typealias HeatPumpEfficiencySample = EnergieSchemaV1.HeatPumpEfficiencySample
typealias ShellyDailySample = EnergieSchemaV3.ShellyDailySample

/// Version 1 of the persisted schema, frozen exactly as it shipped before F8.1 introduced
/// versioning (BACKLOG.md F8.1). Entity names are the unqualified class names, so nesting the
/// models in here didn't change the store hash or the CloudKit record types (`CD_PVDailySample`
/// etc.) — existing installations open this store without any migration.
enum EnergieSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [PVDailySample.self, PVYearlySample.self, HeatPumpEfficiencySample.self]
    }
}

/// Version 2 of the persisted schema (BACKLOG.md F8.1 follow-up). Reuses `EnergieSchemaV1`'s
/// model types verbatim — no entity actually changed yet — purely to exercise a real
/// `.lightweight` migration stage end to end instead of leaving `EnergieMigrationPlan.stages`
/// empty.
///
/// **No longer part of `EnergieMigrationPlan` (F14.1).** Because its models are identical to V1's,
/// V1 and V2 share the same model checksum — harmless while V2 was the current schema (an
/// existing store simply matched it, no stage ever ran), but as soon as a real V3 needed a
/// migration, Core Data's staged migration couldn't resolve that checksum to a single stage and
/// aborted while opening the store (observed in the simulator, app crash at launch). A store
/// shipped "as V2" is byte-for-byte a V1 store, so the plan migrates V1 -> V3 directly instead.
/// Kept only so the migration tests can still create a store exactly as V2 shipped.
enum EnergieSchemaV2: VersionedSchema {
    static let versionIdentifier = Schema.Version(2, 0, 0)

    static var models: [any PersistentModel.Type] {
        [PVDailySample.self, PVYearlySample.self, HeatPumpEfficiencySample.self]
    }
}

/// Version 3 of the persisted schema (BACKLOG.md F14.1): adds the new `ShellyDailySample` entity
/// for the Shelly plugs' locally recorded history. Purely additive — the existing entities are
/// reused verbatim from `EnergieSchemaV1` — so it stays within CloudKit's constraints (see the
/// checklist below).
enum EnergieSchemaV3: VersionedSchema {
    static let versionIdentifier = Schema.Version(3, 0, 0)

    static var models: [any PersistentModel.Type] {
        [PVDailySample.self, PVYearlySample.self, HeatPumpEfficiencySample.self, ShellyDailySample.self]
    }
}

/// Migration plan for the SwiftData store (BACKLOG.md F8.1).
///
/// Checklist for the next `@Model` change:
/// 1. Add `EnergieSchemaV4` with its own copies of the changed models (or, for a new entity, just
///    the new model nested in V4, like `ShellyDailySample` in V3); leave the earlier versions
///    untouched — they have to keep describing already-shipped stores.
/// 2. Repoint the typealiases above to V4, append V4 to `schemas` and add a
///    `.lightweight(fromVersion: EnergieSchemaV3.self, toVersion: EnergieSchemaV4.self)` stage.
/// 3. CloudKit mirroring (Epic 0) only tolerates **additive** changes: new optional properties,
///    new properties with a declaration-site default (F8.2), new entities. No renames, no
///    deletions, no type changes and no custom stages that transform data. Afterwards deploy the
///    CloudKit schema to Production in the CloudKit Console before shipping.
/// 4. Never add a version whose models are identical to the previous one (see `EnergieSchemaV2`)
///    — duplicate checksums break staged migration.
enum EnergieMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [EnergieSchemaV1.self, EnergieSchemaV3.self]
    }

    static var stages: [MigrationStage] {
        [.lightweight(fromVersion: EnergieSchemaV1.self, toVersion: EnergieSchemaV3.self)]
    }

    /// The schema the app opens its store with — always the latest entry in `schemas`.
    static var currentSchema: Schema {
        Schema(versionedSchema: EnergieSchemaV3.self)
    }
}
