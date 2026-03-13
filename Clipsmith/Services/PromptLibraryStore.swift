import SwiftData
import Foundation
import OSLog

private let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.generalarcade.flycut",
    category: "PromptLibraryStore"
)

// MARK: - PromptInfo

/// Sendable value type for cross-actor transfer of PromptLibraryItem data.
///
/// Mirrors the SnippetInfo pattern: carries PersistentIdentifier (safe cross-actor reference)
/// plus copied fields for display and paste without re-fetching the @Model.
struct PromptInfo: Sendable, Identifiable {
    let id: PersistentIdentifier
    let promptID: String        // stable slug from JSON (e.g. "code-review-swift")
    let title: String
    let content: String
    let category: String
    let version: Int
    let isUserCustomized: Bool
    let isUserCreated: Bool
}

// MARK: - PromptDTO

/// Decodable struct for a single prompt entry in the remote JSON catalog.
struct PromptDTO: Decodable, Sendable {
    let id: String
    let title: String
    let category: String
    let version: Int
    let content: String
}

// MARK: - PromptCatalog

/// Decodable struct for the top-level JSON catalog format.
struct PromptCatalog: Decodable, Sendable {
    let version: Int
    let prompts: [PromptDTO]
}

// MARK: - PromptLibraryStore

/// Background data store for prompt library CRUD operations.
///
/// Mirrors the SnippetStore @ModelActor pattern:
/// - All mutations happen on the model actor's background executor
/// - Returns `PersistentIdentifier` (Sendable) for cross-actor references
/// - Calls `modelContext.save()` immediately after every mutation
@ModelActor
actor PromptLibraryStore {

    // MARK: - Insert

    /// Inserts a new prompt library item.
    func insert(
        id: String,
        title: String,
        content: String,
        category: String,
        version: Int = 1,
        isUserCreated: Bool = false
    ) throws {
        let item = ClipsmithSchemaV2.PromptLibraryItem(
            id: id,
            title: title,
            content: content,
            category: category,
            version: version,
            isUserCreated: isUserCreated
        )
        modelContext.insert(item)
        try modelContext.save()
        logger.debug("PromptLibraryItem inserted: \(title, privacy: .public)")
    }

    // MARK: - Fetch All

    /// Returns all prompt persistent IDs sorted by title ascending.
    func fetchAll() throws -> [PersistentIdentifier] {
        let descriptor = FetchDescriptor<ClipsmithSchemaV2.PromptLibraryItem>(
            sortBy: [SortDescriptor(\.title, order: .forward)]
        )
        return try modelContext.fetch(descriptor).map(\.persistentModelID)
    }

    // MARK: - Fetch By Category

    /// Returns prompt persistent IDs filtered by category, sorted by title ascending.
    func fetchByCategory(_ category: String) throws -> [PersistentIdentifier] {
        let descriptor = FetchDescriptor<ClipsmithSchemaV2.PromptLibraryItem>(
            predicate: #Predicate { $0.category == category },
            sortBy: [SortDescriptor(\.title, order: .forward)]
        )
        return try modelContext.fetch(descriptor).map(\.persistentModelID)
    }

    // MARK: - Search

    /// Searches prompts by title and content, with optional #category prefix syntax.
    ///
    /// - If query starts with "#", the first word (after "#") filters by category.
    ///   Any remaining text after the category token searches title/content.
    ///   Examples: "#coding" → all coding prompts; "#coding review" → coding + "review"
    /// - Without "#" prefix, searches title and content with localizedStandardContains.
    /// - Empty query returns all prompts.
    func search(query: String) throws -> [PersistentIdentifier] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)

        if trimmed.isEmpty {
            return try fetchAll()
        }

        // #category search syntax
        if trimmed.hasPrefix("#") {
            let withoutHash = String(trimmed.dropFirst())
            let parts = withoutHash.split(separator: " ", maxSplits: 1)
            let categoryFilter = parts.isEmpty ? "" : String(parts[0])
            let textSearch = parts.count > 1 ? String(parts[1]).trimmingCharacters(in: .whitespaces) : ""

            if textSearch.isEmpty {
                // Pure category filter
                return try fetchByCategory(categoryFilter)
            } else {
                // Category filter + text search within that category
                let descriptor = FetchDescriptor<ClipsmithSchemaV2.PromptLibraryItem>(
                    predicate: #Predicate { item in
                        item.category == categoryFilter &&
                        (item.title.localizedStandardContains(textSearch) ||
                         item.content.localizedStandardContains(textSearch))
                    },
                    sortBy: [SortDescriptor(\.title, order: .forward)]
                )
                return try modelContext.fetch(descriptor).map(\.persistentModelID)
            }
        }

        // Standard title/content search
        let descriptor = FetchDescriptor<ClipsmithSchemaV2.PromptLibraryItem>(
            predicate: #Predicate { item in
                item.title.localizedStandardContains(trimmed) ||
                item.content.localizedStandardContains(trimmed)
            },
            sortBy: [SortDescriptor(\.title, order: .forward)]
        )
        return try modelContext.fetch(descriptor).map(\.persistentModelID)
    }

    // MARK: - Upsert (Version-Aware Sync)

    /// Version-aware upsert for syncing a remote prompt.
    ///
    /// Rules:
    /// 1. If prompt exists and isUserCustomized == true: skip (preserve user edits)
    /// 2. If prompt exists and remote.version <= existing.version: skip (not newer)
    /// 3. If prompt exists and remote.version > existing.version: update in place
    /// 4. If prompt does not exist: insert new
    func upsert(remote: PromptDTO) throws {
        let remoteID = remote.id
        let descriptor = FetchDescriptor<ClipsmithSchemaV2.PromptLibraryItem>(
            predicate: #Predicate { $0.id == remoteID }
        )
        if let existing = try modelContext.fetch(descriptor).first {
            // Skip if user has customized this prompt (PMPT-07)
            guard !existing.isUserCustomized else {
                logger.debug("upsert: skipping \(remote.id, privacy: .public) — user customized")
                return
            }
            // Skip if remote version is not newer
            guard remote.version > existing.version else {
                logger.debug("upsert: skipping \(remote.id, privacy: .public) — remote version not newer (\(remote.version) <= \(existing.version))")
                return
            }
            // Update in place
            existing.content = remote.content
            existing.title = remote.title
            existing.version = remote.version
            existing.updatedAt = .now
            try modelContext.save()
            logger.debug("upsert: updated \(remote.id, privacy: .public) to version \(remote.version)")
        } else {
            // Insert new prompt from remote
            let item = ClipsmithSchemaV2.PromptLibraryItem(
                id: remote.id,
                title: remote.title,
                content: remote.content,
                category: remote.category,
                version: remote.version
            )
            modelContext.insert(item)
            try modelContext.save()
            logger.debug("upsert: inserted new \(remote.id, privacy: .public)")
        }
    }

    // MARK: - Update (User Edit)

    /// Updates a prompt's title and content, marking it as user-customized.
    ///
    /// Sets isUserCustomized = true so future sync operations skip this prompt.
    func update(id: PersistentIdentifier, title: String, content: String) throws {
        guard let item = modelContext.model(for: id) as? ClipsmithSchemaV2.PromptLibraryItem else {
            logger.warning("update: prompt not found for id \(id.hashValue, privacy: .public)")
            return
        }
        item.title = title
        item.content = content
        item.isUserCustomized = true
        item.updatedAt = .now
        try modelContext.save()
        logger.debug("update: marked \(title, privacy: .public) as user customized")
    }

    // MARK: - Revert to Original

    /// Clears isUserCustomized flag so the next sync restores the upstream version.
    func revertToOriginal(id: PersistentIdentifier) throws {
        guard let item = modelContext.model(for: id) as? ClipsmithSchemaV2.PromptLibraryItem else {
            logger.warning("revertToOriginal: prompt not found for id \(id.hashValue, privacy: .public)")
            return
        }
        item.isUserCustomized = false
        item.updatedAt = .now
        try modelContext.save()
        logger.debug("revertToOriginal: cleared customization flag for \(item.title, privacy: .public)")
    }

    // MARK: - Delete

    /// Deletes a prompt by its persistent ID.
    func delete(id: PersistentIdentifier) throws {
        guard let item = modelContext.model(for: id) as? ClipsmithSchemaV2.PromptLibraryItem else { return }
        modelContext.delete(item)
        try modelContext.save()
        logger.debug("PromptLibraryItem deleted")
    }

    // MARK: - Deduplicate

    /// Removes duplicate PromptLibraryItems that share the same `id` slug.
    /// Keeps the entry with the highest version (or user-customized one).
    func deduplicate() throws {
        let descriptor = FetchDescriptor<ClipsmithSchemaV2.PromptLibraryItem>(
            sortBy: [SortDescriptor(\.id, order: .forward)]
        )
        let all = try modelContext.fetch(descriptor)

        var seen: [String: ClipsmithSchemaV2.PromptLibraryItem] = [:]
        for item in all {
            if let existing = seen[item.id] {
                // Keep the one that's user-customized, or the higher version
                if item.isUserCustomized && !existing.isUserCustomized {
                    modelContext.delete(existing)
                    seen[item.id] = item
                } else if item.version > existing.version && !existing.isUserCustomized {
                    modelContext.delete(existing)
                    seen[item.id] = item
                } else {
                    modelContext.delete(item)
                }
            } else {
                seen[item.id] = item
            }
        }
        try modelContext.save()
        let removed = all.count - seen.count
        if removed > 0 {
            logger.info("deduplicate: removed \(removed) duplicate prompts")
        }
    }

    // MARK: - Accessors

    /// Returns the plain-text content for a prompt by its persistent ID.
    func content(for id: PersistentIdentifier) -> String? {
        return (modelContext.model(for: id) as? ClipsmithSchemaV2.PromptLibraryItem)?.content
    }

    /// Returns a PromptInfo value for a prompt by its persistent ID.
    ///
    /// Returns nil if the prompt is not found in this model context.
    func prompt(for id: PersistentIdentifier) -> PromptInfo? {
        guard let item = modelContext.model(for: id) as? ClipsmithSchemaV2.PromptLibraryItem else { return nil }
        return PromptInfo(
            id: item.persistentModelID,
            promptID: item.id,
            title: item.title,
            content: item.content,
            category: item.category,
            version: item.version,
            isUserCustomized: item.isUserCustomized,
            isUserCreated: item.isUserCreated
        )
    }
}
