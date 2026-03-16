import Foundation
import GRDB

/// A single entry from a docset's searchIndex SQLite table.
struct DocEntry: Codable, FetchableRecord, Sendable, Identifiable {
    let id: Int64
    let name: String
    let type: String   // "Class", "Method", "Function", "Property", etc.
    let path: String   // Relative path from Documents/ directory
}

/// Queries docset SQLite indexes using GRDB.
///
/// Caches one DatabaseQueue per docset path to avoid file descriptor leaks
/// (Pitfall 3 from RESEARCH.md). Thread-safe — GRDB DatabaseQueue serializes access.
final class DocsetSearchService: Sendable {
    /// Cache of open database queues, keyed by docset path string.
    private let cache = DatabaseQueueCache()

    /// Search a single docset for entries matching the query.
    /// Uses SQL LIKE with prefix match for fast results, limited to 50.
    func search(query: String, in docsetPath: URL) async throws -> [DocEntry] {
        let dbPath = docsetPath
            .appendingPathComponent("Contents/Resources/docSet.dsidx").path
        let dbQueue = try cache.queue(for: dbPath)
        return try await dbQueue.read { db in
            try DocEntry.fetchAll(db, sql: """
                SELECT id, name, type, path
                FROM searchIndex
                WHERE name LIKE ?
                ORDER BY
                    CASE WHEN name LIKE ? THEN 0 ELSE 1 END,
                    length(name),
                    name
                LIMIT 50
                """, arguments: ["%\(query)%", "\(query)%"])
        }
    }

    /// Search across multiple docsets, returning results tagged with docset name.
    func searchAll(query: String, docsets: [DocsetInfo]) async throws -> [(docset: DocsetInfo, entry: DocEntry)] {
        var results: [(DocsetInfo, DocEntry)] = []
        for docset in docsets where docset.isEnabled {
            guard let localPath = docset.localPath else { continue }
            let entries = try await search(query: query, in: localPath)
            results.append(contentsOf: entries.map { (docset, $0) })
        }
        // Sort: prefix matches first, then by name length, then alphabetical
        return results.sorted { lhs, rhs in
            let lName = lhs.1.name.lowercased()
            let rName = rhs.1.name.lowercased()
            let q = query.lowercased()
            let lPrefix = lName.hasPrefix(q)
            let rPrefix = rName.hasPrefix(q)
            if lPrefix != rPrefix { return lPrefix }
            if lName.count != rName.count { return lName.count < rName.count }
            return lName < rName
        }
    }

    /// Remove cached DatabaseQueue for a docset (call when docset is deleted or reinstalled).
    func invalidateCache(for docsetPath: URL) {
        let dbPath = docsetPath
            .appendingPathComponent("Contents/Resources/docSet.dsidx").path
        cache.remove(for: dbPath)
    }
}

/// Thread-safe cache for DatabaseQueue instances.
private final class DatabaseQueueCache: @unchecked Sendable {
    private var queues: [String: DatabaseQueue] = [:]
    private let lock = NSLock()

    func queue(for path: String) throws -> DatabaseQueue {
        lock.lock()
        defer { lock.unlock() }
        if let existing = queues[path] { return existing }
        let q = try DatabaseQueue(path: path)
        queues[path] = q
        return q
    }

    func remove(for path: String) {
        lock.lock()
        defer { lock.unlock() }
        queues.removeValue(forKey: path)
    }
}
