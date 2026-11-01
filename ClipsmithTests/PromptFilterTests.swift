import XCTest
import SwiftData
@testable import Clipsmith

@MainActor
final class PromptFilterTests: XCTestCase {
    private var container: ModelContainer!

    override func setUp() async throws {
        try await super.setUp()
        container = try makeTestContainer()
    }

    private func prompts() -> [ClipsmithSchemaV2.PromptLibraryItem] {
        let ctx = container.mainContext
        let a = ClipsmithSchemaV2.PromptLibraryItem(id: "a", title: "Analyze Logs", content: "logs", category: "analysis", version: 1)
        let b = ClipsmithSchemaV2.PromptLibraryItem(id: "b", title: "Add Error Handling", content: "errors", category: "coding", version: 1)
        let m = ClipsmithSchemaV2.PromptLibraryItem(id: "m", title: "Weekly Review", content: "review", category: "My Prompts", version: 1, isUserCreated: true)
        [a, b, m].forEach(ctx.insert)
        return [a, b, m]
    }

    func testOptionsPutMineFirstThenCategories() {
        let all = prompts()
        XCTAssertEqual(PromptFilter.options(in: all).map(\.id), ["mine", "analysis", "coding"])
        XCTAssertEqual(PromptFilter.options(in: all).first?.label, "My Prompts")
    }

    func testChipMine() {
        XCTAssertEqual(PromptFilter.apply(prompts(), query: "", chip: .mine).map(\.id), ["m"])
    }

    func testChipAndHashQueryBothApply() {
        let all = prompts()
        XCTAssertEqual(PromptFilter.apply(all, query: "#coding error", chip: nil).map(\.id), ["b"])
        XCTAssertEqual(PromptFilter.apply(all, query: "#coding", chip: .category("analysis")).count, 0)
        XCTAssertEqual(PromptFilter.apply(all, query: "#my", chip: nil).map(\.id), ["m"])
    }

    func testChipIDRoundTrip() {
        XCTAssertEqual(PromptFilter.Chip(id: "mine"), .mine)
        XCTAssertEqual(PromptFilter.Chip(id: "coding"), .category("coding"))
    }
}
