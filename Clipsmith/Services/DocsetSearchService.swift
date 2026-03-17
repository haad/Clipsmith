import Foundation

/// A single entry from a DevDocs documentation index.
struct DocEntry: Codable, Sendable, Identifiable {
    var id: String { "\(slug)/\(path)" }
    let slug: String    // Parent doc slug, e.g. "javascript"
    let name: String    // Entry name, e.g. "Array.map"
    let type: String    // Category, e.g. "Array", "Operators"
    let path: String    // Relative path into db.json, e.g. "global_objects/array/map"
}

/// Searches DevDocs documentation indexes in memory.
///
/// Each downloaded doc has an `index.json` with entries. This service loads
/// those indexes and performs substring search with prefix-first ranking.
final class DocsetSearchService: Sendable {

    private let cache = IndexCache()

    /// Load entries from a doc's index.json file on disk.
    func loadIndex(slug: String, from indexPath: URL) throws -> [DocEntry] {
        if let cached = cache.get(slug) { return cached }
        let data = try Data(contentsOf: indexPath)
        let raw = try JSONDecoder().decode(DevDocsIndex.self, from: data)
        let entries = raw.entries.map { entry in
            DocEntry(slug: slug, name: entry.name, type: entry.type, path: entry.path)
        }
        cache.set(slug, entries: entries)
        return entries
    }

    /// Search a single doc's entries by name.
    func search(query: String, in entries: [DocEntry]) -> [DocEntry] {
        let q = query.lowercased()
        let matched = entries.filter { $0.name.lowercased().contains(q) }
        return Array(matched.sorted { lhs, rhs in
            let lName = lhs.name.lowercased()
            let rName = rhs.name.lowercased()
            let lPrefix = lName.hasPrefix(q)
            let rPrefix = rName.hasPrefix(q)
            if lPrefix != rPrefix { return lPrefix }
            if lName.count != rName.count { return lName.count < rName.count }
            return lName < rName
        }.prefix(50))
    }

    /// Search across multiple downloaded docs.
    func searchAll(query: String, docsets: [DocsetInfo]) throws -> [(docset: DocsetInfo, entry: DocEntry)] {
        var results: [(DocsetInfo, DocEntry)] = []
        for docset in docsets where docset.isEnabled && docset.isDownloaded {
            guard let indexPath = docset.indexPath else { continue }
            let entries = try loadIndex(slug: docset.id, from: indexPath)
            let matched = search(query: query, in: entries)
            results.append(contentsOf: matched.map { (docset, $0) })
        }
        let q = query.lowercased()
        return Array(results.sorted { lhs, rhs in
            let lName = lhs.1.name.lowercased()
            let rName = rhs.1.name.lowercased()
            let lPrefix = lName.hasPrefix(q)
            let rPrefix = rName.hasPrefix(q)
            if lPrefix != rPrefix { return lPrefix }
            if lName.count != rName.count { return lName.count < rName.count }
            return lName < rName
        }.prefix(100))
    }

    /// Clear cached index for a doc (call when doc is deleted).
    func invalidateCache(for slug: String) {
        cache.remove(slug)
    }
}

// MARK: - DevDocs JSON format

/// The structure of a DevDocs index.json file.
private struct DevDocsIndex: Codable {
    let entries: [RawEntry]

    struct RawEntry: Codable {
        let name: String
        let path: String
        let type: String
    }
}

// MARK: - Thread-safe cache

private final class IndexCache: @unchecked Sendable {
    private var entries: [String: [DocEntry]] = [:]
    private let lock = NSLock()

    func get(_ slug: String) -> [DocEntry]? {
        lock.lock()
        defer { lock.unlock() }
        return entries[slug]
    }

    func set(_ slug: String, entries: [DocEntry]) {
        lock.lock()
        defer { lock.unlock() }
        self.entries[slug] = entries
    }

    func remove(_ slug: String) {
        lock.lock()
        defer { lock.unlock() }
        entries.removeValue(forKey: slug)
    }
}
