import XCTest
@testable import Clipsmith

final class DocsetSearchServiceTests: XCTestCase {
    private var service: DocsetSearchService!
    private var fixtureURL: URL!

    override func setUp() async throws {
        service = DocsetSearchService()
        // Locate the test fixture relative to the test source file.
        // #filePath returns an absolute path to the source file during compilation.
        let thisFile = URL(fileURLWithPath: #filePath)
        let resolvedFixture = thisFile.deletingLastPathComponent()
            .appendingPathComponent("Fixtures/TestDocset.docset")
        // Resolve to an absolute path so SQLite can open it regardless of cwd
        fixtureURL = URL(fileURLWithPath: resolvedFixture.path)
    }

    func testSearchReturnsMatchingEntries() async throws {
        let results = try await service.search(query: "String", in: fixtureURL)
        XCTAssertFalse(results.isEmpty, "Should find entries matching 'String'")
        XCTAssertTrue(results.allSatisfy { $0.name.contains("String") })
    }

    func testSearchPrefixMatchesRankedFirst() async throws {
        let results = try await service.search(query: "Arr", in: fixtureURL)
        XCTAssertFalse(results.isEmpty)
        // "Array" should appear before "Array.append" (shorter name)
        if results.count >= 2 {
            XCTAssertEqual(results[0].name, "Array")
        }
    }

    func testSearchNoResults() async throws {
        let results = try await service.search(query: "ZZZZNOTFOUND", in: fixtureURL)
        XCTAssertTrue(results.isEmpty)
    }

    func testSearchLimit() async throws {
        // Our fixture has 10 entries; searching broad should return all of them
        let results = try await service.search(query: "", in: fixtureURL)
        // LIKE '%%' matches everything
        XCTAssertEqual(results.count, 10)
    }

    func testSearchAllAcrossDocsets() async throws {
        let docset = DocsetInfo(
            id: "TestDocset",
            displayName: "Test",
            localPath: fixtureURL,
            version: nil,
            isEnabled: true
        )
        let results = try await service.searchAll(query: "Array", docsets: [docset])
        XCTAssertFalse(results.isEmpty)
        XCTAssertTrue(results.allSatisfy { $0.docset.id == "TestDocset" })
    }

    func testDisabledDocsetSkipped() async throws {
        let docset = DocsetInfo(
            id: "TestDocset",
            displayName: "Test",
            localPath: fixtureURL,
            version: nil,
            isEnabled: false  // disabled
        )
        let results = try await service.searchAll(query: "Array", docsets: [docset])
        XCTAssertTrue(results.isEmpty, "Disabled docsets should be skipped")
    }
}
