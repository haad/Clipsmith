import SwiftData

enum FlycutMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [FlycutSchemaV1.self, FlycutSchemaV2.self]
    }

    static var stages: [MigrationStage] {
        [migrateV1toV2]
    }

    /// Lightweight migration from V1 to V2.
    ///
    /// Adding a new independent @Model (PromptLibraryItem) with all-default fields
    /// is a lightweight migration — SwiftData handles it automatically with no data loss.
    /// No custom migration closure is needed.
    static let migrateV1toV2 = MigrationStage.lightweight(
        fromVersion: FlycutSchemaV1.self,
        toVersion: FlycutSchemaV2.self
    )
}
