import Foundation

/// Pure filtering for the Prompts browser section: chip row plus the
/// `#category text` / `#my` search syntax inherited from the prompt library.
nonisolated enum PromptFilter {

    enum Chip: Hashable, Sendable {
        case mine
        case category(String)

        var id: String {
            switch self {
            case .mine: return "mine"
            case .category(let category): return category
            }
        }

        init?(id: String) {
            guard !id.isEmpty else { return nil }
            self = id == "mine" ? .mine : .category(id)
        }
    }

    /// "My Prompts" first (only when any user-created prompt exists), then the
    /// distinct categories of library prompts sorted case-insensitively.
    static func options(in prompts: [ClipsmithSchemaV2.PromptLibraryItem]) -> [BrowserFilterOption] {
        var options: [BrowserFilterOption] = []
        if prompts.contains(where: \.isUserCreated) {
            options.append(BrowserFilterOption(id: Chip.mine.id, label: "My Prompts"))
        }
        let categories = Set(prompts.filter { !$0.isUserCreated }.map(\.category).filter { !$0.isEmpty })
        options += categories
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            .map { BrowserFilterOption(id: $0, label: $0) }
        return options
    }

    /// Text query (with `#category` / `#my` prefix support) AND the chip.
    static func apply(
        _ prompts: [ClipsmithSchemaV2.PromptLibraryItem],
        query: String,
        chip: Chip?
    ) -> [ClipsmithSchemaV2.PromptLibraryItem] {
        byQuery(prompts, query: query).filter { prompt in
            switch chip {
            case nil: return true
            case .mine: return prompt.isUserCreated
            case .category(let category): return !prompt.isUserCreated && prompt.category == category
            }
        }
    }

    private static func byQuery(
        _ prompts: [ClipsmithSchemaV2.PromptLibraryItem],
        query: String
    ) -> [ClipsmithSchemaV2.PromptLibraryItem] {
        guard !query.isEmpty else { return prompts }
        let trimmed = query.trimmingCharacters(in: .whitespaces)

        if trimmed.hasPrefix("#") {
            let withoutHash = String(trimmed.dropFirst())
            let parts = withoutHash.split(separator: " ", maxSplits: 1)
            let categoryFilter = parts.isEmpty ? "" : String(parts[0]).lowercased()
            let textSearch = parts.count > 1 ? String(parts[1]).trimmingCharacters(in: .whitespaces) : ""
            let isMyPrompts = categoryFilter == "my" || "my prompts".hasPrefix(categoryFilter)

            return prompts.filter { prompt in
                let categoryMatches = isMyPrompts
                    ? prompt.isUserCreated
                    : prompt.category.lowercased().hasPrefix(categoryFilter)
                guard categoryMatches else { return false }
                if textSearch.isEmpty { return true }
                return prompt.title.localizedCaseInsensitiveContains(textSearch)
                    || prompt.content.localizedCaseInsensitiveContains(textSearch)
            }
        }

        return prompts.filter { prompt in
            prompt.title.localizedCaseInsensitiveContains(trimmed)
            || prompt.content.localizedCaseInsensitiveContains(trimmed)
            || prompt.category.localizedCaseInsensitiveContains(trimmed)
        }
    }
}
