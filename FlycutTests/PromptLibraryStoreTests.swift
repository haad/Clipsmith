import XCTest
import SwiftData
@testable import FlycutSwift

final class PromptLibraryStoreTests: XCTestCase {

    // MARK: - testInsertAndFetchAll

    func testInsertAndFetchAll() async throws {
        let container = try makeTestContainer()
        let store = PromptLibraryStore(modelContainer: container)

        try await store.insert(
            id: "code-review",
            title: "Code Review",
            content: "Review this: {{clipboard}}",
            category: "coding"
        )

        let ids = try await store.fetchAll()
        XCTAssertEqual(ids.count, 1)

        let info = await store.prompt(for: ids[0])
        XCTAssertNotNil(info)
        XCTAssertEqual(info?.promptID, "code-review")
        XCTAssertEqual(info?.title, "Code Review")
        XCTAssertEqual(info?.category, "coding")
    }

    // MARK: - testFetchByCategory

    func testFetchByCategory() async throws {
        let container = try makeTestContainer()
        let store = PromptLibraryStore(modelContainer: container)

        try await store.insert(id: "code-review", title: "Code Review", content: "...", category: "coding")
        try await store.insert(id: "fix-bug", title: "Fix Bug", content: "...", category: "coding")
        try await store.insert(id: "summarize", title: "Summarize", content: "...", category: "writing")

        let codingIDs = try await store.fetchByCategory("coding")
        XCTAssertEqual(codingIDs.count, 2, "fetchByCategory should return only coding prompts")

        let writingIDs = try await store.fetchByCategory("writing")
        XCTAssertEqual(writingIDs.count, 1)

        let emptyIDs = try await store.fetchByCategory("nonexistent")
        XCTAssertEqual(emptyIDs.count, 0)
    }

    // MARK: - testSearchByTitleAndContent

    func testSearchByTitleAndContent() async throws {
        let container = try makeTestContainer()
        let store = PromptLibraryStore(modelContainer: container)

        try await store.insert(id: "code-review", title: "Code Review", content: "Review this code: {{clipboard}}", category: "coding")
        try await store.insert(id: "summarize", title: "Summarize Text", content: "Summarize this: {{clipboard}}", category: "writing")
        try await store.insert(id: "fix-bug", title: "Fix Bug", content: "Find the bug in: {{clipboard}}", category: "coding")

        let reviewResults = try await store.search(query: "review")
        XCTAssertEqual(reviewResults.count, 1)
        let reviewInfo = await store.prompt(for: reviewResults[0])
        XCTAssertEqual(reviewInfo?.promptID, "code-review")
    }

    // MARK: - testSearchHashCategoryFilter

    func testSearchHashCategoryFilter() async throws {
        let container = try makeTestContainer()
        let store = PromptLibraryStore(modelContainer: container)

        try await store.insert(id: "code-review", title: "Code Review", content: "...", category: "coding")
        try await store.insert(id: "fix-bug", title: "Fix Bug", content: "...", category: "coding")
        try await store.insert(id: "summarize", title: "Summarize Text", content: "...", category: "writing")

        let codingResults = try await store.search(query: "#coding")
        XCTAssertEqual(codingResults.count, 2, "#coding should filter to coding category only")
    }

    // MARK: - testSearchHashCategoryWithText

    func testSearchHashCategoryWithText() async throws {
        let container = try makeTestContainer()
        let store = PromptLibraryStore(modelContainer: container)

        try await store.insert(id: "code-review", title: "Code Review", content: "...", category: "coding")
        try await store.insert(id: "fix-bug", title: "Fix Bug", content: "...", category: "coding")
        try await store.insert(id: "summarize", title: "Summarize Text", content: "...", category: "writing")

        let results = try await store.search(query: "#coding review")
        XCTAssertEqual(results.count, 1, "#coding review should filter by category AND search text")
        let info = await store.prompt(for: results[0])
        XCTAssertEqual(info?.promptID, "code-review")
    }

    // MARK: - testUpsertInsertsNew

    func testUpsertInsertsNew() async throws {
        let container = try makeTestContainer()
        let store = PromptLibraryStore(modelContainer: container)

        let dto = PromptDTO(id: "new-prompt", title: "New Prompt", category: "coding", version: 1, content: "Content")
        try await store.upsert(remote: dto)

        let ids = try await store.fetchAll()
        XCTAssertEqual(ids.count, 1, "upsert should insert when no matching id exists")
        let info = await store.prompt(for: ids[0])
        XCTAssertEqual(info?.promptID, "new-prompt")
    }

    // MARK: - testUpsertUpdatesWhenRemoteVersionNewer

    func testUpsertUpdatesWhenRemoteVersionNewer() async throws {
        let container = try makeTestContainer()
        let store = PromptLibraryStore(modelContainer: container)

        // Insert initial version
        try await store.insert(id: "my-prompt", title: "Old Title", content: "Old content", category: "coding", version: 1)

        // Upsert with newer remote version
        let remoteDTO = PromptDTO(id: "my-prompt", title: "New Title", category: "coding", version: 2, content: "New content")
        try await store.upsert(remote: remoteDTO)

        let ids = try await store.fetchAll()
        XCTAssertEqual(ids.count, 1, "upsert should not create duplicate")
        let info = await store.prompt(for: ids[0])
        XCTAssertEqual(info?.title, "New Title", "upsert should update title when remote version is newer")
        XCTAssertEqual(info?.content, "New content", "upsert should update content when remote version is newer")
        XCTAssertEqual(info?.version, 2)
    }

    // MARK: - testUpsertSkipsWhenUserCustomized

    func testUpsertSkipsWhenUserCustomized() async throws {
        let container = try makeTestContainer()
        let store = PromptLibraryStore(modelContainer: container)

        // Insert and mark as user customized
        try await store.insert(id: "my-prompt", title: "Original", content: "User custom content", category: "coding", version: 1)
        let ids = try await store.fetchAll()
        try await store.update(id: ids[0], title: "User Modified", content: "User custom content")

        // Try to upsert with newer remote version — should be skipped (PMPT-07)
        let remoteDTO = PromptDTO(id: "my-prompt", title: "Remote Title", category: "coding", version: 5, content: "Remote content")
        try await store.upsert(remote: remoteDTO)

        let allIDs = try await store.fetchAll()
        let info = await store.prompt(for: allIDs[0])
        XCTAssertEqual(info?.title, "User Modified", "upsert should skip update when isUserCustomized == true")
        XCTAssertEqual(info?.content, "User custom content", "upsert should not overwrite user content")
        XCTAssertTrue(info?.isUserCustomized ?? false)
    }

    // MARK: - testUpsertSkipsWhenRemoteVersionNotNewer

    func testUpsertSkipsWhenRemoteVersionNotNewer() async throws {
        let container = try makeTestContainer()
        let store = PromptLibraryStore(modelContainer: container)

        try await store.insert(id: "my-prompt", title: "Current Title", content: "Current content", category: "coding", version: 3)

        // Remote version equal to local — should skip
        let sameVersionDTO = PromptDTO(id: "my-prompt", title: "Different Title", category: "coding", version: 3, content: "Different content")
        try await store.upsert(remote: sameVersionDTO)

        let ids = try await store.fetchAll()
        let info = await store.prompt(for: ids[0])
        XCTAssertEqual(info?.title, "Current Title", "upsert should skip when remote version == local version")

        // Remote version older — should also skip
        let olderDTO = PromptDTO(id: "my-prompt", title: "Old Title", category: "coding", version: 1, content: "Old content")
        try await store.upsert(remote: olderDTO)

        let updatedInfo = await store.prompt(for: ids[0])
        XCTAssertEqual(updatedInfo?.title, "Current Title", "upsert should skip when remote version < local version")
    }

    // MARK: - testUpdateSetsUserCustomized

    func testUpdateSetsUserCustomized() async throws {
        let container = try makeTestContainer()
        let store = PromptLibraryStore(modelContainer: container)

        try await store.insert(id: "code-review", title: "Original", content: "Original content", category: "coding")

        let ids = try await store.fetchAll()
        try await store.update(id: ids[0], title: "Modified", content: "Modified content")

        let info = await store.prompt(for: ids[0])
        XCTAssertEqual(info?.title, "Modified")
        XCTAssertEqual(info?.content, "Modified content")
        XCTAssertTrue(info?.isUserCustomized ?? false, "update() should set isUserCustomized = true")
    }

    // MARK: - testRevertToOriginalClearsCustomizedFlag

    func testRevertToOriginalClearsCustomizedFlag() async throws {
        let container = try makeTestContainer()
        let store = PromptLibraryStore(modelContainer: container)

        try await store.insert(id: "code-review", title: "Original", content: "Original content", category: "coding")
        let ids = try await store.fetchAll()

        // Mark as customized
        try await store.update(id: ids[0], title: "Modified", content: "Modified content")
        let customizedInfo = await store.prompt(for: ids[0])
        XCTAssertTrue(customizedInfo?.isUserCustomized ?? false)

        // Revert
        try await store.revertToOriginal(id: ids[0])
        let revertedInfo = await store.prompt(for: ids[0])
        XCTAssertFalse(revertedInfo?.isUserCustomized ?? true, "revertToOriginal() should clear isUserCustomized flag")
    }

    // MARK: - testDelete

    func testDelete() async throws {
        let container = try makeTestContainer()
        let store = PromptLibraryStore(modelContainer: container)

        try await store.insert(id: "keep", title: "Keep", content: "...", category: "coding")
        try await store.insert(id: "delete-me", title: "Delete Me", content: "...", category: "coding")

        var ids = try await store.fetchAll()
        XCTAssertEqual(ids.count, 2)

        try await store.delete(id: ids[0])

        ids = try await store.fetchAll()
        XCTAssertEqual(ids.count, 1)
    }

    // MARK: - testPromptForReturnsPromptInfo

    func testPromptForReturnsPromptInfo() async throws {
        let container = try makeTestContainer()
        let store = PromptLibraryStore(modelContainer: container)

        try await store.insert(
            id: "test-prompt",
            title: "Test Prompt",
            content: "Content {{clipboard}}",
            category: "coding",
            version: 2
        )

        let ids = try await store.fetchAll()
        let info = await store.prompt(for: ids[0])

        XCTAssertNotNil(info)
        XCTAssertEqual(info?.promptID, "test-prompt")
        XCTAssertEqual(info?.title, "Test Prompt")
        XCTAssertEqual(info?.content, "Content {{clipboard}}")
        XCTAssertEqual(info?.category, "coding")
        XCTAssertEqual(info?.version, 2)
        XCTAssertFalse(info?.isUserCustomized ?? true)
    }

    // MARK: - testContentAccessor

    func testContentAccessor() async throws {
        let container = try makeTestContainer()
        let store = PromptLibraryStore(modelContainer: container)

        try await store.insert(id: "code-review", title: "Code Review", content: "Review this: {{clipboard}}", category: "coding")

        let ids = try await store.fetchAll()
        let content = await store.content(for: ids[0])
        XCTAssertEqual(content, "Review this: {{clipboard}}")
    }
}
