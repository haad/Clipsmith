import XCTest
import SwiftData
@testable import Clipsmith

/// Unit tests for BezelViewModel navigation, search, and delete logic.
///
/// BezelViewModel uses [ClippingInfo] (with PersistentIdentifier).
/// Tests use makeClippingInfos() to obtain valid PersistentIdentifiers via
/// an in-memory SwiftData container.
@MainActor
final class BezelViewModelTests: XCTestCase {

    // MARK: - Helpers

    /// Creates an in-memory container and maps strings to ClippingInfo with valid PersistentIdentifiers.
    private func makeClippingInfos(_ strings: [String]) throws -> [ClippingInfo] {
        let container = try makeTestContainer()
        let context = container.mainContext
        return strings.map { str in
            let c = ClipsmithSchemaV1.Clipping(content: str)
            context.insert(c)
            try! context.save()
            return ClippingInfo(
                id: c.persistentModelID,
                content: str,
                sourceAppName: nil,
                sourceAppBundleURL: nil,
                timestamp: c.timestamp
            )
        }
    }

    private func makeViewModel(clippings: [String] = []) throws -> BezelViewModel {
        let vm = BezelViewModel()
        vm.clippings = try makeClippingInfos(clippings)
        return vm
    }

    // MARK: - navigateDown

    func testNavigateDownIncrementsIndex() throws {
        let vm = try makeViewModel(clippings: ["a", "b", "c"])
        XCTAssertEqual(vm.selectedIndex, 0)
        vm.navigateDown()
        XCTAssertEqual(vm.selectedIndex, 1)
    }

    func testNavigateDownNoOpAtLastItem() throws {
        let vm = try makeViewModel(clippings: ["a", "b", "c"])
        vm.selectedIndex = 2
        vm.navigateDown()
        XCTAssertEqual(vm.selectedIndex, 2, "navigateDown should be a no-op at the last item")
    }

    // MARK: - navigateUp

    func testNavigateUpDecrementsIndex() throws {
        let vm = try makeViewModel(clippings: ["a", "b", "c"])
        vm.selectedIndex = 2
        vm.navigateUp()
        XCTAssertEqual(vm.selectedIndex, 1)
    }

    func testNavigateUpNoOpAtFirstItem() throws {
        let vm = try makeViewModel(clippings: ["a", "b", "c"])
        XCTAssertEqual(vm.selectedIndex, 0)
        vm.navigateUp()
        XCTAssertEqual(vm.selectedIndex, 0, "navigateUp should be a no-op at index 0")
    }

    // MARK: - navigateToFirst

    func testNavigateToFirstSetsIndexToZero() throws {
        let vm = try makeViewModel(clippings: ["a", "b", "c"])
        vm.selectedIndex = 2
        vm.navigateToFirst()
        XCTAssertEqual(vm.selectedIndex, 0)
    }

    // MARK: - navigateToLast

    func testNavigateToLastSetsIndexToLastItem() throws {
        let vm = try makeViewModel(clippings: ["a", "b", "c"])
        vm.navigateToLast()
        XCTAssertEqual(vm.selectedIndex, 2)
    }

    func testNavigateToLastOnEmptyReturnsZero() throws {
        let vm = try makeViewModel(clippings: [])
        vm.navigateToLast()
        XCTAssertEqual(vm.selectedIndex, 0)
    }

    // MARK: - navigateUpTen

    func testNavigateUpTenDecrementsBy10() throws {
        let vm = try makeViewModel(clippings: Array(repeating: "x", count: 20))
        vm.selectedIndex = 15
        vm.navigateUpTen()
        XCTAssertEqual(vm.selectedIndex, 5)
    }

    func testNavigateUpTenClampsAtZero() throws {
        let vm = try makeViewModel(clippings: Array(repeating: "x", count: 20))
        vm.selectedIndex = 3
        vm.navigateUpTen()
        XCTAssertEqual(vm.selectedIndex, 0, "navigateUpTen should clamp at 0")
    }

    // MARK: - navigateDownTen

    func testNavigateDownTenIncrementsBy10() throws {
        let vm = try makeViewModel(clippings: Array(repeating: "x", count: 20))
        vm.selectedIndex = 5
        vm.navigateDownTen()
        XCTAssertEqual(vm.selectedIndex, 15)
    }

    func testNavigateDownTenClampsAtLastIndex() throws {
        let vm = try makeViewModel(clippings: Array(repeating: "x", count: 20))
        vm.selectedIndex = 15
        vm.navigateDownTen()
        XCTAssertEqual(vm.selectedIndex, 19, "navigateDownTen should clamp at last index")
    }

    // MARK: - filteredClippings

    func testFilteredClippingsReturnsAllWhenSearchTextEmpty() throws {
        let vm = try makeViewModel(clippings: ["hello", "world", "foo"])
        XCTAssertEqual(vm.filteredClippings.map(\.content), ["hello", "world", "foo"])
    }

    func testFilteredClippingsFiltersWhenSearchTextSet() throws {
        let vm = try makeViewModel(clippings: ["hello world", "foo bar", "hello foo"])
        vm.searchText = "hello"
        XCTAssertEqual(vm.filteredClippings.map(\.content), ["hello world", "hello foo"])
    }

    func testFilteredClippingsCaseInsensitive() throws {
        let vm = try makeViewModel(clippings: ["Hello", "HELLO", "world"])
        vm.searchText = "hello"
        XCTAssertEqual(vm.filteredClippings.map(\.content), ["Hello", "HELLO"])
    }

    func testFilteredClippingsReturnsEmptyWhenNoMatch() throws {
        let vm = try makeViewModel(clippings: ["foo", "bar"])
        vm.searchText = "xyz"
        XCTAssertTrue(vm.filteredClippings.isEmpty)
    }

    // MARK: - searchText resets selectedIndex

    func testSearchTextResetsSelectedIndex() throws {
        let vm = try makeViewModel(clippings: ["hello world", "foo", "hello bar"])
        vm.selectedIndex = 2
        vm.searchText = "hello"
        XCTAssertEqual(vm.selectedIndex, 0, "Setting searchText should reset selectedIndex to 0")
    }

    // MARK: - currentClipping

    func testCurrentClippingReturnsNilWhenEmpty() throws {
        let vm = try makeViewModel(clippings: [])
        XCTAssertNil(vm.currentClipping)
    }

    func testCurrentClippingReturnsItemAtSelectedIndex() throws {
        let vm = try makeViewModel(clippings: ["a", "b", "c"])
        vm.selectedIndex = 1
        XCTAssertEqual(vm.currentClipping, "b")
    }

    func testCurrentClippingWithSearchFilter() throws {
        let vm = try makeViewModel(clippings: ["hello world", "foo bar", "hello swift"])
        vm.searchText = "hello"
        // filteredClippings = ["hello world", "hello swift"]
        vm.selectedIndex = 1
        XCTAssertEqual(vm.currentClipping, "hello swift")
    }

    // MARK: - navigationLabel

    func testNavigationLabelEmptyWhenNoClippings() throws {
        let vm = try makeViewModel(clippings: [])
        XCTAssertEqual(vm.navigationLabel, "")
    }

    func testNavigationLabelFormat() throws {
        let vm = try makeViewModel(clippings: ["a", "b", "c"])
        vm.selectedIndex = 1
        XCTAssertEqual(vm.navigationLabel, "2 of 3")
    }

    // MARK: - navigateTo (new)

    func testNavigateToSetsSelectedIndex() throws {
        let vm = try makeViewModel(clippings: ["a", "b", "c", "d", "e"])
        vm.navigateTo(index: 2)
        XCTAssertEqual(vm.selectedIndex, 2, "navigateTo(index:) should set selectedIndex to 2")
    }

    func testNavigateToClampsBeyondLast() throws {
        let vm = try makeViewModel(clippings: ["a", "b", "c", "d", "e"])
        vm.navigateTo(index: 10)
        XCTAssertEqual(vm.selectedIndex, 4, "navigateTo beyond last index should clamp to last (4)")
    }

    func testNavigateToClampsBelowZero() throws {
        let vm = try makeViewModel(clippings: ["a", "b", "c", "d", "e"])
        vm.navigateTo(index: -1)
        XCTAssertEqual(vm.selectedIndex, 0, "navigateTo with negative index should clamp to 0")
    }

    func testNavigateToNoOpWhenEmpty() throws {
        let vm = try makeViewModel(clippings: [])
        vm.navigateTo(index: 2)
        XCTAssertEqual(vm.selectedIndex, 0, "navigateTo on empty clippings should be a no-op")
    }

    // MARK: - removeCurrentClipping (new)

    func testRemoveCurrentClippingRemovesAtSelectedIndex() throws {
        let vm = try makeViewModel(clippings: ["a", "b", "c"])
        vm.selectedIndex = 1
        vm.removeCurrentClipping()
        XCTAssertEqual(vm.clippings.count, 2, "removeCurrentClipping should remove one clipping")
        XCTAssertFalse(vm.clippings.map(\.content).contains("b"), "The item at selectedIndex should be removed")
    }

    func testRemoveCurrentClippingClampsIndexAfterRemovingLast() throws {
        let vm = try makeViewModel(clippings: ["a", "b", "c"])
        vm.selectedIndex = 2
        vm.removeCurrentClipping()
        XCTAssertEqual(vm.selectedIndex, 1, "selectedIndex should clamp to last valid index after removal")
    }

    func testRemoveCurrentClippingNoOpWhenEmpty() throws {
        let vm = try makeViewModel(clippings: [])
        vm.removeCurrentClipping()  // Should not crash
        XCTAssertEqual(vm.clippings.count, 0)
    }

    // MARK: - currentClippingInfo (new)

    func testCurrentClippingInfoReturnsClippingInfoAtIndex() throws {
        let vm = try makeViewModel(clippings: ["a", "b", "c"])
        vm.selectedIndex = 1
        XCTAssertEqual(vm.currentClippingInfo?.content, "b")
    }

    func testCurrentClippingInfoReturnsNilWhenEmpty() throws {
        let vm = try makeViewModel(clippings: [])
        XCTAssertNil(vm.currentClippingInfo)
    }

    // MARK: - Fuzzy search (Phase 07-01)

    func testFuzzySearchFindsNonContiguousMatch() throws {
        let vm = try makeViewModel(clippings: ["JSON.parse(data)", "hello world", "foo bar"])
        vm.searchText = "jsonpar"
        let contents = vm.filteredClippings.map(\.content)
        XCTAssertTrue(contents.contains("JSON.parse(data)"),
            "Fuzzy search for \"jsonpar\" must match \"JSON.parse(data)\"")
        XCTAssertFalse(contents.contains("hello world"),
            "\"hello world\" must NOT match \"jsonpar\"")
        XCTAssertFalse(contents.contains("foo bar"),
            "\"foo bar\" must NOT match \"jsonpar\"")
    }

    func testFuzzySearchRanksByMatchQuality() throws {
        let vm = try makeViewModel(clippings: [
            "justSomeOddNaming_parse_results",
            "JSON.parse(data)"
        ])
        vm.searchText = "jsonpar"
        XCTAssertEqual(vm.filteredClippings.count, 2,
            "Both strings must match \"jsonpar\"")
        XCTAssertEqual(vm.filteredClippings[0].content, "JSON.parse(data)",
            "Closer match \"JSON.parse(data)\" must rank first")
    }

    func testFuzzySearchReturnsEmptyForNonSubsequence() throws {
        let vm = try makeViewModel(clippings: ["hello", "world"])
        vm.searchText = "xyz"
        XCTAssertTrue(vm.filteredClippings.isEmpty,
            "Non-subsequence query \"xyz\" must return no matches")
    }

    // MARK: - Wraparound navigation (Bug #8)

    func testNavigateDownWrapsToFirstWhenAtLastAndWraparoundEnabled() throws {
        let vm = try makeViewModel(clippings: ["a", "b", "c"])
        vm.wraparoundBezel = true
        vm.selectedIndex = 2   // last index
        vm.navigateDown()
        XCTAssertEqual(vm.selectedIndex, 0, "navigateDown at last with wraparound=true should wrap to 0")
    }

    func testNavigateUpWrapsToLastWhenAtFirstAndWraparoundEnabled() throws {
        let vm = try makeViewModel(clippings: ["a", "b", "c"])
        vm.wraparoundBezel = true
        vm.selectedIndex = 0
        vm.navigateUp()
        XCTAssertEqual(vm.selectedIndex, 2, "navigateUp at first with wraparound=true should wrap to last")
    }

    func testNavigateDownNoOpAtLastWhenWraparoundDisabled() throws {
        let vm = try makeViewModel(clippings: ["a", "b", "c"])
        vm.wraparoundBezel = false
        vm.selectedIndex = 2
        vm.navigateDown()
        XCTAssertEqual(vm.selectedIndex, 2, "navigateDown at last with wraparound=false should clamp")
    }

    func testNavigateUpNoOpAtFirstWhenWraparoundDisabled() throws {
        let vm = try makeViewModel(clippings: ["a", "b", "c"])
        vm.wraparoundBezel = false
        vm.selectedIndex = 0
        vm.navigateUp()
        XCTAssertEqual(vm.selectedIndex, 0, "navigateUp at first with wraparound=false should clamp")
    }
}
