import Foundation
import Observation

// MARK: - PromptBezelViewModel

/// Pure-Swift observable view model for the Prompt Library Bezel HUD.
///
/// Responsibilities:
/// - Maintains the selected category and selected index within filtered prompts
/// - Supports Tab-key category cycling through the canonical category list
/// - Parses #category search syntax (e.g., "#coding review") to override the
///   selected category filter and search within it
/// - Provides navigation methods mirroring BezelViewModel (up/down/first/last/+10/-10)
/// - Exposes filteredPrompts as a cached, recomputed slice of all prompts
///
/// Designed for the 3-second flow: hotkey → type/navigate → Enter → pasted.
@Observable @MainActor
final class PromptBezelViewModel {

    // MARK: - Category constants

    /// Canonical ordered list of categories for Tab cycling.
    static let allCategories: [String] = ["All", "coding", "writing", "analysis", "creative", "My Prompts"]

    // MARK: - State

    /// The full list of prompt info objects. Set externally by PromptBezelView when @Query updates.
    var prompts: [PromptInfo] = [] {
        didSet { recomputeFilteredPrompts() }
    }

    /// The current selection index within filteredPrompts.
    var selectedIndex: Int = 0

    /// The current search query.
    /// Setting this resets selectedIndex to 0 and recomputes the filter cache.
    var searchText: String = "" {
        didSet {
            selectedIndex = 0
            recomputeFilteredPrompts()
        }
    }

    /// Prompt bezel is always in search mode — search field always visible.
    var isSearchMode: Bool = true

    /// The currently selected category tab. One of allCategories values.
    var selectedCategory: String = "All" {
        didSet {
            selectedIndex = 0
            recomputeFilteredPrompts()
        }
    }

    /// Whether to wrap navigation past the end/start of the list.
    /// Cached from UserDefaults to avoid per-keystroke I/O.
    var wraparoundBezel: Bool = false

    // MARK: - Filtered cache

    /// Cached result of filtering prompts by selectedCategory and searchText.
    /// Updated when `prompts`, `searchText`, or `selectedCategory` changes.
    private(set) var filteredPrompts: [PromptInfo] = []

    /// Recomputes `filteredPrompts` from current state.
    ///
    /// Logic:
    /// 1. Start with all prompts
    /// 2. Apply selectedCategory filter (unless "All")
    /// 3. Parse searchText for #category prefix override
    /// 4. Apply text search on remaining query
    func recomputeFilteredPrompts() {
        var result = prompts

        // Check for #category search syntax in searchText
        let trimmed = searchText.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("#") {
            // Parse: "#category remaining text"
            let withoutHash = String(trimmed.dropFirst())
            let parts = withoutHash.split(separator: " ", maxSplits: 1)
            let categoryToken = parts.isEmpty ? "" : String(parts[0]).lowercased()
            let remainingText = parts.count > 1 ? String(parts[1]).trimmingCharacters(in: .whitespaces) : ""

            // Override selectedCategory filter with the #category token
            if !categoryToken.isEmpty {
                if categoryToken == "my prompts" || categoryToken == "myprompts" {
                    result = result.filter { $0.isUserCreated }
                } else {
                    result = result.filter { $0.category.lowercased() == categoryToken }
                }
            }

            // Apply remaining text search (fuzzy, ranked by match quality)
            if !remainingText.isEmpty {
                let q = remainingText
                let scored: [(PromptInfo, Double)] = result.compactMap { info in
                    let titleScore = FuzzyMatcher.score(info.title, query: q) ?? -1
                    let contentScore = FuzzyMatcher.score(info.content, query: q) ?? -1
                    let best = max(titleScore, contentScore)
                    guard best >= 0 else { return nil }
                    return (info, best)
                }
                result = scored.sorted { $0.1 > $1.1 }.map(\.0)
            }
        } else {
            // Apply selectedCategory filter
            if selectedCategory != "All" {
                if selectedCategory == "My Prompts" {
                    result = result.filter { $0.isUserCreated }
                } else {
                    result = result.filter { $0.category == selectedCategory }
                }
            }

            // Apply plain text search (fuzzy, ranked by match quality)
            if !trimmed.isEmpty {
                let q = trimmed
                let scored: [(PromptInfo, Double)] = result.compactMap { info in
                    let titleScore = FuzzyMatcher.score(info.title, query: q) ?? -1
                    let contentScore = FuzzyMatcher.score(info.content, query: q) ?? -1
                    let best = max(titleScore, contentScore)
                    guard best >= 0 else { return nil }
                    return (info, best)
                }
                result = scored.sorted { $0.1 > $1.1 }.map(\.0)
            }
        }

        filteredPrompts = result
    }

    // MARK: - Computed properties

    /// Returns the PromptInfo at selectedIndex, or nil if filteredPrompts is empty.
    var currentPrompt: PromptInfo? {
        let filtered = filteredPrompts
        guard !filtered.isEmpty, selectedIndex >= 0, selectedIndex < filtered.count else { return nil }
        return filtered[selectedIndex]
    }

    /// Returns "N of M" label for navigation, or empty string if no prompts.
    var navigationLabel: String {
        let filtered = filteredPrompts
        guard !filtered.isEmpty else { return "" }
        return "\(selectedIndex + 1) of \(filtered.count)"
    }

    /// Returns a displayable category name for the header.
    var categoryLabel: String {
        switch selectedCategory {
        case "All":          return "All Prompts"
        case "My Prompts":   return "My Prompts"
        default:
            // Capitalize first letter of category name
            return selectedCategory.prefix(1).uppercased() + selectedCategory.dropFirst()
        }
    }

    // MARK: - Category cycling (Tab key)

    /// Cycles selectedCategory to the next in allCategories, wrapping from the last back to "All".
    func cycleCategory() {
        let categories = Self.allCategories
        if let currentIdx = categories.firstIndex(of: selectedCategory) {
            let nextIdx = (currentIdx + 1) % categories.count
            selectedCategory = categories[nextIdx]
        } else {
            selectedCategory = "All"
        }
    }

    // MARK: - Navigation

    /// Decrements selectedIndex by 1.
    /// When wraparoundBezel is enabled, wraps from index 0 to the last item.
    func navigateUp() {
        if wraparoundBezel {
            selectedIndex = selectedIndex > 0
                ? selectedIndex - 1
                : max(0, filteredPrompts.count - 1)
        } else {
            selectedIndex = max(0, selectedIndex - 1)
        }
    }

    /// Increments selectedIndex by 1.
    /// When wraparoundBezel is enabled, wraps from the last item back to 0.
    func navigateDown() {
        let last = max(0, filteredPrompts.count - 1)
        if wraparoundBezel {
            selectedIndex = selectedIndex < last ? selectedIndex + 1 : 0
        } else {
            selectedIndex = min(last, selectedIndex + 1)
        }
    }

    /// Sets selectedIndex to 0.
    func navigateToFirst() {
        selectedIndex = 0
    }

    /// Sets selectedIndex to filteredPrompts.count - 1 (or 0 if empty).
    func navigateToLast() {
        selectedIndex = max(0, filteredPrompts.count - 1)
    }

    /// Decrements selectedIndex by 10, clamped at 0.
    func navigateUpTen() {
        selectedIndex = max(0, selectedIndex - 10)
    }

    /// Increments selectedIndex by 10, clamped at last index.
    func navigateDownTen() {
        let last = max(0, filteredPrompts.count - 1)
        selectedIndex = min(last, selectedIndex + 10)
    }

    /// Jumps to the given index, clamped to [0, filteredPrompts.count - 1].
    /// No-op if filteredPrompts is empty.
    func navigateTo(index: Int) {
        guard !filteredPrompts.isEmpty else { return }
        selectedIndex = max(0, min(index, filteredPrompts.count - 1))
    }
}
