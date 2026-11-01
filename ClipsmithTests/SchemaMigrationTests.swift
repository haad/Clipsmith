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

    // MARK: - testV1ModelsWorkWithCurrentSchema

    /// Clipping and Snippet (V1 models) persist through the current (V3) test container.
    func testV1ModelsWorkWithCurrentSchema() async throws {
        let container = try makeTestContainer()

        try await MainActor.run {
            let context = container.mainContext

            // Insert a Clipping
            let clipping = ClipsmithSchemaV2.Clipping(content: "test clipping")
            context.insert(clipping)

            // Insert a Snippet
            let snippet = ClipsmithSchemaV2.Snippet(name: "test snippet", content: "let x = 1")
            context.insert(snippet)

            try context.save()

            let clippings = try context.fetch(FetchDescriptor<ClipsmithSchemaV2.Clipping>())
            let snippets = try context.fetch(FetchDescriptor<ClipsmithSchemaV2.Snippet>())

            XCTAssertEqual(clippings.count, 1, "Clipping should be persisted with the current schema")
            XCTAssertEqual(snippets.count, 1, "Snippet should be persisted with the current schema")
        }
    }

    // MARK: - V3

    func testV3SchemaHasThreeModels() {
        XCTAssertEqual(ClipsmithSchemaV3.models.count, 3)
        XCTAssertFalse(ClipsmithSchemaV3.models.contains { $0 == ClipsmithSchemaV1.GistRecord.self })
    }

    func testMigrationPlanEndsAtV3() {
        XCTAssertTrue(ClipsmithMigrationPlan.schemas.last == ClipsmithSchemaV3.self)
        XCTAssertEqual(ClipsmithMigrationPlan.stages.count, 2)
    }

    /// Review Focus 5: a V2 store holding Gist records opens under V3 and keeps the rest.
    func testV2StoreWithGistRecordsMigratesToV3() async throws {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "migration-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }

        // Seed a V2 store.
        do {
            let v2Schema = Schema(ClipsmithSchemaV2.models)
            let v2 = try ModelContainer(for: v2Schema,
                                        configurations: [ModelConfiguration(schema: v2Schema, url: url)])
            try await MainActor.run {
                let ctx = v2.mainContext
                ctx.insert(ClipsmithSchemaV1.GistRecord(gistID: "g1", gistURL: "https://gist.github.com/g1", filename: "a.txt"))
                ctx.insert(ClipsmithSchemaV1.Snippet(name: "keep", content: "x"))
                ctx.insert(ClipsmithSchemaV2.PromptLibraryItem(id: "p", title: "P", content: "c", category: "coding", version: 1))
                try ctx.save()
            }
        }

        // Reopen with the migration plan at V3.
        let v3Schema = Schema(ClipsmithSchemaV3.models)
        let v3 = try ModelContainer(for: v3Schema,
                                    migrationPlan: ClipsmithMigrationPlan.self,
                                    configurations: [ModelConfiguration(schema: v3Schema, url: url)])
        try await MainActor.run {
            let ctx = v3.mainContext
            XCTAssertEqual(try ctx.fetchCount(FetchDescriptor<ClipsmithSchemaV3.Snippet>()), 1)
            XCTAssertEqual(try ctx.fetchCount(FetchDescriptor<ClipsmithSchemaV3.PromptLibraryItem>()), 1)
        }
    }
}
