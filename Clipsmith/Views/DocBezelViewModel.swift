import Foundation
import Observation
import OSLog

private let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.github.haad.clipsmith",
    category: "DocBezelViewModel"
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
final class DocBezelViewModel {

    // MARK: - Dependencies (injected by DocBezelController)
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

        do {
            let docsets = managerService.enabledDocsets
            let results = try searchService.searchAll(query: searchQuery, docFilter: parsed.docFilter, docsets: docsets)
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
