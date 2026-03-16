import Foundation
import Observation
import OSLog

private let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.github.haad.clipsmith",
    category: "DocBezelViewModel"
)

/// Result item combining a docset source with a search entry.
struct DocSearchResult: Identifiable, Sendable {
    var id: String { "\(docsetID)-\(entry.id)" }
    let docsetID: String
    let docsetName: String
    let entry: DocEntry
    /// Full path to the HTML file for WKWebView loading.
    let htmlURL: URL?
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
                return
            }
            searchTask = Task {
                try? await Task.sleep(for: .milliseconds(150))  // debounce
                guard !Task.isCancelled else { return }
                await performSearch(query: query)
            }
        }
    }

    var selectedIndex: Int = 0
    var filteredResults: [DocSearchResult] = []
    var isSearching: Bool = false
    var wraparoundBezel: Bool = false

    private var searchTask: Task<Void, Never>?

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

    func performSearch(query: String) async {
        guard let searchService, let managerService else { return }
        isSearching = true
        do {
            let docsets = managerService.enabledDocsets
            let results = try await searchService.searchAll(query: query, docsets: docsets)
            filteredResults = results.map { pair in
                let htmlURL = pair.docset.localPath?
                    .appendingPathComponent("Contents/Resources/Documents")
                    .appendingPathComponent(pair.entry.path)
                return DocSearchResult(
                    docsetID: pair.docset.id,
                    docsetName: pair.docset.displayName,
                    entry: pair.entry,
                    htmlURL: htmlURL
                )
            }
        } catch {
            logger.error("Doc search failed: \(error.localizedDescription, privacy: .public)")
            filteredResults = []
        }
        isSearching = false
    }

    // MARK: - Navigation (mirrors PromptBezelViewModel exactly)

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
