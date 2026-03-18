import XCTest
@testable import Clipsmith

@MainActor
final class DocBezelViewModelTests: XCTestCase {
    private var viewModel: DocBezelViewModel!

    override func setUp() {
        viewModel = DocBezelViewModel()
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
