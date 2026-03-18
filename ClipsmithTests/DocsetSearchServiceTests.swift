import XCTest
@testable import Clipsmith

final class DocsetSearchServiceTests: XCTestCase {
    private var service: DocsetSearchService!
    private var sampleEntries: [DocEntry]!

    override func setUp() {
        service = DocsetSearchService()
        sampleEntries = [
            DocEntry(slug: "javascript", name: "Array", type: "Global Objects", path: "global_objects/array"),
            DocEntry(slug: "javascript", name: "Array.map", type: "Array", path: "global_objects/array/map"),
            DocEntry(slug: "javascript", name: "Array.filter", type: "Array", path: "global_objects/array/filter"),
            DocEntry(slug: "javascript", name: "Array.forEach", type: "Array", path: "global_objects/array/foreach"),
            DocEntry(slug: "javascript", name: "String", type: "Global Objects", path: "global_objects/string"),
            DocEntry(slug: "javascript", name: "String.split", type: "String", path: "global_objects/string/split"),
            DocEntry(slug: "javascript", name: "parseInt", type: "Functions", path: "global_objects/parseint"),
            DocEntry(slug: "javascript", name: "Promise", type: "Global Objects", path: "global_objects/promise"),
            DocEntry(slug: "javascript", name: "Map", type: "Global Objects", path: "global_objects/map"),
            DocEntry(slug: "javascript", name: "Set", type: "Global Objects", path: "global_objects/set"),
        ]
    }

    // MARK: - Fuzzy search

    func testSearchReturnsMatchingEntries() {
        let results = service.search(query: "String", in: sampleEntries)
        XCTAssertFalse(results.isEmpty, "Should find entries matching 'String'")
        XCTAssertTrue(results.allSatisfy { $0.entry.name.contains("String") })
    }

    func testSearchExactMatchRankedFirst() {
        let results = service.search(query: "Array", in: sampleEntries)
        XCTAssertFalse(results.isEmpty)
        // "Array" exact match should appear first (highest score, then shortest name)
        XCTAssertEqual(results[0].entry.name, "Array")
        XCTAssertGreaterThanOrEqual(results[0].score, results[1].score)
    }

    func testSearchFuzzyMatching() {
        // "arrmap" should fuzzy-match "Array.map" (subsequence)
        let results = service.search(query: "arrmap", in: sampleEntries)
        XCTAssertFalse(results.isEmpty, "Fuzzy subsequence should match")
        XCTAssertTrue(results.contains { $0.entry.name == "Array.map" })
    }

    func testSearchNoResults() {
        let results = service.search(query: "ZZZZNOTFOUND", in: sampleEntries)
        XCTAssertTrue(results.isEmpty)
    }

    func testSearchCaseInsensitive() {
        let results = service.search(query: "array", in: sampleEntries)
        XCTAssertFalse(results.isEmpty)
    }

    func testSearchScoring() {
        // "Map" (exact) should score higher than "Array.map" (partial)
        let results = service.search(query: "Map", in: sampleEntries)
        XCTAssertGreaterThanOrEqual(results.count, 2)
        XCTAssertEqual(results[0].entry.name, "Map")
    }

    // MARK: - Query parsing

    func testParseQueryWithPrefix() {
        let parsed = service.parseQuery("python:map")
        XCTAssertEqual(parsed.docFilter, "python")
        XCTAssertEqual(parsed.query, "map")
    }

    func testParseQueryWithoutPrefix() {
        let parsed = service.parseQuery("map")
        XCTAssertNil(parsed.docFilter)
        XCTAssertEqual(parsed.query, "map")
    }

    func testParseQueryEmptyPrefix() {
        let parsed = service.parseQuery(":map")
        XCTAssertNil(parsed.docFilter)
        XCTAssertEqual(parsed.query, ":map")
    }

    func testParseQueryWithSpaces() {
        let parsed = service.parseQuery("go : fmt")
        XCTAssertEqual(parsed.docFilter, "go")
        XCTAssertEqual(parsed.query, "fmt")
    }

    // MARK: - Doc filter matching

    func testDocsetMatchesFilterBySlug() {
        let docset = DocsetInfo(id: "python~3.14", displayName: "Python 3.14", release: nil, dbSize: 100, isEnabled: true, isDownloaded: true)
        XCTAssertTrue(service.docsetMatchesFilter(docset, filter: "python"))
        XCTAssertTrue(service.docsetMatchesFilter(docset, filter: "py"))
        XCTAssertFalse(service.docsetMatchesFilter(docset, filter: "ruby"))
    }

    func testDocsetMatchesFilterByDisplayName() {
        let docset = DocsetInfo(id: "go", displayName: "Go", release: nil, dbSize: 100, isEnabled: true, isDownloaded: true)
        XCTAssertTrue(service.docsetMatchesFilter(docset, filter: "go"))
        XCTAssertTrue(service.docsetMatchesFilter(docset, filter: "Go"))
    }

    // MARK: - Filtered search

    func testSearchAllWithDocFilter() throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let indexJSON = """
        {"entries":[{"name":"Array","path":"global_objects/array","type":"Global Objects"}]}
        """
        try indexJSON.data(using: .utf8)!.write(to: tmpDir.appendingPathComponent("index.json"))
        _ = try service.loadIndex(slug: "javascript", from: tmpDir.appendingPathComponent("index.json"))

        let docset = DocsetInfo(id: "javascript", displayName: "JavaScript", release: nil, dbSize: 1000, isEnabled: true, isDownloaded: true)

        // With matching filter — should find results
        let results = try service.searchAll(query: "Array", docFilter: "java", docsets: [docset])
        XCTAssertFalse(results.isEmpty)

        // With non-matching filter — should find nothing
        let filtered = try service.searchAll(query: "Array", docFilter: "python", docsets: [docset])
        XCTAssertTrue(filtered.isEmpty)
    }

    func testDisabledDocsetSkipped() throws {
        let docset = DocsetInfo(id: "test-disabled", displayName: "Test", release: nil, dbSize: 100, isEnabled: false, isDownloaded: true)
        let results = try service.searchAll(query: "Array", docFilter: nil, docsets: [docset])
        XCTAssertTrue(results.isEmpty, "Disabled docsets should be skipped")
    }
}
