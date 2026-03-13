import SwiftData
import Foundation

enum ClipsmithSchemaV2: VersionedSchema {
    static let versionIdentifier = Schema.Version(2, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            ClipsmithSchemaV2.Clipping.self,
            ClipsmithSchemaV2.Snippet.self,
            ClipsmithSchemaV2.GistRecord.self,
            ClipsmithSchemaV2.PromptLibraryItem.self
        ]
    }

    // Re-export V1 models unchanged via typealias so migration plan can reference them
    // and so V2 consumers can use ClipsmithSchemaV2.Clipping etc. consistently.
    typealias Clipping = ClipsmithSchemaV1.Clipping
    typealias Snippet = ClipsmithSchemaV1.Snippet
    typealias GistRecord = ClipsmithSchemaV1.GistRecord

    // MARK: - PromptLibraryItem

    /// A library prompt synced from remote or created by the user.
    ///
    /// Library prompts have a stable `id` slug (e.g. "code-review-swift"), a
    /// `version` for conflict-free sync updates, and an `isUserCustomized` flag
    /// that protects user edits from being overwritten by future syncs.
    @Model
    final class PromptLibraryItem {
        #Index<PromptLibraryItem>([\.category], [\.title])

        /// Stable slug ID derived from the JSON file name (e.g. "code-review-swift").
        var id: String = ""

        /// Display title for the prompt.
        var title: String = ""

        /// Prompt content with optional {{variable}} placeholders.
        var content: String = ""

        /// Category tag: "coding", "writing", "analysis", "creative", or "My Prompts".
        var category: String = ""

        /// Monotonically increasing version from the remote source.
        /// Sync only updates prompts when remote version > local version.
        var version: Int = 1

        /// True when the user has edited this library prompt in-place.
        /// Sync skips prompts with isUserCustomized == true to preserve edits.
        var isUserCustomized: Bool = false

        /// True for prompts created by the user (not from the remote library).
        /// User-created prompts are never affected by sync.
        var isUserCreated: Bool = false

        /// Raw source URL for this prompt file (optional, for debugging/attribution).
        var sourceURL: String? = nil

        var createdAt: Date = Date.now
        var updatedAt: Date = Date.now

        init(
            id: String,
            title: String,
            content: String,
            category: String,
            version: Int = 1,
            isUserCustomized: Bool = false,
            isUserCreated: Bool = false,
            sourceURL: String? = nil
        ) {
            self.id = id
            self.title = title
            self.content = content
            self.category = category
            self.version = version
            self.isUserCustomized = isUserCustomized
            self.isUserCreated = isUserCreated
            self.sourceURL = sourceURL
        }
    }
}
