import XCTest
import SwiftData
@testable import Clipsmith

final class SchemaMigrationTests: XCTestCase {

    // MARK: - testV2SchemaIncludesAllFourModels

    /// V2 schema must include all V1 models plus PromptLibraryItem (4 models total).
    func testV2SchemaIncludesAllFourModels() {
        let modelTypes = ClipsmithSchemaV2.models
        XCTAssertEqual(modelTypes.count, 4, "ClipsmithSchemaV2 must include 4 models: Clipping, Snippet, GistRecord, PromptLibraryItem")
    }

    // MARK: - testV2ContainerCreation

    /// A V2 in-memory container can be created successfully.
    func testV2ContainerCreation() throws {
        let schema = Schema(ClipsmithSchemaV2.models)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        XCTAssertNotNil(container)
    }

    // MARK: - testPromptLibraryItemInsertAndFetch

    /// PromptLibraryItem can be inserted and fetched from a V2 container.
    func testPromptLibraryItemInsertAndFetch() async throws {
        let container = try makeTestContainer()

        try await MainActor.run {
            let context = container.mainContext

            let item = ClipsmithSchemaV2.PromptLibraryItem(
                id: "code-review-swift",
                title: "Swift Code Review",
                content: "Review this Swift code:\n\n{{clipboard}}",
                category: "coding",
                version: 1
            )
            context.insert(item)
            try context.save()

            let descriptor = FetchDescriptor<ClipsmithSchemaV2.PromptLibraryItem>()
            let fetched = try context.fetch(descriptor)
            XCTAssertEqual(fetched.count, 1)
            XCTAssertEqual(fetched[0].id, "code-review-swift")
            XCTAssertEqual(fetched[0].title, "Swift Code Review")
            XCTAssertEqual(fetched[0].category, "coding")
        }
    }

    // MARK: - testPromptLibraryItemDefaults

    /// PromptLibraryItem fields have correct defaults.
    func testPromptLibraryItemDefaults() throws {
        let item = ClipsmithSchemaV2.PromptLibraryItem(
            id: "test-prompt",
            title: "Test",
            content: "Content",
            category: "coding"
        )
        XCTAssertEqual(item.version, 1, "version default should be 1")
        XCTAssertFalse(item.isUserCustomized, "isUserCustomized default should be false")
        XCTAssertFalse(item.isUserCreated, "isUserCreated default should be false")
        XCTAssertNil(item.sourceURL, "sourceURL default should be nil")
    }

    // MARK: - testV1ModelsWorkWithV2Schema

    /// Clipping, Snippet, and GistRecord all work correctly with the V2 schema.
    func testV1ModelsWorkWithV2Schema() async throws {
        let container = try makeTestContainer()

        try await MainActor.run {
            let context = container.mainContext

            // Insert a Clipping
            let clipping = ClipsmithSchemaV2.Clipping(content: "test clipping")
            context.insert(clipping)

            // Insert a Snippet
            let snippet = ClipsmithSchemaV2.Snippet(name: "test snippet", content: "let x = 1")
            context.insert(snippet)

            // Insert a GistRecord
            let gist = ClipsmithSchemaV2.GistRecord(gistID: "abc123", gistURL: "https://gist.github.com/abc123", filename: "test.swift")
            context.insert(gist)

            try context.save()

            let clippings = try context.fetch(FetchDescriptor<ClipsmithSchemaV2.Clipping>())
            let snippets = try context.fetch(FetchDescriptor<ClipsmithSchemaV2.Snippet>())
            let gists = try context.fetch(FetchDescriptor<ClipsmithSchemaV2.GistRecord>())

            XCTAssertEqual(clippings.count, 1, "Clipping should be persisted with V2 schema")
            XCTAssertEqual(snippets.count, 1, "Snippet should be persisted with V2 schema")
            XCTAssertEqual(gists.count, 1, "GistRecord should be persisted with V2 schema")
        }
    }
}
