import Foundation

/// Pure filtering for the Snippets browser section: language chips and text search.
nonisolated enum SnippetFilter {

    /// Distinct, non-empty languages sorted case-insensitively. `id == label == language`.
    static func languages(in snippets: [ClipsmithSchemaV1.Snippet]) -> [BrowserFilterOption] {
        let distinct = Set(snippets.compactMap { snippet -> String? in
            guard let language = snippet.language, !language.isEmpty else { return nil }
            return language
        })
        return distinct
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            .map { BrowserFilterOption(id: $0, label: $0) }
    }

    /// Case-insensitive match on name, content or any tag, AND the language chip.
    static func apply(
        _ snippets: [ClipsmithSchemaV1.Snippet],
        query: String,
        language: String?
    ) -> [ClipsmithSchemaV1.Snippet] {
        snippets.filter { snippet in
            let languageMatch = language == nil || snippet.language == language
            let textMatch = query.isEmpty
                || snippet.name.localizedCaseInsensitiveContains(query)
                || snippet.content.localizedCaseInsensitiveContains(query)
                || snippet.tags.contains { $0.localizedCaseInsensitiveContains(query) }
            return languageMatch && textMatch
        }
    }

    /// Lowercased names used by more than one snippet (names compared as
    /// stored, not trimmed).
    static func duplicateNames(_ names: [String]) -> Set<String> {
        var seen = Set<String>(), dupes = Set<String>()
        for name in names.map({ $0.lowercased() }) where !seen.insert(name).inserted {
            dupes.insert(name)
        }
        return dupes
    }

    /// The snippet a `[[name]]` reference opens: case-insensitive match,
    /// most recently updated wins.
    static func bestMatch(
        named name: String,
        in snippets: [ClipsmithSchemaV1.Snippet]
    ) -> ClipsmithSchemaV1.Snippet? {
        snippets
            .filter { $0.name.caseInsensitiveCompare(name) == .orderedSame }
            .max { $0.updatedAt < $1.updatedAt }
    }
}
