import XCTest
import SwiftData
@testable import FlycutSwift

final class ClipboardStoreTests: XCTestCase {

    // MARK: - testInsertAndFetch

    func testInsertAndFetch() async throws {
        let container = try makeTestContainer()
        let store = ClipboardStore(modelContainer: container)

        try await store.insert(content: "hello", sourceAppName: nil, sourceAppBundleURL: nil, rememberNum: 99)

        let ids = try await store.fetchAll()
        XCTAssertEqual(ids.count, 1)

        let content = await store.content(for: ids[0])
        XCTAssertEqual(content, "hello")
    }

    // MARK: - testDuplicateSkipped (count stays 1 — backward-compat test name retained)

    func testDuplicateSkipped() async throws {
        let container = try makeTestContainer()
        let store = ClipboardStore(modelContainer: container)

        try await store.insert(content: "hello", sourceAppName: nil, sourceAppBundleURL: nil, rememberNum: 99)
        try await store.insert(content: "hello", sourceAppName: nil, sourceAppBundleURL: nil, rememberNum: 99)

        let ids = try await store.fetchAll()
        XCTAssertEqual(ids.count, 1)
    }

    // MARK: - testTrimToLimit

    func testTrimToLimit() async throws {
        let container = try makeTestContainer()
        let store = ClipboardStore(modelContainer: container)

        // Insert 5 items with small delays to ensure distinct timestamps
        try await store.insert(content: "item1", sourceAppName: nil, sourceAppBundleURL: nil, rememberNum: 3)
        try await store.insert(content: "item2", sourceAppName: nil, sourceAppBundleURL: nil, rememberNum: 3)
        try await store.insert(content: "item3", sourceAppName: nil, sourceAppBundleURL: nil, rememberNum: 3)
        try await store.insert(content: "item4", sourceAppName: nil, sourceAppBundleURL: nil, rememberNum: 3)
        try await store.insert(content: "item5", sourceAppName: nil, sourceAppBundleURL: nil, rememberNum: 3)

        let ids = try await store.fetchAll()
        XCTAssertEqual(ids.count, 3)
    }

    // MARK: - testPersistenceRoundTrip

    func testPersistenceRoundTrip() async throws {
        let container = try makeTestContainer()
        let store1 = ClipboardStore(modelContainer: container)

        try await store1.insert(content: "persist me", sourceAppName: nil, sourceAppBundleURL: nil, rememberNum: 99)

        // Create a second store from the SAME container
        let store2 = ClipboardStore(modelContainer: container)
        let ids = try await store2.fetchAll()
        XCTAssertEqual(ids.count, 1)

        let content = await store2.content(for: ids[0])
        XCTAssertEqual(content, "persist me")
    }

    // MARK: - testClearAll

    func testClearAll() async throws {
        let container = try makeTestContainer()
        let store = ClipboardStore(modelContainer: container)

        try await store.insert(content: "item1", sourceAppName: nil, sourceAppBundleURL: nil, rememberNum: 99)
        try await store.insert(content: "item2", sourceAppName: nil, sourceAppBundleURL: nil, rememberNum: 99)
        try await store.insert(content: "item3", sourceAppName: nil, sourceAppBundleURL: nil, rememberNum: 99)

        try await store.clearAll()

        let ids = try await store.fetchAll()
        XCTAssertEqual(ids.count, 0)
    }

    // MARK: - testDeleteOne

    func testDeleteOne() async throws {
        let container = try makeTestContainer()
        let store = ClipboardStore(modelContainer: container)

        try await store.insert(content: "first", sourceAppName: nil, sourceAppBundleURL: nil, rememberNum: 99)
        try await store.insert(content: "middle", sourceAppName: nil, sourceAppBundleURL: nil, rememberNum: 99)
        try await store.insert(content: "last", sourceAppName: nil, sourceAppBundleURL: nil, rememberNum: 99)

        // fetchAll returns newest first, so index 1 is "middle"
        let ids = try await store.fetchAll()
        XCTAssertEqual(ids.count, 3)

        // Delete the middle item (index 1 in newest-first order)
        try await store.delete(id: ids[1])

        let remaining = try await store.fetchAll()
        XCTAssertEqual(remaining.count, 2)
    }

    // MARK: - testFetchOrdering

    func testFetchOrdering() async throws {
        let container = try makeTestContainer()
        let store = ClipboardStore(modelContainer: container)

        try await store.insert(content: "first", sourceAppName: nil, sourceAppBundleURL: nil, rememberNum: 99)
        try await store.insert(content: "second", sourceAppName: nil, sourceAppBundleURL: nil, rememberNum: 99)

        let ids = try await store.fetchAll()
        XCTAssertEqual(ids.count, 2)

        // fetchAll returns newest first — "second" was inserted last
        let first = await store.content(for: ids[0])
        let second = await store.content(for: ids[1])
        XCTAssertEqual(first, "second")
        XCTAssertEqual(second, "first")
    }

    // MARK: - testInsertWithSourceApp (Bug #1 — metadata persistence)

    func testInsertWithSourceApp() async throws {
        let container = try makeTestContainer()
        let store = ClipboardStore(modelContainer: container)

        try await store.insert(
            content: "metadata test",
            sourceAppName: "Safari",
            sourceAppBundleURL: "/Applications/Safari.app",
            rememberNum: 99
        )

        let ids = try await store.fetchAll()
        XCTAssertEqual(ids.count, 1)

        let appName = await store.sourceAppName(for: ids[0])
        let appURL = await store.sourceAppBundleURL(for: ids[0])

        XCTAssertEqual(appName, "Safari", "sourceAppName should be persisted")
        XCTAssertEqual(appURL, "/Applications/Safari.app", "sourceAppBundleURL should be persisted")
    }

    // MARK: - testMoveToTop (Bug #23 — pasteMovesToTop)

    func testMoveToTop() async throws {
        let container = try makeTestContainer()
        let store = ClipboardStore(modelContainer: container)

        // Insert "old" first, then "new" — "new" should be at the top by timestamp
        try await store.insert(content: "old", sourceAppName: nil, sourceAppBundleURL: nil, rememberNum: 99)
        try await Task.sleep(nanoseconds: 10_000_000) // 10ms to ensure distinct timestamps
        try await store.insert(content: "new", sourceAppName: nil, sourceAppBundleURL: nil, rememberNum: 99)

        // Capture "new"'s timestamp as reference point
        let beforeMoveToTop = Date.now
        try await Task.sleep(nanoseconds: 10_000_000) // 10ms

        // Call moveToTop on "old" — its timestamp should become newer than "new"
        try await store.moveToTop(content: "old")

        // Verify "old" is now at the top (index 0 in newest-first order)
        let ids = try await store.fetchAll()
        XCTAssertEqual(ids.count, 2)
        let topContent = await store.content(for: ids[0])
        XCTAssertEqual(topContent, "old", "moveToTop should promote 'old' to position 0")

        // Verify "old"'s timestamp is newer than beforeMoveToTop
        let oldTimestamp = await store.timestamp(for: ids[0])
        XCTAssertNotNil(oldTimestamp)
        XCTAssertGreaterThan(oldTimestamp!, beforeMoveToTop, "moveToTop should update timestamp to .now")
    }

    // MARK: - testRemoveDuplicatesFalseAllowsDuplicates (Bug #9)

    func testRemoveDuplicatesFalseAllowsDuplicates() async throws {
        UserDefaults.standard.set(false, forKey: "removeDuplicates")
        defer { UserDefaults.standard.removeObject(forKey: "removeDuplicates") }

        let container = try makeTestContainer()
        let store = ClipboardStore(modelContainer: container)

        try await store.insert(content: "hello", sourceAppName: nil, sourceAppBundleURL: nil, rememberNum: 99)
        try await store.insert(content: "hello", sourceAppName: nil, sourceAppBundleURL: nil, rememberNum: 99)

        let ids = try await store.fetchAll()
        XCTAssertEqual(ids.count, 2, "removeDuplicates=false should allow duplicate clippings")
    }

    // MARK: - testDuplicateMovedToTop (Bug #2 — dedup move-to-top)

    func testDuplicateMovedToTop() async throws {
        let container = try makeTestContainer()
        let store = ClipboardStore(modelContainer: container)

        // Insert "hello" first, then "world", then "hello" again
        try await store.insert(content: "hello", sourceAppName: nil, sourceAppBundleURL: nil, rememberNum: 99)
        // Small sleep to ensure distinct timestamps
        try await Task.sleep(nanoseconds: 10_000_000) // 10ms
        try await store.insert(content: "world", sourceAppName: nil, sourceAppBundleURL: nil, rememberNum: 99)
        let worldTimestamp = Date.now
        try await Task.sleep(nanoseconds: 10_000_000) // 10ms
        try await store.insert(content: "hello", sourceAppName: "TextEdit", sourceAppBundleURL: "/Applications/TextEdit.app", rememberNum: 99)

        // Count should remain 2 (not 3)
        let ids = try await store.fetchAll()
        XCTAssertEqual(ids.count, 2, "Duplicate insert should not create a new entry")

        // "hello" should be at top (index 0) — newest timestamp
        let topContent = await store.content(for: ids[0])
        XCTAssertEqual(topContent, "hello", "Re-copied clipping should be at the top")

        // Verify "hello" timestamp is newer than "world" (was inserted after worldTimestamp)
        let helloTimestamp = await store.timestamp(for: ids[0])
        XCTAssertNotNil(helloTimestamp)
        XCTAssertGreaterThan(
            helloTimestamp!,
            worldTimestamp,
            "Re-copied clipping timestamp should be updated to .now"
        )

        // Source metadata should be updated to second insert's values
        let appName = await store.sourceAppName(for: ids[0])
        let appURL = await store.sourceAppBundleURL(for: ids[0])
        XCTAssertEqual(appName, "TextEdit", "Source metadata should be updated on dedup move-to-top")
        XCTAssertEqual(appURL, "/Applications/TextEdit.app")
    }
}
