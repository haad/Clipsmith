import SwiftData
import Foundation
import OSLog

private let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.github.haad.clipsmith",
    category: "SnippetStore"
)

// MARK: - SnippetInfo

/// Sendable value type for cross-actor transfer of Snippet data.
///
/// Mirrors the ClippingInfo pattern: carries PersistentIdentifier (safe cross-actor reference)
/// plus copied fields for display and paste without re-fetching the @Model.
struct SnippetInfo: Sendable, Identifiable {
    let id: PersistentIdentifier
    let name: String
    let content: String
    let language: String?
    let tags: [String]
    let createdAt: Date
    let updatedAt: Date
}

// MARK: - SnippetStore

/// Background data store for code snippet CRUD operations.
///
/// Mirrors the ClipboardStore @ModelActor pattern:
/// - All mutations happen on the model actor's background executor
/// - Returns `PersistentIdentifier` (Sendable) for cross-actor references
/// - Calls `modelContext.save()` immediately after every mutation (PITFALL 3)
@ModelActor
actor SnippetStore {

    // MARK: - Insert

    /// Inserts a new snippet with name, content, language, and tags.
    ///
    /// Always saves immediately to ensure the PersistentIdentifier is permanent (PITFALL 3).
    func insert(
        name: String,
        content: String,
        language: String?,
        tags: [String]
    ) throws {
        let snippet = ClipsmithSchemaV1.Snippet(
            name: name,
            content: content,
            language: language,
            tags: tags
        )
        modelContext.insert(snippet)
        try modelContext.save()
        logger.debug("Snippet inserted: \(name, privacy: .public)")
    }

    // MARK: - Fetch All

    /// Returns all snippet persistent IDs sorted by updatedAt descending (most recently edited first).
    func fetchAll() throws -> [PersistentIdentifier] {
        let descriptor = FetchDescriptor<ClipsmithSchemaV1.Snippet>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        return try modelContext.fetch(descriptor).map(\.persistentModelID)
    }

    // MARK: - Fetch By Language

    /// Returns snippet persistent IDs filtered by a specific language, sorted by updatedAt descending.
    func fetchByLanguage(_ language: String) throws -> [PersistentIdentifier] {
        let descriptor = FetchDescriptor<ClipsmithSchemaV1.Snippet>(
            predicate: #Predicate { $0.language == language },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        return try modelContext.fetch(descriptor).map(\.persistentModelID)
    }

    // MARK: - Search

    /// Searches snippets by name, content, or tags.
    ///
    /// - Empty query returns all snippets (sorted by updatedAt descending).
    /// - Non-empty query matches name/content via `localizedStandardContains` (case-insensitive, locale-aware).
    /// - Tag matching is performed in-memory since SwiftData #Predicate does not support
    ///   `.contains()` on `[String]` arrays.
    func search(query: String) throws -> [PersistentIdentifier] {
        if query.isEmpty {
            return try fetchAll()
        }

        // Fetch name + content matches via predicate (SQLite-level filtering)
        let descriptor = FetchDescriptor<ClipsmithSchemaV1.Snippet>(
            predicate: #Predicate { snippet in
                snippet.name.localizedStandardContains(query)
                    || snippet.content.localizedStandardContains(query)
            },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        var matched = try modelContext.fetch(descriptor)

        // Fetch all snippets and filter for tag matches in-memory (tags: [String] not SQLite-filterable)
        let allDescriptor = FetchDescriptor<ClipsmithSchemaV1.Snippet>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        let all = try modelContext.fetch(allDescriptor)
        let tagMatches = all.filter { snippet in
            snippet.tags.contains { tag in
                tag.localizedStandardContains(query)
            }
        }

        // Merge, deduplicate by persistentModelID, preserve updatedAt ordering
        let matchedIDs = Set(matched.map(\.persistentModelID))
        for tagMatch in tagMatches where !matchedIDs.contains(tagMatch.persistentModelID) {
            matched.append(tagMatch)
        }

        // Re-sort merged result by updatedAt descending
        matched.sort { $0.updatedAt > $1.updatedAt }

        return matched.map(\.persistentModelID)
    }

    // MARK: - Update

    /// Updates an existing snippet's fields and refreshes updatedAt.
    func update(
        id: PersistentIdentifier,
        name: String,
        content: String,
        language: String?,
        tags: [String]
    ) throws {
        guard let snippet = modelContext.model(for: id) as? ClipsmithSchemaV1.Snippet else {
            logger.warning("update: snippet not found for id \(id.hashValue, privacy: .public)")
            return
        }
        snippet.name = name
        snippet.content = content
        snippet.language = language
        snippet.tags = tags
        snippet.updatedAt = .now
        try modelContext.save()
        logger.debug("Snippet updated: \(name, privacy: .public)")
    }

    // MARK: - Delete

    /// Deletes a snippet by its persistent ID.
    func delete(id: PersistentIdentifier) throws {
        guard let snippet = modelContext.model(for: id) as? ClipsmithSchemaV1.Snippet else { return }
        modelContext.delete(snippet)
        try modelContext.save()
        logger.debug("Snippet deleted")
    }

    // MARK: - Accessors

    /// Returns the plain-text content for a snippet by its persistent ID.
    func content(for id: PersistentIdentifier) -> String? {
        return (modelContext.model(for: id) as? ClipsmithSchemaV1.Snippet)?.content
    }

    /// Returns a SnippetInfo value for a snippet by its persistent ID.
    ///
    /// Returns nil if the snippet is not found in this model context.
    func snippet(for id: PersistentIdentifier) -> SnippetInfo? {
        guard let snippet = modelContext.model(for: id) as? ClipsmithSchemaV1.Snippet else { return nil }
        return SnippetInfo(
            id: snippet.persistentModelID,
            name: snippet.name,
            content: snippet.content,
            language: snippet.language,
            tags: snippet.tags,
            createdAt: snippet.createdAt,
            updatedAt: snippet.updatedAt
        )
    }
}
