import AppKit
import Foundation
import Observation
import SwiftData

// MARK: - ClippingInfo

/// Value type carrying clipping data across the View→ViewModel boundary.
///
/// Carries a PersistentIdentifier so BezelController can delete clippings
/// by ID without exposing the @Model object across actor boundaries.
/// Also carries source app metadata for future display (Bug #14, Wave 4).
struct ClippingInfo: Sendable {
    let id: PersistentIdentifier
    let content: String
    let sourceAppName: String?
    let sourceAppBundleURL: String?
    let timestamp: Date
}

// MARK: - BezelViewModel

/// Pure-Swift observable view model for the Bezel HUD.
///
/// Responsibilities:
/// - Maintains the selected index within the current clippings list
/// - Filters clippings by search text (case-insensitive)
/// - Provides navigation methods (up/down/first/last/+10/-10/navigateTo)
/// - Supports removeCurrentClipping() for Delete key action (Bug #11)
///
/// Design: Uses [ClippingInfo] instead of [String] so that:
/// - BezelController can delete by PersistentIdentifier (Bug #11)
/// - Source app can be displayed in Wave 4 (Bug #14)
/// BezelView maps @Query results to [ClippingInfo] before setting viewModel.clippings.
@Observable @MainActor
final class BezelViewModel {

    // MARK: - State

    /// The full list of clipping info objects. Set externally by BezelView when @Query updates.
    var clippings: [ClippingInfo] = [] {
        didSet { recomputeFilteredClippings() }
    }

    /// The current selection index within filteredClippings.
    var selectedIndex: Int = 0

    /// Whether the bezel was opened in search mode (via activateSearch hotkey).
    /// When false, the search field is hidden and all keys navigate clippings.
    var isSearchMode: Bool = false

    /// The current search query. Setting this resets selectedIndex to 0 and recomputes the filter cache.
    var searchText: String = "" {
        didSet {
            selectedIndex = 0
            recomputeFilteredClippings()
        }
    }

    /// Whether to wrap navigation past the end/start of the list.
    /// Cached from UserDefaults to avoid per-keystroke I/O.
    var wraparoundBezel: Bool = false

    /// Whether the keyboard shortcut cheat sheet overlay is visible.
    /// Toggled by pressing `?` when not in search mode.
    var isShowingCheatSheet: Bool = false

    /// Cache for app icons keyed by bundle path. Lives on the view model (not @State)
    /// so that lookups from the view body do not mutate SwiftUI state mid-render.
    var iconCache: [String: NSImage] = [:]

    // MARK: - Filtered cache

    /// Cached result of filtering clippings by searchText.
    /// Updated when `clippings` or `searchText` changes.
    private(set) var filteredClippings: [ClippingInfo] = []

    /// Recomputes `filteredClippings` from current `clippings` and `searchText`.
    ///
    /// When `searchText` is empty, returns all clippings in original order.
    /// When `searchText` is set, performs fuzzy (character-subsequence) matching
    /// and ranks results by match quality (best match first).
    func recomputeFilteredClippings() {
        guard !searchText.isEmpty else {
            filteredClippings = clippings
            return
        }
        let q = searchText
        let scored: [(ClippingInfo, Double)] = clippings.compactMap { info in
            guard let s = FuzzyMatcher.score(info.content, query: q) else { return nil }
            return (info, s)
        }
        filteredClippings = scored.sorted { $0.1 > $1.1 }.map(\.0)
    }

    /// Returns the clipping content string at selectedIndex, or nil if filteredClippings is empty.
    /// Convenience for paste operations — derived from currentClippingInfo?.content.
    var currentClipping: String? {
        currentClippingInfo?.content
    }

    /// Returns the ClippingInfo at selectedIndex, or nil if filteredClippings is empty.
    var currentClippingInfo: ClippingInfo? {
        let filtered = filteredClippings
        guard !filtered.isEmpty, selectedIndex >= 0, selectedIndex < filtered.count else { return nil }
        return filtered[selectedIndex]
    }

    /// Returns "N of M" label for navigation, or empty string if no clippings.
    var navigationLabel: String {
        let filtered = filteredClippings
        guard !filtered.isEmpty else { return "" }
        return "\(selectedIndex + 1) of \(filtered.count)"
    }

    // MARK: - Navigation

    /// Decrements selectedIndex by 1.
    /// When wraparoundBezel is enabled, wraps from index 0 to the last item.
    /// Otherwise clamps at 0 (existing behaviour).
    func navigateUp() {
        if wraparoundBezel {
            selectedIndex = selectedIndex > 0
                ? selectedIndex - 1
                : max(0, filteredClippings.count - 1)
        } else {
            selectedIndex = max(0, selectedIndex - 1)
        }
    }

    /// Increments selectedIndex by 1.
    /// When wraparoundBezel is enabled, wraps from the last item back to 0.
    /// Otherwise clamps at the last index (existing behaviour).
    func navigateDown() {
        let last = max(0, filteredClippings.count - 1)
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

    /// Sets selectedIndex to filteredClippings.count - 1 (or 0 if empty).
    func navigateToLast() {
        selectedIndex = max(0, filteredClippings.count - 1)
    }

    /// Decrements selectedIndex by 10, clamped at 0.
    func navigateUpTen() {
        selectedIndex = max(0, selectedIndex - 10)
    }

    /// Increments selectedIndex by 10, clamped at last index.
    func navigateDownTen() {
        let last = max(0, filteredClippings.count - 1)
        selectedIndex = min(last, selectedIndex + 10)
    }

    /// Jumps to the given index, clamped to [0, filteredClippings.count - 1].
    /// No-op if filteredClippings is empty.
    func navigateTo(index: Int) {
        guard !filteredClippings.isEmpty else { return }
        selectedIndex = max(0, min(index, filteredClippings.count - 1))
    }

    // MARK: - Delete

    /// Removes the clipping at selectedIndex from the local array (by PersistentIdentifier).
    /// Also clamps selectedIndex if it becomes out of bounds after removal.
    /// The caller is responsible for also deleting from SwiftData (via ClipboardStore).
    func removeCurrentClipping() {
        let filtered = filteredClippings
        guard !filtered.isEmpty, selectedIndex < filtered.count else { return }
        let info = filtered[selectedIndex]
        clippings.removeAll { $0.id == info.id }
        // Clamp selectedIndex after removal
        if selectedIndex >= filteredClippings.count {
            selectedIndex = max(0, filteredClippings.count - 1)
        }
    }
}
