import Foundation

/// A single entry from a DevDocs documentation index.
struct DocEntry: Codable, Sendable, Identifiable {
    var id: String { "\(slug)/\(path)" }
    let slug: String    // Parent doc slug, e.g. "javascript"
    let name: String    // Entry name, e.g. "Array.map"
    let type: String    // Category, e.g. "Array", "Operators"
    let path: String    // Relative path into db.json, e.g. "global_objects/array/map"
}

/// A scored search result for sorting.
struct ScoredDocEntry: Sendable {
    let entry: DocEntry
    let score: Double   // FuzzyMatcher score, higher is better
}

/// Searches DevDocs documentation indexes in memory using fuzzy matching.
///
/// Supports doc-scoped search via prefix syntax: `python:map`, `go:fmt`.
/// Uses FuzzyMatcher for subsequence matching with consecutive-bonus scoring.
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

    /// Parse a query for doc prefix filter.
    /// "python:map" → (docFilter: "python", query: "map")
    /// "map" → (docFilter: nil, query: "map")
    func parseQuery(_ rawQuery: String) -> (docFilter: String?, query: String) {
        guard let colonIdx = rawQuery.firstIndex(of: ":") else {
            return (nil, rawQuery)
        }
        let prefix = String(rawQuery[rawQuery.startIndex..<colonIdx]).trimmingCharacters(in: .whitespaces)
        let query = String(rawQuery[rawQuery.index(after: colonIdx)...]).trimmingCharacters(in: .whitespaces)
        guard !prefix.isEmpty else { return (nil, rawQuery) }
        return (prefix, query)
    }

    /// Check if a docset matches a filter string (case-insensitive, partial match).
    func docsetMatchesFilter(_ docset: DocsetInfo, filter: String) -> Bool {
        let f = filter.lowercased()
        return docset.id.lowercased().contains(f)
            || docset.displayName.lowercased().contains(f)
    }

    /// Search a single doc's entries by name using fuzzy matching.
    func search(query: String, in entries: [DocEntry]) -> [ScoredDocEntry] {
        guard !query.isEmpty else { return [] }
        var scored: [ScoredDocEntry] = []
        for entry in entries {
            if let score = FuzzyMatcher.score(entry.name, query: query) {
                scored.append(ScoredDocEntry(entry: entry, score: score))
            }
        }
        return Array(scored.sorted { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            if lhs.entry.name.count != rhs.entry.name.count {
                return lhs.entry.name.count < rhs.entry.name.count
            }
            return lhs.entry.name < rhs.entry.name
        }.prefix(50))
    }

    /// Search across multiple downloaded docs with optional doc filter.
    func searchAll(query: String, docFilter: String?, docsets: [DocsetInfo]) throws -> [(docset: DocsetInfo, entry: DocEntry, score: Double)] {
        var results: [(DocsetInfo, DocEntry, Double)] = []
        let targetDocsets: [DocsetInfo]
        if let filter = docFilter {
            targetDocsets = docsets.filter { docsetMatchesFilter($0, filter: filter) }
        } else {
            targetDocsets = docsets
        }
        for docset in targetDocsets where docset.isEnabled && docset.isDownloaded {
            guard let indexPath = docset.indexPath else { continue }
            let entries = try loadIndex(slug: docset.id, from: indexPath)
            let matched = search(query: query, in: entries)
            results.append(contentsOf: matched.map { (docset, $0.entry, $0.score) })
        }
        return Array(results.sorted { lhs, rhs in
            if lhs.2 != rhs.2 { return lhs.2 > rhs.2 }
            if lhs.1.name.count != rhs.1.name.count {
                return lhs.1.name.count < rhs.1.name.count
            }
            return lhs.1.name < rhs.1.name
        }.prefix(100))
    }

    /// Find which docsets match a filter prefix (for UI display).
    func matchingDocsets(filter: String, from docsets: [DocsetInfo]) -> [DocsetInfo] {
        docsets.filter { docsetMatchesFilter($0, filter: filter) && $0.isEnabled && $0.isDownloaded }
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
