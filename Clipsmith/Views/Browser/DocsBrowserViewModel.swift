import Foundation
import Observation
import OSLog

private let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.github.haad.clipsmith",
    category: "DocsBrowserViewModel"
)

/// Result item combining a doc source with a search entry.
struct DocSearchResult: Identifiable, Sendable {
    var id: String { "\(docsetID)/\(entry.path)" }
    let docsetID: String
    let docsetName: String
    let entry: DocEntry
    let score: Double
}

@Observable @MainActor
final class DocsBrowserViewModel {

    // MARK: - Dependencies (injected by the hosting view)
    var searchService: DocsetSearchService?
    var managerService: DocsetManagerService?

    // MARK: - State
    var searchText: String = "" {
        didSet {
            selectedIndex = 0
            searchTask?.cancel()
            let query = searchText.trimmingCharacters(in: .whitespaces)
            guard !query.isEmpty else {
                filteredResults = []
                activeDocFilter = nil
                activeDocFilterNames = []
                return
            }
            searchTask = Task {
                try? await Task.sleep(for: .milliseconds(150))  // debounce
                guard !Task.isCancelled else { return }
                performSearch(query: query)
            }
        }
    }

    var selectedIndex: Int = 0 {
        didSet { loadHTMLForCurrentResult() }
    }
    var filteredResults: [DocSearchResult] = []
    var isSearching: Bool = false
    var wraparoundBezel: Bool = false

    /// Sidebar selection; nil = search every enabled docset. Changing it
    /// re-runs the current query immediately.
    var selectedDocsetID: String? {
        didSet {
            guard !isApplyingPrefixSelection, selectedDocsetID != oldValue else { return }
            let query = searchText.trimmingCharacters(in: .whitespaces)
            if query.isEmpty {
                filteredResults = []
            } else {
                performSearch(query: query)
            }
        }
    }

    /// Entry counts per docset slug for the sidebar, filled by `loadEntryCounts()`.
    var entryCounts: [String: Int] = [:]

    /// Set while `performSearch` moves the sidebar selection for a `prefix:` query,
    /// so the `selectedDocsetID` observer does not start a second search.
    private var isApplyingPrefixSelection = false
    private var entryCountsTask: Task<Void, Never>?

    /// Active doc filter prefix (e.g. "python" from "python:map")
    var activeDocFilter: String?
    /// Display names of docs matching the active filter
    var activeDocFilterNames: [String] = []

    /// HTML content for the currently selected result (loaded from db.json).
    var currentHTML: String?

    private var searchTask: Task<Void, Never>?
    private var htmlLoadTask: Task<Void, Never>?

    // MARK: - Computed

    var currentResult: DocSearchResult? {
        guard !filteredResults.isEmpty,
              selectedIndex >= 0,
              selectedIndex < filteredResults.count else { return nil }
        return filteredResults[selectedIndex]
    }

    var navigationLabel: String {
        guard !filteredResults.isEmpty else { return "" }
        return "\(selectedIndex + 1) of \(filteredResults.count)"
    }

    var selectedDocset: DocsetInfo? {
        guard let selectedDocsetID else { return nil }
        return managerService?.enabledDocsets.first { $0.id == selectedDocsetID }
    }

    // MARK: - Entry points

    /// Prefill from the docs hotkey: trims the selection, keeps the docset
    /// scope, and restarts from the first result. Whitespace-only clears the field.
    func open(withQuery query: String?) {
        searchText = query?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        selectedIndex = 0
    }

    /// Drops the sidebar scope when its docset was disabled or deleted in Settings,
    /// so the footer's "All docsets" and the search agree.
    func reconcileSelection() {
        guard let id = selectedDocsetID,
              let managerService,
              !managerService.enabledDocsets.contains(where: { $0.id == id }) else { return }
        selectedDocsetID = nil
    }

    /// Loads each enabled docset's index off the main actor and records its entry count.
    func loadEntryCounts() {
        guard let searchService, let managerService else { return }
        let docsets = managerService.enabledDocsets
        entryCountsTask?.cancel()
        entryCountsTask = Task {
            let counts = await Task.detached {
                var counts: [String: Int] = [:]
                for docset in docsets {
                    guard let indexPath = docset.indexPath,
                          let entries = try? searchService.loadIndex(slug: docset.id, from: indexPath) else { continue }
                    counts[docset.id] = entries.count
                }
                return counts
            }.value
            guard !Task.isCancelled else { return }
            entryCounts = counts
        }
    }

    /// Which docsets a query runs against, and whether the sidebar selection should move.
    ///
    /// - `prefix:` present → the first matching docset (selection moves to it), or
    ///   nothing when no installed docset matches (selection untouched).
    /// - no prefix, docset selected → that docset (or nothing if it vanished).
    /// - neither → every docset.
    ///
    /// `newSelection` is `.some(id)` to move the selection, `nil` to leave it alone.
    nonisolated static func targetDocsets(
        selectedDocsetID: String?,
        parsedFilter: String?,
        from docsets: [DocsetInfo],
        using service: DocsetSearchService
    ) -> (docsets: [DocsetInfo], newSelection: String??) {
        if let parsedFilter {
            let matching = service.matchingDocsets(filter: parsedFilter, from: docsets)
            guard let first = matching.first else { return ([], nil) }
            return ([first], .some(first.id))
        }
        if let selectedDocsetID {
            let selected = docsets.filter { $0.id == selectedDocsetID }
            return (selected, nil)
        }
        return (docsets, nil)
    }

    // MARK: - Search

    func performSearch(query: String) {
        guard let searchService, let managerService else { return }
        isSearching = true

        // Parse doc prefix filter (e.g. "python:map")
        let parsed = searchService.parseQuery(query)
        activeDocFilter = parsed.docFilter

        // Update filter display names
        if let filter = parsed.docFilter {
            let matching = searchService.matchingDocsets(filter: filter, from: managerService.enabledDocsets)
            activeDocFilterNames = matching.map(\.displayName)
        } else {
            activeDocFilterNames = []
        }

        let searchQuery = parsed.query
        guard !searchQuery.isEmpty else {
            filteredResults = []
            isSearching = false
            return
        }

        let target = Self.targetDocsets(
            selectedDocsetID: selectedDocsetID,
            parsedFilter: parsed.docFilter,
            from: managerService.enabledDocsets,
            using: searchService
        )
        if case .some(let id) = target.newSelection, id != selectedDocsetID {
            isApplyingPrefixSelection = true
            selectedDocsetID = id
            isApplyingPrefixSelection = false
        }

        do {
            let results = try searchService.searchAll(query: searchQuery, docFilter: nil, docsets: target.docsets)
            filteredResults = results.map { (docset, entry, score) in
                DocSearchResult(
                    docsetID: docset.id,
                    docsetName: docset.displayName,
                    entry: entry,
                    score: score
                )
            }
        } catch {
            logger.error("Doc search failed: \(error.localizedDescription, privacy: .public)")
            filteredResults = []
        }
        isSearching = false
        loadHTMLForCurrentResult()
    }

    // MARK: - HTML content loading

    /// Load HTML for the currently selected result from db.json on disk.
    private func loadHTMLForCurrentResult() {
        htmlLoadTask?.cancel()
        guard let result = currentResult else {
            currentHTML = nil
            return
        }
        let slug = result.docsetID
        let path = result.entry.path
        let resultID = result.id

        htmlLoadTask = Task {
            let html = await Task.detached {
                Self.loadHTMLContent(slug: slug, path: path)
            }.value
            // Only update if still showing the same result
            if self.currentResult?.id == resultID {
                self.currentHTML = html
            }
        }
    }

    /// Read a single entry's HTML from db.json on disk.
    /// db.json is a JSON object mapping path → HTML string.
    private nonisolated static func loadHTMLContent(slug: String, path: String) -> String? {
        let dbURL = DocsetInfo.docDirectory(for: slug).appendingPathComponent("db.json")
        guard let data = try? Data(contentsOf: dbURL) else { return nil }
        guard let dict = try? JSONSerialization.jsonObject(with: data) as? [String: String] else { return nil }
        // Strip #fragment from path — db.json keys are page paths without fragments.
        // e.g. "pipelines#index-_0021" → look up "pipelines"
        let pagePath = path.split(separator: "#", maxSplits: 1).first.map(String.init) ?? path
        return dict[pagePath]
    }

    // MARK: - Navigation

    func navigateUp() {
        if wraparoundBezel {
            selectedIndex = selectedIndex > 0
                ? selectedIndex - 1
                : max(0, filteredResults.count - 1)
        } else {
            selectedIndex = max(0, selectedIndex - 1)
        }
    }

    func navigateDown() {
        let last = max(0, filteredResults.count - 1)
        if wraparoundBezel {
            selectedIndex = selectedIndex < last ? selectedIndex + 1 : 0
        } else {
            selectedIndex = min(last, selectedIndex + 1)
        }
    }

    func navigateToFirst() { selectedIndex = 0 }

    func navigateToLast() {
        selectedIndex = max(0, filteredResults.count - 1)
    }

    func navigateUpTen() {
        selectedIndex = max(0, selectedIndex - 10)
    }

    func navigateDownTen() {
        let last = max(0, filteredResults.count - 1)
        selectedIndex = min(last, selectedIndex + 10)
    }

    func navigateTo(index: Int) {
        guard !filteredResults.isEmpty else { return }
        selectedIndex = max(0, min(index, filteredResults.count - 1))
    }
}
