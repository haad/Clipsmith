import XCTest
import SwiftData
@testable import Clipsmith

final class SnippetStoreTests: XCTestCase {

    // MARK: - testInsertAndFetch

    func testInsertAndFetch() async throws {
        let container = try makeTestContainer()
        let store = SnippetStore(modelContainer: container)

        try await store.insert(
            name: "My Snippet",
            content: "let x = 42",
            language: "swift",
            tags: ["swift", "basics"]
        )

        let ids = try await store.fetchAll()
        XCTAssertEqual(ids.count, 1)

        let info = await store.snippet(for: ids[0])
        XCTAssertNotNil(info)
        XCTAssertEqual(info?.name, "My Snippet")
        XCTAssertEqual(info?.content, "let x = 42")
        XCTAssertEqual(info?.language, "swift")
        XCTAssertEqual(info?.tags, ["swift", "basics"])
    }

    // MARK: - testFetchByLanguage

    func testFetchByLanguage() async throws {
        let container = try makeTestContainer()
        let store = SnippetStore(modelContainer: container)

        try await store.insert(name: "Swift One", content: "let a = 1", language: "swift", tags: [])
        try await store.insert(name: "Python One", content: "a = 1", language: "python", tags: [])
        try await store.insert(name: "Swift Two", content: "let b = 2", language: "swift", tags: [])

        let swiftIDs = try await store.fetchByLanguage("swift")
        XCTAssertEqual(swiftIDs.count, 2, "fetchByLanguage should return only swift snippets")

        let pythonIDs = try await store.fetchByLanguage("python")
        XCTAssertEqual(pythonIDs.count, 1, "fetchByLanguage should return only python snippets")

        let rustIDs = try await store.fetchByLanguage("rust")
        XCTAssertEqual(rustIDs.count, 0, "fetchByLanguage should return empty for unknown language")
    }

    // MARK: - testSearchByName

    func testSearchByName() async throws {
        let container = try makeTestContainer()
        let store = SnippetStore(modelContainer: container)

        try await store.insert(name: "kubectl get pods", content: "kubectl get pods -n default", language: "bash", tags: [])
        try await store.insert(name: "jq filter", content: "jq '.[] | .name'", language: "bash", tags: [])
        try await store.insert(name: "Swift hello world", content: "print(\"Hello\")", language: "swift", tags: [])

        let results = try await store.search(query: "kubectl")
        XCTAssertEqual(results.count, 1)

        let info = await store.snippet(for: results[0])
        XCTAssertEqual(info?.name, "kubectl get pods")
    }

    // MARK: - testSearchByContent

    func testSearchByContent() async throws {
        let container = try makeTestContainer()
        let store = SnippetStore(modelContainer: container)

        try await store.insert(name: "Snippet A", content: "docker run --rm -it ubuntu bash", language: "bash", tags: [])
        try await store.insert(name: "Snippet B", content: "git commit -m 'feat: add feature'", language: "bash", tags: [])
        try await store.insert(name: "Snippet C", content: "npm install --save-dev typescript", language: "bash", tags: [])

        let results = try await store.search(query: "docker")
        XCTAssertEqual(results.count, 1)

        let info = await store.snippet(for: results[0])
        XCTAssertEqual(info?.name, "Snippet A")
    }

    // MARK: - testSearchByTag

    func testSearchByTag() async throws {
        let container = try makeTestContainer()
        let store = SnippetStore(modelContainer: container)

        try await store.insert(name: "Snippet A", content: "content A", language: nil, tags: ["kubernetes", "ops"])
        try await store.insert(name: "Snippet B", content: "content B", language: nil, tags: ["docker", "ops"])
        try await store.insert(name: "Snippet C", content: "content C", language: nil, tags: ["swift", "ios"])

        let results = try await store.search(query: "kubernetes")
        XCTAssertEqual(results.count, 1)

        let info = await store.snippet(for: results[0])
        XCTAssertEqual(info?.name, "Snippet A")
    }

    // MARK: - testSearchEmptyQueryReturnsAll

    func testSearchEmptyQueryReturnsAll() async throws {
        let container = try makeTestContainer()
        let store = SnippetStore(modelContainer: container)

        try await store.insert(name: "A", content: "aaa", language: nil, tags: [])
        try await store.insert(name: "B", content: "bbb", language: nil, tags: [])
        try await store.insert(name: "C", content: "ccc", language: nil, tags: [])

        let results = try await store.search(query: "")
        XCTAssertEqual(results.count, 3, "Empty search query should return all snippets")
    }

    // MARK: - testUpdate

    func testUpdate() async throws {
        let container = try makeTestContainer()
        let store = SnippetStore(modelContainer: container)

        try await store.insert(name: "Original", content: "original content", language: "swift", tags: ["old"])

        let ids = try await store.fetchAll()
        XCTAssertEqual(ids.count, 1)

        let originalInfo = await store.snippet(for: ids[0])
        let originalUpdatedAt = originalInfo?.updatedAt ?? Date.distantPast

        // Small sleep to ensure distinct timestamps
        try await Task.sleep(nanoseconds: 10_000_000) // 10ms

        try await store.update(
            id: ids[0],
            name: "Updated Name",
            content: "updated content",
            language: "python",
            tags: ["new", "updated"]
        )

        let updatedInfo = await store.snippet(for: ids[0])
        XCTAssertEqual(updatedInfo?.name, "Updated Name")
        XCTAssertEqual(updatedInfo?.content, "updated content")
        XCTAssertEqual(updatedInfo?.language, "python")
        XCTAssertEqual(updatedInfo?.tags, ["new", "updated"])
        XCTAssertGreaterThan(updatedInfo?.updatedAt ?? Date.distantPast, originalUpdatedAt,
                             "updatedAt should be updated after mutation")
    }

    // MARK: - testDelete

    func testDelete() async throws {
        let container = try makeTestContainer()
        let store = SnippetStore(modelContainer: container)

        try await store.insert(name: "Keep Me", content: "keep", language: nil, tags: [])
        try await store.insert(name: "Delete Me", content: "delete", language: nil, tags: [])

        var ids = try await store.fetchAll()
        XCTAssertEqual(ids.count, 2)

        // Delete the first one (newest, at index 0)
        try await store.delete(id: ids[0])

        ids = try await store.fetchAll()
        XCTAssertEqual(ids.count, 1)

        let remaining = await store.snippet(for: ids[0])
        XCTAssertNotNil(remaining)
    }

    // MARK: - testFetchAllSortedByUpdatedAtDescending

    func testFetchAllSortedByUpdatedAtDescending() async throws {
        let container = try makeTestContainer()
        let store = SnippetStore(modelContainer: container)

        try await store.insert(name: "First", content: "first", language: nil, tags: [])
        try await Task.sleep(nanoseconds: 10_000_000) // 10ms
        try await store.insert(name: "Second", content: "second", language: nil, tags: [])
        try await Task.sleep(nanoseconds: 10_000_000) // 10ms
        try await store.insert(name: "Third", content: "third", language: nil, tags: [])

        let ids = try await store.fetchAll()
        XCTAssertEqual(ids.count, 3)

        // Most recently inserted/updated is at index 0
        let first = await store.snippet(for: ids[0])
        let last = await store.snippet(for: ids[2])
        XCTAssertEqual(first?.name, "Third", "Most recently edited snippet should be first")
        XCTAssertEqual(last?.name, "First", "Oldest snippet should be last")
    }

    // MARK: - testContentAccessor

    func testContentAccessor() async throws {
        let container = try makeTestContainer()
        let store = SnippetStore(modelContainer: container)

        try await store.insert(name: "Content Test", content: "print(\"hello world\")", language: "swift", tags: [])

        let ids = try await store.fetchAll()
        let content = await store.content(for: ids[0])
        XCTAssertEqual(content, "print(\"hello world\")")
    }
}
