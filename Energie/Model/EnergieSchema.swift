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

/// Migration plan for the SwiftData store (BACKLOG.md F8.1).
///
/// Checklist for the next `@Model` change:
/// 1. Add `EnergieSchemaV2` with its own copies of the changed models; leave `EnergieSchemaV1`
///    untouched — it has to keep describing the shipped store.
/// 2. Repoint the typealiases above to V2, append V2 to `schemas` and add a
///    `.lightweight(fromVersion: EnergieSchemaV1.self, toVersion: EnergieSchemaV2.self)` stage.
/// 3. CloudKit mirroring (Epic 0) only tolerates **additive** changes: new optional properties,
///    new properties with a declaration-site default (F8.2), new entities. No renames, no
///    deletions, no type changes and no custom stages that transform data. Afterwards deploy the
///    CloudKit schema to Production in the CloudKit Console before shipping.
enum EnergieMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [EnergieSchemaV1.self]
    }

    static var stages: [MigrationStage] {
        []
    }

    /// The schema the app opens its store with — always the latest entry in `schemas`.
    static var currentSchema: Schema {
        Schema(versionedSchema: EnergieSchemaV1.self)
    }
}
