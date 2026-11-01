import XCTest
import SwiftData
@testable import Clipsmith

@MainActor
final class SnippetFilterTests: XCTestCase {
    private func snippets(in ctx: ModelContext) -> [ClipsmithSchemaV1.Snippet] {
        let a = ClipsmithSchemaV1.Snippet(name: "Config", content: "struct Config {}", language: "swift", tags: ["model"])
        let b = ClipsmithSchemaV1.Snippet(name: "drain", content: "kubectl drain", language: "bash")
        let c = ClipsmithSchemaV1.Snippet(name: "notes", content: "plain", language: nil)
        let d = ClipsmithSchemaV1.Snippet(name: "empty-lang", content: "x", language: "")
        [a, b, c, d].forEach(ctx.insert)
        return [a, b, c, d]
    }

    /// Review Focus 4: nil / empty languages appear under "All" and create no chip.
    func testLanguagesIgnoreNilAndEmpty() throws {
        let container = try makeTestContainer()
        let ctx = container.mainContext
        let opts = SnippetFilter.languages(in: snippets(in: ctx))
        XCTAssertEqual(opts.map(\.id), ["bash", "swift"])
    }

    func testApplyByLanguage() throws {
        let container = try makeTestContainer()
        let ctx = container.mainContext
        let all = snippets(in: ctx)
        XCTAssertEqual(SnippetFilter.apply(all, query: "", language: "swift").map(\.name), ["Config"])
        XCTAssertEqual(SnippetFilter.apply(all, query: "", language: nil).count, 4)
    }

    func testApplyByQueryMatchesNameContentTags() throws {
        let container = try makeTestContainer()
        let ctx = container.mainContext
        let all = snippets(in: ctx)
        XCTAssertEqual(SnippetFilter.apply(all, query: "MODEL", language: nil).map(\.name), ["Config"])
        XCTAssertEqual(SnippetFilter.apply(all, query: "kubectl", language: "swift").count, 0)
    }
}
