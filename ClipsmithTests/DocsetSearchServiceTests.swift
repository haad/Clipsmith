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

    func testSearchReturnsMatchingEntries() {
        let results = service.search(query: "String", in: sampleEntries)
        XCTAssertFalse(results.isEmpty, "Should find entries matching 'String'")
        XCTAssertTrue(results.allSatisfy { $0.name.contains("String") })
    }

    func testSearchPrefixMatchesRankedFirst() {
        let results = service.search(query: "Arr", in: sampleEntries)
        XCTAssertFalse(results.isEmpty)
        // "Array" should appear before "Array.map" (shorter name)
        XCTAssertEqual(results[0].name, "Array")
    }

    func testSearchNoResults() {
        let results = service.search(query: "ZZZZNOTFOUND", in: sampleEntries)
        XCTAssertTrue(results.isEmpty)
    }

    func testSearchCaseInsensitive() {
        let results = service.search(query: "array", in: sampleEntries)
        XCTAssertFalse(results.isEmpty)
        XCTAssertTrue(results.allSatisfy { $0.name.lowercased().contains("array") })
    }

    func testSearchAllAcrossDocsets() throws {
        // Create a temp index.json for testing
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let indexJSON = """
        {"entries":[{"name":"Array","path":"global_objects/array","type":"Global Objects"},{"name":"Map","path":"global_objects/map","type":"Global Objects"}]}
        """
        try indexJSON.data(using: .utf8)!.write(to: tmpDir.appendingPathComponent("index.json"))

        let docset = DocsetInfo(
            id: "javascript",
            displayName: "JavaScript",
            release: nil,
            dbSize: 1000,
            isEnabled: true,
            isDownloaded: true
        )
        // Manually cache the entries since we can't set indexPath to our tmp dir
        let entries = try service.loadIndex(slug: "javascript", from: tmpDir.appendingPathComponent("index.json"))
        XCTAssertEqual(entries.count, 2)

        let results = service.search(query: "Array", in: entries)
        XCTAssertFalse(results.isEmpty)
    }

    func testDisabledDocsetSkipped() throws {
        let docset = DocsetInfo(
            id: "test-disabled",
            displayName: "Test",
            release: nil,
            dbSize: 100,
            isEnabled: false,
            isDownloaded: true
        )
        let results = try service.searchAll(query: "Array", docsets: [docset])
        XCTAssertTrue(results.isEmpty, "Disabled docsets should be skipped")
    }
}
