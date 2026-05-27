import Foundation
import Observation

// MARK: - AppLaunchViewModel

/// Pure-Swift observable view model for the App Launcher Bezel HUD.
///
/// Responsibilities:
/// - Maintains the app list (injected from AppScannerService) and the recent bundle ID list
/// - Provides instant fuzzy search with recency boost ranking (CONTEXT D-04, D-05)
/// - Provides navigation methods matching the PromptBezelViewModel pattern
/// - Exposes displayedApps as a cached, recomputed slice of apps
///
/// Tie-break rule (for Plan 03 human-verify predictability): when two apps have
/// the same boosted FuzzyMatcher score, they are sorted by `name.lowercased()`
/// ascending. This ensures deterministic ordering for repeated queries.
@Observable @MainActor
final class AppLaunchViewModel {

    // MARK: - State

    /// Full app list — set by AppScannerService after each scan.
    /// Setting this triggers recomputation of displayedApps.
    var apps: [AppEntry] = [] {
        didSet { recomputeDisplayedApps() }
    }

    /// Bundle IDs of recently launched apps, ordered most-recent-first.
    /// Set externally from AppScannerService before or after showing the bezel.
    /// Setting this triggers recomputation of displayedApps.
    var recentBundleIDs: [String] = [] {
        didSet { recomputeDisplayedApps() }
    }

    /// The current search query.
    /// Setting this resets selectedIndex to 0 and recomputes displayedApps.
    var searchText: String = "" {
        didSet {
            selectedIndex = 0
            recomputeDisplayedApps()
        }
    }

    /// The current selection index within displayedApps.
    var selectedIndex: Int = 0

    /// Wrap-around navigation setting — cached from UserDefaults in configureAndPresent().
    var wraparoundBezel: Bool = false

    /// True while AppScannerService is scanning. Mirrored from service by AppLaunchController.
    var isLoading: Bool = false

    /// Always true — app launcher is always in instant-search mode (CONTEXT D-03).
    var isSearchMode: Bool = true

    // MARK: - Phase 12: Command palette state

    /// The evaluated result for the current command-palette query. Nil when not in
    /// command palette mode or when the expression is invalid.
    var commandResult: CommandResult? = nil

    /// Published toast state for the SwiftUI overlay. Set to `true` by AppLaunchController
    /// in Plan 04 after the result is copied; the view animates it back to false.
    var showCopiedToast: Bool = false

    /// Injected by AppDelegate in Plan 04 after both services are wired. Nullable so
    /// existing tests and previews continue to work without it.
    var commandPaletteService: CommandPaletteService? = nil

    /// Pending debounced evaluation — cancelled on every keystroke so NSExpression
    /// is never called on a half-typed expression.
    private var evaluationTask: Task<Void, Never>?

    // MARK: - Command palette mode

    /// Returns `true` when the command-palette feature flag is enabled AND the current
    /// `searchText` starts with the configured prefix.
    ///
    /// This is a computed property, not stored, so runtime changes to the flag or prefix
    /// (via Settings) take effect immediately on the next `searchText` change (D-03).
    var isCommandPaletteMode: Bool {
        guard UserDefaults.standard.bool(forKey: AppSettingsKeys.commandPaletteEnabled) else {
            return false
        }
        let prefix = UserDefaults.standard.string(forKey: AppSettingsKeys.commandPalettePrefix) ?? "="
        guard !prefix.isEmpty else { return false }
        return searchText.hasPrefix(prefix)
    }

    // MARK: - Filtered cache

    /// Cached result of ranking/filtering apps by searchText and recentBundleIDs.
    /// Updated when `apps`, `recentBundleIDs`, or `searchText` changes.
    private(set) var displayedApps: [AppEntry] = []

    // MARK: - Private helpers

    /// The current command-palette prefix from UserDefaults (defaults to "=").
    ///
    /// Used to compute the query payload by dropping the correct number of characters
    /// from `searchText`. A private computed property keeps the drop length correct
    /// even if the prefix is multi-char in future.
    private var currentPrefix: String {
        UserDefaults.standard.string(forKey: AppSettingsKeys.commandPalettePrefix) ?? "="
    }

    // MARK: - Ranking

    /// Recomputes `displayedApps` from current state.
    ///
    /// Ranking rules:
    /// - Command palette mode (Phase 12): short-circuit — evaluate the query and clear the app list.
    /// - Empty query (D-04): return up to 5 most recent apps in recency order.
    /// - Non-empty query (D-05): FuzzyMatcher score + 0.1 recency boost for apps
    ///   whose bundleID is in `recentBundleIDs`. Sorted score-descending, then
    ///   name-ascending for equal scores.
    func recomputeDisplayedApps() {
        // Phase 12 short-circuit: when in command palette mode, debounce evaluation
        // so NSExpression never sees a half-typed expression (D-01).
        if isCommandPaletteMode {
            let prefix = currentPrefix
            let queryPayload = String(searchText.dropFirst(prefix.count))
            displayedApps = []

            evaluationTask?.cancel()

            guard !queryPayload.isEmpty else {
                commandResult = nil
                return
            }

            let service = commandPaletteService
            evaluationTask = Task { @MainActor [weak self] in
                guard let self else { return }
                do { try await Task.sleep(nanoseconds: 300_000_000) } catch { return }
                let result = service?.evaluate(queryPayload)
                // Show valid results immediately; nil (invalid) only after the pause.
                self.commandResult = result
            }
            return
        }
        // When leaving command palette mode, clear any stale result so the view
        // doesn't flash the previous evaluation while the app list repopulates.
        commandResult = nil

        let q = searchText.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else {
            let recents = recentApps()
            displayedApps = recents.isEmpty
                ? Array(apps.sorted { $0.name.lowercased() < $1.name.lowercased() }.prefix(9))
                : recents
            return
        }

        let recentIDs = Set(recentBundleIDs)
        let scored: [(AppEntry, Double)] = apps.compactMap { app in
            guard var score = FuzzyMatcher.score(app.name, query: q) else { return nil }
            if let bid = app.bundleID, recentIDs.contains(bid) { score += 0.1 }
            return (app, score)
        }
        // Sort by score descending; tie-break by lowercased name ascending.
        displayedApps = scored
            .sorted { lhs, rhs in
                if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
                return lhs.0.name.lowercased() < rhs.0.name.lowercased()
            }
            .map(\.0)
    }

    /// Returns up to 5 recently launched apps in recency order.
    /// Apps whose bundle ID is not in `apps` are dropped.
    private func recentApps() -> [AppEntry] {
        var result: [AppEntry] = []
        for id in recentBundleIDs.prefix(5) {
            if let app = apps.first(where: { $0.bundleID == id }) {
                result.append(app)
            }
        }
        return result
    }

    // MARK: - Computed Properties

    /// Returns the AppEntry at selectedIndex, or nil if displayedApps is empty or index is out of range.
    var currentApp: AppEntry? {
        let list = displayedApps
        guard !list.isEmpty, selectedIndex >= 0, selectedIndex < list.count else { return nil }
        return list[selectedIndex]
    }

    /// Returns "N of M" label for navigation, or empty string if displayedApps is empty.
    var navigationLabel: String {
        let list = displayedApps
        guard !list.isEmpty else { return "" }
        return "\(selectedIndex + 1) of \(list.count)"
    }

    // MARK: - Navigation

    /// Decrements selectedIndex by 1.
    /// When wraparoundBezel is enabled, wraps from index 0 to the last item.
    func navigateUp() {
        if wraparoundBezel {
            selectedIndex = selectedIndex > 0
                ? selectedIndex - 1
                : max(0, displayedApps.count - 1)
        } else {
            selectedIndex = max(0, selectedIndex - 1)
        }
    }

    /// Increments selectedIndex by 1.
    /// When wraparoundBezel is enabled, wraps from the last item back to 0.
    func navigateDown() {
        let last = max(0, displayedApps.count - 1)
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

    /// Sets selectedIndex to displayedApps.count - 1 (or 0 if empty).
    func navigateToLast() {
        selectedIndex = max(0, displayedApps.count - 1)
    }

    /// Decrements selectedIndex by 10, clamped at 0.
    func navigateUpTen() {
        selectedIndex = max(0, selectedIndex - 10)
    }

    /// Increments selectedIndex by 10, clamped at last index.
    func navigateDownTen() {
        let last = max(0, displayedApps.count - 1)
        selectedIndex = min(last, selectedIndex + 10)
    }

    /// Jumps to the given index, clamped to [0, displayedApps.count - 1].
    /// No-op if displayedApps is empty.
    func navigateTo(index: Int) {
        guard !displayedApps.isEmpty else { return }
        selectedIndex = max(0, min(index, displayedApps.count - 1))
    }
}
