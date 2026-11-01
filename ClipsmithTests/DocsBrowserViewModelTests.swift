import XCTest
@testable import Clipsmith

@MainActor
final class DocsBrowserViewModelTests: XCTestCase {
    private var viewModel: DocsBrowserViewModel!

    override func setUp() async throws {
        try await super.setUp()
        viewModel = DocsBrowserViewModel()
    }

    func testInitialState() {
        XCTAssertEqual(viewModel.searchText, "")
        XCTAssertEqual(viewModel.selectedIndex, 0)
        XCTAssertTrue(viewModel.filteredResults.isEmpty)
        XCTAssertNil(viewModel.currentResult)
        XCTAssertEqual(viewModel.navigationLabel, "")
    }

    func testNavigateDownClampsAtEnd() {
        viewModel.filteredResults = makeResults(count: 3)
        viewModel.selectedIndex = 2
        viewModel.navigateDown()
        XCTAssertEqual(viewModel.selectedIndex, 2)
    }

    func testNavigateDownWraparound() {
        viewModel.wraparoundBezel = true
        viewModel.filteredResults = makeResults(count: 3)
        viewModel.selectedIndex = 2
        viewModel.navigateDown()
        XCTAssertEqual(viewModel.selectedIndex, 0)
    }

    func testNavigateUpClampsAtStart() {
        viewModel.filteredResults = makeResults(count: 3)
        viewModel.selectedIndex = 0
        viewModel.navigateUp()
        XCTAssertEqual(viewModel.selectedIndex, 0)
    }

    func testNavigateUpWraparound() {
        viewModel.wraparoundBezel = true
        viewModel.filteredResults = makeResults(count: 3)
        viewModel.selectedIndex = 0
        viewModel.navigateUp()
        XCTAssertEqual(viewModel.selectedIndex, 2)
    }

    func testNavigateToFirst() {
        viewModel.filteredResults = makeResults(count: 5)
        viewModel.selectedIndex = 3
        viewModel.navigateToFirst()
        XCTAssertEqual(viewModel.selectedIndex, 0)
    }

    func testNavigateToLast() {
        viewModel.filteredResults = makeResults(count: 5)
        viewModel.navigateToLast()
        XCTAssertEqual(viewModel.selectedIndex, 4)
    }

    func testNavigationLabel() {
        viewModel.filteredResults = makeResults(count: 3)
        viewModel.selectedIndex = 1
        XCTAssertEqual(viewModel.navigationLabel, "2 of 3")
    }

    func testCurrentResult() {
        let results = makeResults(count: 3)
        viewModel.filteredResults = results
        viewModel.selectedIndex = 1
        XCTAssertEqual(viewModel.currentResult?.entry.name, "Entry 1")
    }

    // MARK: - Docset scoping

    private func docset(_ id: String, _ name: String) -> DocsetInfo {
        DocsetInfo(id: id, displayName: name, release: nil, dbSize: 0, homeURL: nil, codeURL: nil,
                   docType: nil, isEnabled: true, isDownloaded: true)
    }
    private var all: [DocsetInfo] { [docset("go", "Go"), docset("django", "Django"), docset("mongoose", "Mongoose")] }

    func testSelectedDocsetScopesExactlyOne() {
        let r = DocsBrowserViewModel.targetDocsets(selectedDocsetID: "go", parsedFilter: nil, from: all, using: DocsetSearchService())
        XCTAssertEqual(r.docsets.map(\.id), ["go"])
        XCTAssertTrue(r.newSelection == nil, "selection must not move")
    }

    func testPrefixPicksFirstMatchAndMovesSelection() {
        let r = DocsBrowserViewModel.targetDocsets(selectedDocsetID: nil, parsedFilter: "go", from: all, using: DocsetSearchService())
        XCTAssertEqual(r.docsets.count, 1)
        XCTAssertEqual(r.newSelection, .some(r.docsets.first?.id))
    }

    /// Review Focus 2: prefix for a docset that is not installed.
    func testPrefixWithNoMatchKeepsSelection() {
        let r = DocsBrowserViewModel.targetDocsets(selectedDocsetID: "go", parsedFilter: "rust", from: all, using: DocsetSearchService())
        XCTAssertTrue(r.docsets.isEmpty)
        XCTAssertTrue(r.newSelection == nil, "selection must not move")
    }

    func testNoSelectionNoPrefixSearchesAll() {
        let r = DocsBrowserViewModel.targetDocsets(selectedDocsetID: nil, parsedFilter: nil, from: all, using: DocsetSearchService())
        XCTAssertEqual(r.docsets.count, 3)
    }

    /// Review Focus 1: hotkey with a whitespace-only selection.
    func testOpenWithQueryWhitespaceClearsSearch() {
        viewModel.selectedDocsetID = "go"
        viewModel.open(withQuery: "   \n")
        XCTAssertEqual(viewModel.searchText, "")
        XCTAssertEqual(viewModel.selectedDocsetID, "go")
        XCTAssertTrue(viewModel.filteredResults.isEmpty)
    }

    func testOpenWithQueryTrimsAndKeepsSelection() {
        viewModel.selectedDocsetID = "go"
        viewModel.open(withQuery: "  fmt ")
        XCTAssertEqual(viewModel.searchText, "fmt")
        XCTAssertEqual(viewModel.selectedDocsetID, "go")
    }

    /// Review fix: a docset disabled or deleted in Settings must not leave a stale scope.
    func testReconcileSelectionClearsVanishedDocset() {
        let manager = DocsetManagerService()
        manager.docsets = all
        viewModel.managerService = manager
        viewModel.selectedDocsetID = "go"
        viewModel.reconcileSelection()
        XCTAssertEqual(viewModel.selectedDocsetID, "go")

        manager.docsets = all.filter { $0.id != "go" }
        viewModel.reconcileSelection()
        XCTAssertNil(viewModel.selectedDocsetID)
    }

    // MARK: - Helpers

    private func makeResults(count: Int) -> [DocSearchResult] {
        (0..<count).map { i in
            DocSearchResult(
                docsetID: "test",
                docsetName: "Test",
                entry: DocEntry(slug: "test", name: "Entry \(i)", type: "Class", path: "entry\(i)"),
                score: 1.0
            )
        }
    }
}
