import XCTest
import SwiftData
@testable import Clipsmith

@MainActor
final class ClipboardExportServiceTests: XCTestCase {

    var container: ModelContainer!
    var store: ClipboardStore!

    override func setUp() async throws {
        try await super.setUp()
        container = try makeTestContainer()
        store = ClipboardStore(modelContainer: container)
    }

    override func tearDown() async throws {
        try await store.clearAll()
        container = nil
        store = nil
        try await super.tearDown()
    }

    // MARK: - testExportEmptyHistory

    func testExportEmptyHistory() async throws {
        let data = try await ClipboardExportService.exportHistory(from: store)

        // Must be valid JSON
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertNotNil(json, "Export result should be valid JSON")

        // Must have version = 1
        let version = json?["version"] as? Int
        XCTAssertEqual(version, 1, "Export version should be 1")

        // Must have empty clippings array
        let clippings = json?["clippings"] as? [[String: Any]]
        XCTAssertNotNil(clippings, "Export should contain clippings key")
        XCTAssertEqual(clippings?.count, 0, "Empty history should produce 0 clippings")
    }

    // MARK: - testExportWithClippings

    func testExportWithClippings() async throws {
        try await store.insert(content: "first", sourceAppName: "Safari", sourceAppBundleURL: nil, rememberNum: 99)
        try await store.insert(content: "second", sourceAppName: "TextEdit", sourceAppBundleURL: nil, rememberNum: 99)
        try await store.insert(content: "third", sourceAppName: nil, sourceAppBundleURL: nil, rememberNum: 99)

        let data = try await ClipboardExportService.exportHistory(from: store)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let clippings = json?["clippings"] as? [[String: Any]]

        XCTAssertEqual(clippings?.count, 3, "Export should contain 3 records")

        // Verify content is present in some order
        let contents = clippings?.compactMap { $0["content"] as? String } ?? []
        XCTAssertTrue(contents.contains("first"), "Export should contain 'first'")
        XCTAssertTrue(contents.contains("second"), "Export should contain 'second'")
        XCTAssertTrue(contents.contains("third"), "Export should contain 'third'")

        // Verify timestamp field is present
        let record = clippings?.first
        XCTAssertNotNil(record?["timestamp"], "Each record should have a timestamp")
    }

    // MARK: - testImportRoundTrip

    func testImportRoundTrip() async throws {
        // Insert 3 clippings with different timestamps
        let t1 = Date(timeIntervalSinceNow: -300)
        let t2 = Date(timeIntervalSinceNow: -200)
        let t3 = Date(timeIntervalSinceNow: -100)

        try await store.insert(content: "alpha", sourceAppName: "AppA", sourceAppBundleURL: nil, timestamp: t1, rememberNum: 99)
        try await store.insert(content: "beta", sourceAppName: "AppB", sourceAppBundleURL: nil, timestamp: t2, rememberNum: 99)
        try await store.insert(content: "gamma", sourceAppName: nil, sourceAppBundleURL: nil, timestamp: t3, rememberNum: 99)

        // Export
        let data = try await ClipboardExportService.exportHistory(from: store)

        // Clear
        try await store.clearAll()
        let idsAfterClear = try await store.fetchAll()
        XCTAssertEqual(idsAfterClear.count, 0, "Store should be empty after clearAll")

        // Import
        let importedCount = try await ClipboardExportService.importHistory(
            into: store,
            from: data,
            merge: false
        )
        XCTAssertEqual(importedCount, 3, "Import should restore 3 records")

        // Verify all restored
        let ids = try await store.fetchAll()
        XCTAssertEqual(ids.count, 3, "Store should have 3 records after import")

        var contents: [String] = []
        for id in ids {
            if let c = await store.content(for: id) {
                contents.append(c)
            }
        }
        XCTAssertTrue(contents.contains("alpha"), "Round-trip should restore 'alpha'")
        XCTAssertTrue(contents.contains("beta"), "Round-trip should restore 'beta'")
        XCTAssertTrue(contents.contains("gamma"), "Round-trip should restore 'gamma'")
    }

    // MARK: - testImportSkipsDuplicates

    func testImportSkipsDuplicates() async throws {
        try await store.insert(content: "dup1", sourceAppName: nil, sourceAppBundleURL: nil, rememberNum: 99)
        try await store.insert(content: "dup2", sourceAppName: nil, sourceAppBundleURL: nil, rememberNum: 99)

        // Export the 2 clippings
        let data = try await ClipboardExportService.exportHistory(from: store)

        // Import with merge=true (don't clear, just add new ones)
        let importedCount = try await ClipboardExportService.importHistory(
            into: store,
            from: data,
            merge: true
        )

        // Should skip both as duplicates
        XCTAssertEqual(importedCount, 0, "Import of duplicates should import 0 new records")

        let ids = try await store.fetchAll()
        XCTAssertEqual(ids.count, 2, "Store should still have 2 records (no duplicates created)")
    }
}
