import SwiftData
import Foundation
import OSLog

private let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.github.haad.clipsmith",
    category: "ClipboardStore"
)

@ModelActor
actor ClipboardStore {

    // MARK: - Insert

    /// Inserts a new clipping, enforcing deduplication (move-to-top) and history size limit.
    ///
    /// Bug #2 behaviour: if identical content already exists, the existing clipping is moved
    /// to top (timestamp updated, source metadata refreshed) instead of silently dropped.
    ///
    /// - Parameter timestamp: Optional explicit timestamp (used during import to restore original
    ///   timestamps). Defaults to `.now` for normal clipboard captures.
    func insert(
        content: String,
        sourceAppName: String? = nil,
        sourceAppBundleURL: String? = nil,
        timestamp: Date = .now,
        rememberNum: Int
    ) throws {
        // Deduplication: controlled by removeDuplicates setting (Bug #9).
        // When enabled (default), move the existing clipping to top instead of creating a duplicate.
        // When disabled, allow duplicate clippings to be inserted.
        let shouldDedup = UserDefaults.standard.bool(forKey: AppSettingsKeys.removeDuplicates)
        if shouldDedup {
            let existing = try modelContext.fetch(
                FetchDescriptor<ClipsmithSchemaV1.Clipping>(
                    predicate: #Predicate { $0.content == content }
                )
            )
            if let duplicate = existing.first {
                // Move to top: update timestamp and refresh source metadata
                duplicate.timestamp = .now
                duplicate.sourceAppName = sourceAppName
                duplicate.sourceAppBundleURL = sourceAppBundleURL
                try modelContext.save()
                logger.debug("Duplicate clipping moved to top")
                return
            }
        }

        let clipping = ClipsmithSchemaV1.Clipping(
            content: content,
            timestamp: timestamp,
            sourceAppName: sourceAppName,
            sourceAppBundleURL: sourceAppBundleURL
        )
        modelContext.insert(clipping)
        try modelContext.save()

        // Trim to rememberNum
        try trimToLimit(rememberNum: rememberNum)
    }

    // MARK: - Fetch

    /// Returns all clipping persistent IDs ordered by timestamp descending (newest first).
    func fetchAll(limit: Int? = nil) throws -> [PersistentIdentifier] {
        var descriptor = FetchDescriptor<ClipsmithSchemaV1.Clipping>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        if let limit { descriptor.fetchLimit = limit }
        return try modelContext.fetch(descriptor).map(\.persistentModelID)
    }

    /// Returns plain-text content for a clipping by its persistent ID.
    func content(for id: PersistentIdentifier) -> String? {
        return (modelContext.model(for: id) as? ClipsmithSchemaV1.Clipping)?.content
    }

    /// Returns the source app name for a clipping by its persistent ID.
    func sourceAppName(for id: PersistentIdentifier) -> String? {
        return (modelContext.model(for: id) as? ClipsmithSchemaV1.Clipping)?.sourceAppName
    }

    /// Returns the source app bundle URL for a clipping by its persistent ID.
    func sourceAppBundleURL(for id: PersistentIdentifier) -> String? {
        return (modelContext.model(for: id) as? ClipsmithSchemaV1.Clipping)?.sourceAppBundleURL
    }

    /// Returns the timestamp for a clipping by its persistent ID.
    func timestamp(for id: PersistentIdentifier) -> Date? {
        return (modelContext.model(for: id) as? ClipsmithSchemaV1.Clipping)?.timestamp
    }

    // MARK: - Move to top

    /// Moves an existing clipping to the top of history by updating its timestamp to .now.
    ///
    /// Used by pasteMovesToTop (Bug #23): after pasting, the pasted clipping is promoted
    /// to position 0 so subsequent paste sequences stay coherent.
    /// No-op if no clipping with the given content exists.
    func moveToTop(content: String) throws {
        let results = try modelContext.fetch(
            FetchDescriptor<ClipsmithSchemaV1.Clipping>(
                predicate: #Predicate { $0.content == content }
            )
        )
        if let clipping = results.first {
            clipping.timestamp = .now
            try modelContext.save()
        }
    }

    // MARK: - Delete

    /// Deletes a single clipping by its persistent ID.
    func delete(id: PersistentIdentifier) throws {
        guard let clipping = modelContext.model(for: id) as? ClipsmithSchemaV1.Clipping else { return }
        modelContext.delete(clipping)
        try modelContext.save()
    }

    // MARK: - Merge

    /// Merges all clippings into a single newline-joined entry (Bug #24).
    ///
    /// Creates a new "Merged" clipping from all existing clippings, ordered newest first.
    /// No-op if fewer than 2 clippings exist.
    func mergeAll(rememberNum: Int) throws {
        let all = try modelContext.fetch(
            FetchDescriptor<ClipsmithSchemaV1.Clipping>(
                sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
            )
        )
        guard all.count > 1 else { return }
        let merged = all.map(\.content).joined(separator: "\n")
        let clipping = ClipsmithSchemaV1.Clipping(
            content: merged,
            sourceAppName: "Merged"
        )
        modelContext.insert(clipping)
        try modelContext.save()
        logger.info("Merged \(all.count, privacy: .public) clippings")
    }

    /// Deletes all Clipping records from the store.
    func clearAll() throws {
        try modelContext.delete(model: ClipsmithSchemaV1.Clipping.self)
        try modelContext.save()
        logger.info("All clippings cleared")
    }

    // MARK: - Trim

    /// Removes oldest clippings beyond rememberNum, keeping the newest.
    private func trimToLimit(rememberNum: Int) throws {
        let descriptor = FetchDescriptor<ClipsmithSchemaV1.Clipping>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        let all = try modelContext.fetch(descriptor)
        if all.count > rememberNum {
            for clipping in all[rememberNum...] {
                modelContext.delete(clipping)
            }
            try modelContext.save()
        }
    }
}
