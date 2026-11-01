import SwiftData
import Foundation

/// Schema V3 drops `GistRecord` (GitHub Gist sharing was removed).
///
/// Every remaining model is re-exported unchanged, so the V2 → V3 step is a
/// lightweight migration: SwiftData deletes the orphaned entity's table.
enum ClipsmithSchemaV3: VersionedSchema {
    static let versionIdentifier = Schema.Version(3, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            ClipsmithSchemaV3.Clipping.self,
            ClipsmithSchemaV3.Snippet.self,
            ClipsmithSchemaV3.PromptLibraryItem.self
        ]
    }

    typealias Clipping = ClipsmithSchemaV1.Clipping
    typealias Snippet = ClipsmithSchemaV1.Snippet
    typealias PromptLibraryItem = ClipsmithSchemaV2.PromptLibraryItem
}
